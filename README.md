# G-Rump

**An autonomous AI coding agent for macOS** -- 54K lines of Swift, a persistent cross-session memory, 100+ local tools, MCP integration, agent modes, and an approval-gated autonomous daemon.

G-Rump is a native macOS AI coding agent built with Swift and SwiftUI, powered by **Anthropic Claude (default), OpenAI, Google Gemini, or OpenRouter** with your own API keys. It executes over 100 local tools (file operations, shell, git, Docker, browser, Apple-native APIs), implements the full Model Context Protocol, and runs an autonomous daemon that works coding goals on a scratch branch behind human approval gates.

Its defining feature is a **persistent, cross-session brain**: G-Rump accumulates experience, recalls the most relevant memories *within a fixed token budget*, and *forgets* stale context on purpose -- a memory that behaves like a brain rather than an append-only vector log.

> Originally built for the Global AI Hackathon with Qwen Cloud -- **Track 1: MemoryAgent**. The optional [`backend/`](./backend) proxy still speaks Qwen/DashScope; the app now calls providers directly by default.

---

## Features

- **Multi-Provider AI** -- Anthropic Claude (Opus 4.8 default; Fable 5, Sonnet 5, Haiku 4.5), OpenAI GPT-5.x, Google Gemini, and OpenRouter passthroughs, with provider-aware task routing across the tiers
- **Persistent Cognitive Memory** -- cross-session memory that ranks by relevance x recency x salience, recalls within a fixed token budget, and consolidates/forgets stale memories (Track 1: MemoryAgent)
- **Autonomous Daemon** -- works pending goals on a scratch branch with a Conscience safety gate and per-write approval
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
├── backend/                    # Node.js Qwen proxy (deploys on Alibaba Cloud)
│   ├── server.js               # Express API: health, chat, embeddings
│   ├── alibaba.js              # The Alibaba Cloud / Qwen (DashScope) call site
│   ├── Dockerfile              # Container for Alibaba ECS / Function Compute
│   └── README-DEPLOY.md        # Alibaba Cloud deployment runbook
├── Tests/                      # Swift test suite
├── Makefile                    # Build automation
├── Package.swift               # Swift Package Manager manifest
└── project.yml                 # XcodeGen project definition
```

## Backend

A minimal, stateless Node.js + Express proxy to **Qwen on Alibaba Cloud** (DashScope). All Alibaba Cloud calls live in `backend/alibaba.js`. Endpoints: `/api/health`, `/api/v1/chat/completions` (SSE streaming, tool calls preserved), `/api/v1/embeddings`. Deploy it on Alibaba Cloud ECS or Function Compute -- see [`backend/README-DEPLOY.md`](./backend/README-DEPLOY.md).

```bash
cd backend
npm install
QWEN_API_KEY=sk-... npm start   # http://localhost:3042
npm test                        # Run tests
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
  "model": "qwen-coder-plus",
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
| Backend | Node.js / Express (optional legacy Qwen proxy) |
| Models | Claude Opus 4.8 (default) / Fable 5 / Sonnet 5 / Haiku 4.5 · GPT-5.2 · Gemini 3 Pro / 2.5 Flash · OpenRouter routes |
| Embeddings | Qwen text-embedding (Apple NLEmbedding offline fallback) |
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

## Testing & evaluation

**You don't need a Mac to verify G-Rump runs on Qwen.** With a Qwen key on any OS:

```bash
node scripts/judge-verify.mjs   # proves chat + multi-turn tool calling + embeddings on Qwen
node scripts/agent-eval.mjs     # scores Qwen on a 4-task agent battery (real tool loop, mock repo)
```

On macOS, the full automated suites: `swift test -j 12` (1,437 checks incl. the
cognitive-memory eval) and `cd backend && npm test`. Full methodology and a
no-Mac testing path are in [docs/EVALS.md](./docs/EVALS.md).

## License

MIT -- see [LICENSE](./LICENSE).
