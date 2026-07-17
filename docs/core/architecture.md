# Architecture

G-Rump is a native macOS AI coding agent built with Swift and SwiftUI, targeting macOS 14+.

## Entry Points

- **`App/GRumpApp.swift`** — `@main` App struct. Initializes `ThemeManager`, sets up `WindowGroup`, injects environment objects, defines `CommandGroup` menu items and keyboard shortcuts.
- **`App/AppRootView.swift`** — Gates onboarding. Shows `ContentView` after first-run setup completes.
- **`App/ContentView.swift`** — Main app shell. Manages layout (sidebar, chat, right panel), service initialization, Spotlight indexing, LSP diagnostics, and notification observers.

## Data Flow

```
User Input → ChatInputView → ChatViewModel → AIService (provider router)
                                            → ToolExecutor (160 tools)
                                            → StreamingResponse → MessageListView
```

### Key Layers

| Layer | Responsibility |
|---|---|
| **Views** | SwiftUI views organized by feature (Chat, Settings, Panels, Overlays) |
| **ViewModels** | `ChatViewModel` + 15 focused extensions — orchestrates conversations, tool calls, streaming, verification |
| **Services** | Singletons for AI providers, LSP, MCP, voice input, connection monitoring |
| **Intelligence** | Memory, learning loop (OutcomeLedger, LessonStore, ReflectionEngine), daemon, conscience values |
| **Models** | `Conversation`, `Message`, `Tool`, `Skill`, `MCPServerConfig` |
| **Storage** | SwiftData for conversations; `UserDefaults` for settings; JSON files for exec approvals, skills |

## Package Structure

```
Sources/GRump/
├── App/                        # GRumpApp entry, AppRootView gate, ContentView shell
├── Models/                     # Core types, GRumpDefaults, SwiftData models
├── ViewModels/                 # ChatViewModel + 15 focused extensions
│   └── ChatViewModel+*         # AgentLoop, AgentVerification, Compaction, Streaming,
│                               # ToolExecution, PromptBuilding, Conscience, Memory, …
├── Views/
│   ├── Chat/                   # Message views, code blocks, diffs, input
│   ├── Settings/               # 21 settings tabs in 7 groups
│   ├── Onboarding/             # First-run flow
│   ├── Welcome/                # Welcome window (recents, open/clone/new)
│   ├── Panels/                 # 20 IDE dock panels
│   ├── Layout/                 # Sidebar, layout shells, project navigator
│   └── Overlays/               # Modals, keyboard shortcuts
├── Services/
│   ├── AI/                     # Anthropic, OpenAI, Google, OpenRouter, Ollama
│   ├── MCP/                    # MCP client & server
│   ├── ToolExecution/          # 160 tool defs + executors by domain
│   ├── Apple/                  # Spotlight, SecureEnclave, Apple Intelligence
│   ├── Developer/              # LSP, BuildService, CodeApply
│   └── System/                 # ProjectStore, ConnectionMonitor, hotkeys
├── Intelligence/
│   ├── Memory/                 # MemoryStore, ActivityStore, MemoryGraph
│   ├── Learning/               # OutcomeLedger, LessonStore, ReflectionEngine, skill proposals
│   ├── Brain/ Mind/ Daemon/    # Vault notes, identity + conscience, goal loop
│   └── Eyes/ Suggestions/ …    # Screen perception (opt-in), suggestions, code intel
├── Utilities/                  # ThemeManager, DesignTokens, parsers, logger
└── Resources/
    └── Skills/                 # Bundled SKILL.md files
```

## Dependencies

- **Sparkle** — Auto-update framework (direct distribution)
- **No other third-party Swift packages** — Everything else is built on Apple frameworks

## Threading Model

- All UI and service singletons are `@MainActor`
- Tool execution uses structured concurrency (`async/await`)
- LSP communication runs on a dedicated `DispatchQueue`
- Network monitoring uses `NWPathMonitor` on a background queue
