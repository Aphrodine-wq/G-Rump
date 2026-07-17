# G-Rump Architecture Summary

Short reference for contributors on key architecture decisions.

## Source Organization

```
Sources/GRump/
├── App/                        # Entry point, AppRootView gate, AppDelegate
├── Models/                     # Core types, GRumpDefaults, SwiftData models
├── ViewModels/                 # ChatViewModel + 15 focused extensions
│   ├── ChatViewModel.swift     # Core view model (~18K, property declarations)
│   ├── +AgentLoop              # Agent loop, fast reply, retry, intent detection
│   ├── +AgentPostRun           # Post-run cleanup and follow-up
│   ├── +AgentVerification      # Completion gate + auto-verify at run end
│   ├── +Compaction             # Rolling context compaction, pinned task framing
│   ├── +ExportImport           # Export (JSON, Markdown) and import
│   ├── +Helpers                # API message building, token estimation
│   ├── +Conscience             # Fail-closed gate ahead of mutating tools
│   ├── +Memory                 # Memory retrieval and injection
│   ├── +Messages               # Message management
│   ├── +Persistence            # Conversation save/load/flush
│   ├── +PromptBuilding         # System prompt construction per mode
│   ├── +Streaming              # Streaming event handling
│   ├── +ThinkingParser         # <think> block extraction
│   ├── +ToolExecution          # Tool dispatch and parallel execution
│   └── +UIState                # UI state management
├── Views/                      # SwiftUI views (zero loose files)
│   ├── Chat/                   # Chat input, messages, code blocks, diffs, build toolbar
│   ├── Settings/               # 21 settings tabs in 7 groups + Settings{} scene root
│   ├── Onboarding/             # 6-step first-run flow (typed steps + gating)
│   ├── Welcome/                # Xcode-style welcome window (recents, open/clone/new)
│   ├── Profile/                # You | Your Agent (developer profile + SOUL editor)
│   ├── Panels/                 # 20 IDE panels incl. build console + learning
│   ├── Components/             # Reusable UI components
│   ├── Layout/                 # Sidebar, main layout shells, ⌘0 navigator pane
│   ├── Overlays/               # Modals, keyboard shortcut overlay
│   └── ...                     # DevTools, Git, Terminal, etc.
├── Services/
│   ├── AI/                     # Multi-provider (Anthropic, OpenAI, Google, OpenRouter, Ollama)
│   ├── MCP/                    # Model Context Protocol client & server
│   ├── ToolExecution/          # 160 tool defs + executors by domain
│   ├── Apple/                  # Spotlight, SecureEnclave, FocusFilter, Apple Intelligence
│   ├── Developer/              # LSP, BuildService, XcodeProjectInspector, CodeApply
│   └── System/                 # ProjectStore, ConnectionMonitor, GlobalHotkey, Sparkle
├── Intelligence/
│   ├── Memory/                 # MemoryStore, ActivityStore, MemoryGraph
│   ├── Brain/                  # Vault (markdown notes), config, paths
│   ├── Mind/                   # MIND.md identity + ConscienceGate values
│   ├── Daemon/                 # Autonomous goal loop (scratch-branch, gated)
│   ├── Eyes/                   # Opt-in screen perception (off by default)
│   ├── Learning/               # OutcomeLedger, LessonStore, ReflectionEngine, skill proposals
│   ├── Suggestions/            # SuggestionEngine, types, lifecycle
│   ├── CodeIntel/              # AmbientCodeAwareness, ContextResolver
│   └── Analysis/               # CognitiveLoopDetector, ConfidenceCalibration
├── Utilities/                  # ThemeManager, DesignTokens, parsers, logger
└── Resources/                  # Skills, assets, localization, privacy manifest
```

## Onboarding (pre-app) + Welcome window

Onboarding runs **before** the main app. It never appears inside the Chat Interface.

