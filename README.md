# G-Rump

**AI Coding Agent for macOS** -- 54K lines of Swift, multi-model support, 100+ local tools, MCP integration, agent modes, skills system, and ambient code awareness.

G-Rump is a native macOS AI coding agent built with Swift and SwiftUI. It connects to multiple LLM providers (OpenRouter, Anthropic, OpenAI, Ollama, on-device CoreML), executes over 100 local tools (file operations, shell, git, Docker, browser, cloud deploy, Apple-native APIs), and implements the full Model Context Protocol for extensible tool use. Designed for developers who want a fast, private, macOS-native coding assistant with deep system integration.

---

## Features

- **Multi-Provider AI** -- Anthropic, OpenAI, Ollama, OpenRouter, and on-device CoreML models with tier-based access
- **100+ Local Tools** -- File, shell, git, Docker, browser, cloud deploy, Apple-native (Spotlight, Keychain, Calendar, OCR, xcodebuild), and more
- **MCP Client & Server** -- 58 pre-configured MCP servers (GitHub, Postgres, Slack, Supabase, Figma, Playwright, Stripe, etc.) with Keychain-backed credential vault. Also exposes tools as an MCP server on TCP port 18790
- **Agent Modes** -- Chat, Plan, Build, Debate, Spec, Parallel -- each with tailored execution strategies
- **IDE Panels** -- 17 built-in panels: File Navigator, Git, Tests, Assets, Localization, Profiling, Logs, Terminal, App Store Tools, Apple Docs
- **Skills System** -- 40+ bundled skill files (SwiftUI, async/await, Kubernetes, code review, etc.) plus custom global and per-project skills with relevance scoring
- **SOUL.md Personality** -- Define global and per-project AI personality with templates
- **Apple Intelligence Integration** -- Native macOS AI features where available
- **Ambient Code Awareness** -- Watches your project for changes and maintains context automatically
- **LSP Integration** -- Live SourceKit-LSP diagnostics with error/warning badges
- **Proactive Engine** -- Git polling (5 min), end-of-day review, morning brief
- **Themes** -- Light, Dark, and Fun themes (ChatGPT, Claude, Gemini, Kiro, Perplexity)
- **Layout Customization** -- Zen Mode, Activity Bar, customizable panels, keyboard shortcuts
- **Global Hotkey** -- Double-tap Ctrl+Space for floating quick chat

## Quick Start

```bash
# Build and run (debug)
make run

# Build release .app bundle
make app

# Build release .app + .dmg
make dmg

# Run tests
swift test --parallel

# Reset app state for fresh-boot testing
make reset
```

Or double-click `G-Rump.command` to build and launch.

Requires **macOS 14+** and **Swift 5.9+**.

## Architecture

```
G-Rump/
├── Sources/GRump/              # Swift application (54K+ LOC)
│   ├── GRumpApp.swift          # Entry point
│   ├── ContentView.swift       # Main chat UI with sidebar
│   ├── ChatViewModel+*.swift   # Central state manager (streaming, tools, memory, messages, UI)
│   ├── ToolDefs+*.swift        # Tool definitions by domain (FileOps, Shell, Git, Apple)
│   ├── ToolExec+*.swift        # Tool execution by domain
│   ├── MCPService.swift        # MCP client (stdio, http, websocket transports)
│   ├── MCPServerHost.swift     # MCP server (exposes tools to external clients)
│   ├── Skills/                 # Skills system (built-in, global, project scopes)
│   ├── Models.swift            # Message, ToolCall, Conversation, Thread, Branch
│   └── SwiftDataModels.swift   # Persistence (SwiftData for Xcode, JSON for SPM)
├── Resources/Skills/           # 40+ bundled SKILL.md files
├── backend/                    # Node.js + SQLite backend
│   ├── server.js               # Express API entry point
│   ├── auth.js                 # Google Sign-In, JWT, user creation
│   ├── db.js                   # SQLite (users, credits, tiers)
│   └── proxy.js                # OpenRouter proxying with credit deduction
├── Tests/                      # Swift test suite
├── Makefile                    # Build automation
├── Package.swift               # Swift Package Manager manifest
└── project.yml                 # XcodeGen project definition
```

## Backend

Node.js + Express server backed by SQLite. Handles auth, conversation persistence, credit management, and OpenRouter proxying.

```bash
cd backend
npm install
npm start         # http://localhost:3042
npm run dev       # Watch mode
npm test          # Run tests
```

## Exec Approvals

`system_run` executes shell commands with user-controlled security:

- **Config**: `~/Library/Application Support/GRump/exec-approvals.json`
- **Levels**: Deny (default), Ask, Allowlist, Allow
- When **Ask** is on, a dialog lets you choose: Run Once, Always Allow, or Deny

Configure in **Settings > Security**.

## Project Config

Add `.grump/config.json` in your project root:

```json
{
  "model": "anthropic/claude-3.7-sonnet",
  "systemPrompt": "Custom instructions for this project...",
  "toolAllowlist": ["read_file", "run_command", "web_search"],
  "projectFacts": ["Uses Swift 5.9", "SwiftLint enabled"],
  "maxAgentSteps": 30,
  "contextFile": ".grump/context.md"
}
```

Add `.grump/context.md` for persistent project context injected into every conversation.

## Distribution

Distributed outside the Mac App Store (requires shell execution, LSP, and file tools -- no sandbox):

- **Code signing** -- Developer ID certificate
- **Notarization** -- Apple notary service via `notarytool`
- **Packaging** -- DMG installer
- **Updates** -- Sparkle framework for in-app updates

```bash
make sign             # Signed .app (needs DEVELOPER_ID env)
make package          # Signed .dmg (needs DEVELOPER_ID env)
make notarize         # Full distribution (needs DEVELOPER_ID, APPLE_ID, TEAM_ID, APP_PASSWORD)
```

## CI/CD

GitHub Actions pipeline runs on push/PR to `main`:

- Swift build and test (`swift test --parallel`)
- SwiftLint strict mode (no `print()` statements -- use `GRumpLogger`)
- Backend tests (`npm test`)
- Release build with signing and notarization

## Tech Stack

| Component | Technology |
|-----------|-----------|
| Frontend | Swift 5.9+ / SwiftUI |
| Backend | Node.js / Express / SQLite |
| LLM Providers | OpenRouter, Anthropic, OpenAI, Ollama, CoreML |
| Protocol | Model Context Protocol (MCP) |
| Persistence | SwiftData (Xcode) / JSON (SPM) |
| LSP | SourceKit-LSP |
| Updates | Sparkle |
| CI | GitHub Actions |
| Platform | macOS 14+ (Sonoma) |

## macOS Permissions

- **Notifications** -- System Settings > Notifications > G-Rump
- **Screen Recording** -- System Settings > Privacy & Security > Screen Recording
- **Accessibility** -- System Settings > Privacy & Security > Accessibility (for global hotkey)

## License

Proprietary. All rights reserved.
