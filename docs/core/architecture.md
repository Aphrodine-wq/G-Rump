# Architecture

G-Rump is a native macOS AI coding agent built with Swift and SwiftUI, targeting macOS 14+.

## Entry Points

- **`GRumpApp.swift`** — `@main` App struct. Initializes `ThemeManager`, sets up `WindowGroup`, injects environment objects, defines `CommandGroup` menu items and keyboard shortcuts.
- **`AppRootView.swift`** — Gates onboarding. Shows `ContentView` after first-run setup completes.
- **`ContentView.swift`** — Main app shell. Manages layout (sidebar, chat, right panel), service initialization, Spotlight indexing, LSP diagnostics, and notification observers.

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
| **ViewModels** | `ChatViewModel` — orchestrates conversations, tool calls, streaming |
| **Services** | Singletons for AI providers, LSP, MCP, voice input, connection monitoring |
| **Models** | `Conversation`, `Message`, `Tool`, `Skill`, `MCPServerConfig` |
| **Storage** | SwiftData for conversations; `UserDefaults` for settings; JSON files for exec approvals, skills |

## Package Structure

```
Sources/GRump/
├── GRumpApp.swift              # App entry
├── ContentView.swift           # Main shell
├── ThemeManager.swift          # Themes, palettes, accent colors
├── DesignTokens.swift          # Typography, Spacing, Radius, Border, Anim
├── ChatViewModel.swift         # AI orchestration
├── Views/
│   ├── Chat/                   # Message views, empty states, input
│   ├── Settings/               # Settings tab views
│   ├── Panels/                 # Right panel manager
│   ├── Layout/                 # Panel layout, sidebar
│   └── Overlays/               # Modals, keyboard shortcuts
├── Services/                   # AI providers, LSP, MCP, tools
├── Models/                     # Data models
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