- **Gate:** `AppRootView` checks `HasCompletedOnboarding` (UserDefaults). If `false`, it shows only `OnboardingView` (full-screen). Sidebar and chat are not shown until onboarding is finished.
- **Flow:** Splash → six typed steps (`OnboardingStep`: welcome → provider → model → skills → appearance → security) with a pure `canAdvance` gate — welcome needs privacy consent, provider needs a saved key or an explicit "I'll add a key later" deferral. Skill packs apply exactly once at completion via `SkillPack.mergedAllowlist` — a UNION into any existing allowlist, so onboarding can never wipe a returning user's skills.
- **Existing users:** If the user already has an API key (e.g. after upgrade), `AppRootView.onAppear` sets `HasCompletedOnboarding = true` so they are not blocked.
- **Welcome window:** After onboarding (and on any launch with no project open, gated by `ShowWelcomeWindowOnLaunch`), a 780×480 `Window` scene (id `"welcome"`, ⇧⌘1) offers Open / Clone / New Project plus pinned recents from `ProjectStore` (`~/.grump/recent-projects.json`). Every open path funnels through `ChatViewModel.setWorkingDirectory`, which feeds `ProjectStore`.

## Settings (window scene)

- **Scene:** On macOS Settings is a real `Settings{}` scene (`SettingsSceneRoot`) — native ⌘, and app-menu item, min 940×640 with detail content capped at 720pt. iOS keeps the sheet.
- **Entry points:** Legacy callers still flip `state.showSettings`; `ContentView` bridges that into `openSettings()`. A requested tab rides `SettingsRouter.pendingTab`, which `SettingsView` consumes on appear and live via `onReceive` (the window persists across opens).
- **Tabs:** 21 tabs across 7 disclosure groups — Account · AI · Project (project/tools/MCP/security) · Agent (skills/soul/brain/memory) · Appearance · General · About. See `SettingsTab.swift`.

## Build engine (build → run → logs)

- **`BuildService`** (`Services/Developer/`) drives `xcodebuild` (or `swift build` for SPM packages) for the open project: a legal state machine `idle → building → succeeded/failed/cancelled`, with a run intent continuing `succeeded → installing → launching → running(app) → idle`. Console output streams through chunk-safe line buffering into a 10k-line ring buffer with 100ms/50-line batched flushes; issues parse via `BuildErrorParserEngine` on completion.
- **`XcodeProjectInspector`** owns nonisolated project parsing plus `buildSettings()` (`xcodebuild -showBuildSettings -json`, 10s watchdog) — the product path/bundle id the run pipeline installs and launches.
- **Run pipeline:** `simctl bootstatus -b` → `simctl install` → `simctl launch --terminate-running-process` → a second process streams the app's `log stream` into the same console. Stop kills the stream and terminates the app. Step seams are injectable for tests.
- **Surfaces:** the build toolbar above the chat (⌘R / ⌘⇧., project/scheme/destination chips, status pill), the Build dock panel (Log + Issues tabs, Fix-with-G-Rump, Reveal in Navigator, `xed --line`), and the ⌘0 left navigator with `FileTreeService.expandTo` for reveals. Failures auto-open the console; the agent drives the same loop through `xcrun_simctl` (list/boot/bootstatus/install/launch/terminate/app_log).

## 250fps target (high-frequency loop + smooth display)

The app targets a **250Hz internal update loop** and smooth display output (60/120Hz limited by the display).

- **Loop:** `FrameLoopService` runs a 250Hz timer (every 4ms) on the main thread when the app is active. It does minimal work per tick (increment tick count). Start/stop is tied to scene phase in `AppRootView`.
- **Display:** Actual frame presentation is still bounded by the display refresh rate (60 or 120Hz ProMotion). The 250Hz loop is for driving time-based state and keeping the app responsive; views can observe `frameLoop.tick` if needed.
- **FPS overlay:** Optional overlay (enable with UserDefaults `ShowFPSOverlay = true`) shows the measured loop rate in Hz.
- **Performance:** Heavy work is avoided in view bodies (e.g. markdown parsing in `MarkdownTextView` is cached and only runs when text changes). Message and conversation lists use `LazyVStack`; streaming row uses `.drawingGroup()` to reduce redraw cost.

## Keyboard shortcuts

- **⌘N** New Chat  
- **⌘,** Settings  
- **⌘.** Stop generation  
- **⌘R** Run (build, then run-to-simulator when the destination is a sim)  
- **⌘⇧.** Stop build / running app  
- **⌘0** Toggle project navigator  
- **⇧⌘1** Welcome window  
- **⌘L** Focus message input  
- **⌘E** Export current conversation as Markdown  

Shortcuts work from both sidebar and detail. Listed in Help → Keyboard Shortcuts and in tooltips (e.g. sidebar Settings button).
