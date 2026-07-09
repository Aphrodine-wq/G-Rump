# G-Rump Architecture Summary

Short reference for contributors on key architecture decisions.

## Source Organization

```
Sources/GRump/
├── App/                        # Entry point, AppRootView gate, AppDelegate
├── Models/                     # Core types, GRumpDefaults, SwiftData models
├── ViewModels/                 # ChatViewModel + 13 focused extensions
│   ├── ChatViewModel.swift     # Core view model (~18K, property declarations)
│   ├── +AgentLoop              # Agent loop, fast reply, retry, intent detection
│   ├── +AgentPostRun           # Post-run cleanup and follow-up
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
│   ├── Chat/                   # Chat input, messages, code blocks, diffs
│   ├── Settings/               # 21 settings tabs in 6 groups + extensions
│   ├── Onboarding/             # 6-step first-run flow
│   ├── Panels/                 # 18 IDE panels
│   ├── Components/             # Reusable UI components
│   ├── Layout/                 # Sidebar, main layout shells
│   ├── Overlays/               # Modals, keyboard shortcut overlay
│   └── ...                     # DevTools, Git, Terminal, etc.
├── Services/
│   ├── AI/                     # Multi-provider (Anthropic, OpenAI, Google, OpenRouter)
│   ├── MCP/                    # Model Context Protocol client & server
│   ├── ToolExecution/          # 153 tool defs + executors by domain
│   ├── Apple/                  # Spotlight, SecureEnclave, FocusFilter, Apple Intelligence
│   ├── Developer/              # LSP, CodeApply, WritingTools
│   └── System/                 # ConnectionMonitor, GlobalHotkey, Sparkle
├── Intelligence/
│   ├── Memory/                 # MemoryStore, ActivityStore, MemoryGraph
│   ├── Brain/                  # Vault (markdown notes), config, paths
│   ├── Mind/                   # MIND.md identity + ConscienceGate values
│   ├── Daemon/                 # Autonomous goal loop (scratch-branch, gated)
│   ├── Eyes/                   # Opt-in screen perception (off by default)
│   ├── Suggestions/            # SuggestionEngine, types, lifecycle
│   ├── CodeIntel/              # AmbientCodeAwareness, ContextResolver
│   └── Analysis/               # CognitiveLoopDetector, ConfidenceCalibration
├── Utilities/                  # ThemeManager, DesignTokens, parsers, logger
└── Resources/                  # Skills, assets, localization, privacy manifest
```

## Onboarding (pre-app)

Onboarding runs **before** the main app. It never appears inside the Chat Interface.

- **Gate:** `AppRootView` checks `HasCompletedOnboarding` (UserDefaults). If `false`, it shows only `OnboardingView` (full-screen). Sidebar and chat are not shown until onboarding is finished.
- **Flow:** Splash → (if not completed) OnboardingView (3 slides, "Finish onboarding" / "Open Settings") → on finish, `HasCompletedOnboarding = true` → main app (`ContentView` with sidebar + chat).
- **Existing users:** If the user already has an API key (e.g. after upgrade), `AppRootView.onAppear` sets `HasCompletedOnboarding = true` so they are not blocked.

## Settings (tabbed)

Settings are split into **tabs** instead of a single long scroll.

- **Tabs:** 21 tabs across 6 disclosure groups — providers/models, project, behavior, tools, MCP, skills, soul, brain, memory, security, appearance, notifications, shortcuts, data, privacy, and about. See `SettingsTab.swift`.
- **UI:** `SettingsView` uses `NavigationSplitView`: sidebar list of tabs, detail shows the selected section. Same bindings and behavior as before; only the layout is tabbed.
- **Opening to a tab:** Callers can pass `initialTab: SettingsTab?` (e.g. `.model`) so the sheet opens on that tab (e.g. from the chat toolbar model badge).

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
- **⌘L** Focus message input  
- **⌘E** Export current conversation as Markdown  

Shortcuts work from both sidebar and detail. Listed in Help → Keyboard Shortcuts and in tooltips (e.g. sidebar Settings button).
