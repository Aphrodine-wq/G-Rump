# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

G-Rump is an autonomous AI coding agent macOS/iOS app written in Swift (SwiftUI), multi-provider: **Anthropic (default), OpenAI, Google, and OpenRouter**. It provides chat-based AI assistance with 150+ local file system, shell, git, and system control tools, a persistent cognitive memory, and an approval-gated autonomous daemon. Default model: **claude-opus-4-8**; Fable 5 is premium and never auto-routed. The app calls providers directly — there is no backend.

### AI Providers

- `AIProvider` (AIProviders.swift): `.anthropic` / `.openAI` / `.google` / `.openRouter`. API keys live in the **Keychain only** (one account per provider via `keychainAccount`); `ProviderConfiguration` excludes `apiKey` from Codable so keys never touch UserDefaults.
- Model catalog is the single data file `AIModelCatalog.swift`. Registry default is `claude-opus-4-8`; `ModelRouter` picks provider-aware chains and never auto-routes to Fable 5.
- Dispatch: `MultiProviderAIService` — native wire formats for Anthropic + Google, `OpenAICompatibleService` transport for OpenAI + OpenRouter. Anthropic requests omit temperature (Claude 4.7+/5 reject it) and pin `anthropic-version: 2023-06-01`.
- `ProviderMigration` runs once (flag `ProviderMigration_v1`) from `AIModelRegistry.init` to map Qwen-era persisted state; never touch `AIModelRegistry.shared` inside it (deadlock).
- `AIKeyValidator` probes a just-saved key with a cheap authed GET (`/models`; OpenRouter `/key`) and reports valid / invalid / indeterminate inline in Settings and onboarding. Keys are saved before the probe — a failed probe warns, it never blocks or un-saves.

## Build & Run Commands

### Swift (frontend)

```bash
make build            # Debug build (uses all CPU cores)
make build-release    # Optimized universal release build (arm64 + x86_64)
make run              # Build debug + run
make clean            # Remove .build and dist
swift test            # Run all tests (requires full Xcode SDK)
swift test --filter GRumpTests.ModelsTests                    # Run one test file
swift test --filter GRumpTests.ModelsTests/testMessageCreation  # Run one test method
```

The build uses Swift Package Manager. Dependencies resolve automatically on first build. The local `.build` directory is used (not `~/Library`) to avoid permission issues.

### Packaging

```bash
make app              # .app bundle in dist/
make dmg              # .app + .dmg
make sign             # Signed .app (needs DEVELOPER_ID env)
make package          # Signed .dmg (needs DEVELOPER_ID env)
make notarize         # Full distribution (needs DEVELOPER_ID, APPLE_ID, TEAM_ID, APP_PASSWORD)
```

### XcodeGen

`project.yml` defines the Xcode project (macOS app, iOS app, server CLI, test bundle, Xcode extension). Generate with `xcodegen generate` (requires `brew install xcodegen`).

## CI Rules

CI runs 3 jobs on push/PR to `main`: tests, lint, release build (plus notarized distribution on `v*` tags).

**Hard CI failure**: `print()` statements in `Sources/GRump/` — always use `GRumpLogger` instead (categories: `.general`, `.ai`, `.persistence`, `.skills`, `.memory`, `.proactive`, `.migration`, `.spotlight`, `.notifications`, `.coreml`, `.capture`, `.liveActivity`).

SwiftLint runs in strict mode. Force unwraps are warned (not blocked). `PrivacyInfo.xcprivacy` and `LICENSE` must exist.

## Architecture

### Swift App Structure (`Sources/GRump/`)

**Entry point**: `GRumpApp.swift` → `ContentView.swift` (main chat UI with sidebar). `AppDelegate.swift` enforces single-instance to prevent SQLite lock freezes. Additional macOS scenes: `Settings{}` (`SettingsSceneRoot` + `SettingsRouter` for tab routing — legacy `showSettings` flips are bridged to `openSettings()` in ContentView) and the `"welcome"` Window (⇧⌘1).

**ChatViewModel** is the central state manager, split into extensions:
- `ChatViewModel+Streaming.swift` — provider streaming responses (dispatched per provider)
- `ChatViewModel+ToolExecution.swift` — Tool dispatch, parallel execution, retry logic
- `ChatViewModel+Memory.swift` — Activity tracking, memory store
- `ChatViewModel+Messages.swift` — Message management
- `ChatViewModel+UIState.swift` — UI state management

**Agent modes**: `plan`, `fullStack` ("Build"), `spec` (see `AgentMode.swift`)

### Tool System (4 definition files + 6 execution files)

**Definitions** (`ToolDefs+*.swift`): JSON schema definitions split by domain — `FileOps`, `ShellSystem`, `GitDevOps`, `UtilsApple`. Master registry in `ToolDefinitions.swift` with `toolsForCurrentPlatform` (iOS filtering) and `toolsFiltered(allowlist:userDenylist:)`.

**Execution** (`ToolExec+*.swift`): Implementations split by domain — `FileOps`, `ShellSystem`, `GitDevOps`, `AppleNative`, `Utils`, `Extended`. Parallel dispatch via `executeToolCallsParallel` with exponential backoff (200ms/500ms/1s, 2 retries).

**XML tool call parsing**: `XMLToolCallParser.swift` handles models that emit inline XML instead of native `tool_calls` (three formats: `<execute>`, `<tool_call>`, `<function_call>`).

**Code apply**: `CodeApplyService.swift` gives code blocks an apply/reject/undo workflow. `InlineDiffCard.swift` renders unified diffs with LCS algorithm.

### MCP System (three layers)

1. **Client** (`MCPService.swift`): `MCPConnectionManager` (actor-based) maintains persistent connections. Three transports: `stdio` (macOS only), `http`, `websocket`. MCP tools injected as `mcp_<serverId>_<toolName>`. Config at `~/.grump/mcp-servers.json`. `MCPCredentialVault` injects secrets as env vars for stdio processes.

2. **Server Host** (`MCPServerHost.swift`): G-Rump exposes its own tools as an MCP server on TCP port `18790`. External clients (Claude Desktop, etc.) connect via `tools/list` + `tools/call`. `run_command` is refused for safety.

3. **Presets** (`MCPServerConfig.swift`): ~60 preconfigured one-click servers (GitHub, Postgres, Slack, Supabase, Figma, Playwright, Stripe, etc.).

### Skills System

Three scopes: `builtIn` (bundled `Resources/Skills/skill-*.md`), `global` (`~/.grump/skills/`), `project` (`.grump/skills/`). Project overrides global by ID. Each skill is a `SKILL.md` file with YAML frontmatter (`name`, `description`) + markdown body.

`Skill.relevanceScore(for:fileExtensions:)` scores skills against the active query + working directory file types for auto-suggestion.

### Soul System

AI personality via `~/.grump/SOUL.md` (global) and `.grump/SOUL.md` (project, overrides global). YAML frontmatter (`name:`, `version:`) + markdown body. Default persona is "Rump". Editable in Settings → Soul (or Profile → Your Agent).

### Developer Profile

`DeveloperProfile` (`~/.grump/profile.json`, edited in Profile → You) injects a capped block into the system prompt. Final prompt layer order: `[Mode][Skills][Mind][DevProfile][Soul][Base]` — built in `ChatViewModel+Helpers.effectiveAgentConfig()`. Empty profile injects nothing.

### Project + Build Engine

- `ProjectStore` (`Services/System/`): current project + pinned recents (`~/.grump/recent-projects.json`), kind detection (workspace > xcodeproj > Package.swift > plain). The ONE mutation point is `ChatViewModel.setWorkingDirectory` — every open path feeds it. The Welcome window (`Window` id `"welcome"`, ⇧⌘1, shown when onboarded with no project open) reads it.
- `BuildService` (`Services/Developer/`): ⌘R builds via xcodebuild/`swift build`; on a simulator destination a successful build continues installing → launching → running(app) with the app's `log stream` in the build console. ⌘⇧. stops. State machine transitions are legality-checked (`BuildPhase.isLegalTransition`). Failures auto-open the Build panel's Issues tab.
- `XcodeProjectInspector`: nonisolated project parsing + `xcodebuild -showBuildSettings -json` (10s watchdog) for product path/bundle id, cached per scheme|config.
- Surfaces: build toolbar above chat, `PanelTab.build` console (Log|Issues, Fix-with-G-Rump, Reveal in Navigator, `xed --line`), ⌘0 left navigator (`FileTreeService.expandTo` handles reveals). The agent drives the same loop via `xcrun_simctl` (bootstatus/install/launch/terminate/app_log).

### Key Services

- `OpenAICompatibleService` — parameterized OpenAI-compatible streaming transport (serves OpenAI and OpenRouter). Carries the tool-call-complete request body.
- `MultiProviderAIService` — per-provider dispatch: native Anthropic + Google wire formats, OpenAI/OpenRouter via the transport
- `LSPService` — Language Server Protocol / SourceKit-LSP integration
- `ExecApprovals` — Security approval workflow for shell commands
- `ConnectionMonitor` — `NWPathMonitor` + periodic health checks to `openrouter.ai` (30s interval). Exposes `.connected`/`.degraded`/`.disconnected` status.
- `GlobalHotkeyService` — Double-tap `⌃Space` (400ms window) opens `QuickChatPopover` (floating `NSPanel`). Requires Accessibility permission.
- `MenuBarAgent` — Menu bar extra showing project name, agent status, recent tools, proactive suggestions. Toggle: `ShowMenuBarExtra` UserDefaults key.
- `ProactiveEngine` — Cron-based suggestions (git poll 5min, end-of-day review 5:30pm, morning brief 8:30am). Toggle: `ProactiveEngineEnabled` UserDefaults.

### Persistence (dual-mode)

`SwiftDataModels.swift` has two code paths:
- **Xcode builds**: Full SwiftData `@Model` macros with CloudKit sync. Models: `SDConversation`, `SDMessage`, `SDChatThread`, `SDChatBranch`, `SDProject`, `SDMemoryEntry`.
- **SPM builds** (`GRUMP_SPM_BUILD`): Plain `Codable` classes backed by `GRumpPersistenceStore` (JSON file at `~/Library/Application Support/GRump/swiftdata_store.json`).

SwiftData `@Model` macros do not expand under `swift build`. This is by design.

### Data Models

`Models.swift`: `Message`, `ToolCall`, `Conversation`, `MessageThread`, `MessageBranch`. Supports linear, threaded, and branched conversation views.

## Key Conventions

- **Logging**: Use `GRumpLogger.<category>` (never `print()`). CI will reject `print()` statements.
- **Concurrency**: `@MainActor` on ChatViewModel, async/await throughout, `AsyncThrowingStream` for streaming, task groups for parallel tool execution. Strict concurrency is `complete` (set in Package.swift via `StrictConcurrency=complete`).
- **SwiftUI state**: `@EnvironmentObject` for app-wide sharing, `@Published` for reactive props, `@AppStorage` for UserDefaults persistence. Keychain for sensitive data (API keys).
- **Performance**: `LazyVStack` for lists, `.drawingGroup()` on streaming rows, cached markdown parsing. FPS overlay via `ShowFPSOverlay` UserDefaults key.
- **Platform**: `#if os(macOS)` / `#else` guards for platform-specific code. macOS 14+ / iOS 17+.
- **No sandbox**: App entitlements disable sandbox (required for shell execution, LSP, and file tools).

## Project Config

Per-project settings live in `.grump/config.json` or `grump.json` at the project root. `.grump/context.md` is auto-injected into the system prompt when present. Exec approval rules at `~/Library/Application Support/GRump/exec-approvals.json`.

### Full Reset (splash freeze, stuck state)

```bash
make reset
```

Without Make:

```bash
pkill -x GRump 2>/dev/null || true
defaults delete com.grump.app 2>/dev/null || true
rm -rf ~/.grump ~/Library/Application\ Support/GRump ~/Library/Application\ Support/com.grump.app
```

API keys (Keychain) are preserved.
