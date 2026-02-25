# G-Rump — Release Notes

## v1.0.0 — Initial Release (2026-02-24)

**G-Rump** is a native macOS AI coding agent built with Swift & SwiftUI for macOS 14+.
This is the inaugural public release.

---

### ✨ Features

| Category | Highlights |
|---|---|
| **Multi-Provider AI** | Anthropic, OpenAI, Ollama, OpenRouter, and on-device CoreML inference |
| **100+ Built-in Tools** | File I/O, shell, git, Docker, browser automation, cloud deploy, plus Apple-native tools (Spotlight, Keychain, Calendar, OCR, xcodebuild) |
| **17 IDE Panels** | File Navigator, Git, Tests, Assets, Localization, Profiling, Logs, Terminal, App Store Tools, Apple Docs, and more |
| **Skills System** | 40+ bundled `SKILL.md` files (SwiftUI, async/await, Kubernetes, code review, etc.) with support for custom project skills |
| **SOUL.md** | Define global and per-project AI personality via templates |
| **MCP Integration** | 58 pre-configured MCP servers with Keychain-backed credential vault |
| **Agent Modes** | Chat, Plan, Build, Debate, Spec — each with tailored behavior |
| **LSP Integration** | Live SourceKit-LSP diagnostics with inline error/warning badges |
| **Themes** | Light, Dark, and Fun themes (Cursor, ChatGPT, Claude, Gemini, Kiro) |
| **Layout** | Zen Mode, Activity Bar, customizable panel layout, keyboard shortcuts |

### 🏗️ Architecture

- **Onboarding gate** — `AppRootView` shows a 3-slide onboarding flow before the main app; existing users with API keys skip it automatically.
- **Tabbed Settings** — Account, Appearance, Model, Project, Behavior, Tools, About — accessible via `NavigationSplitView` with deep-link support (`initialTab`).
- **250 Hz frame loop** — `FrameLoopService` drives a high-frequency update loop for responsive UI; actual display is bounded by 60/120 Hz. Optional FPS overlay for profiling.
- **Performance** — Cached markdown parsing, `LazyVStack` lists, `.drawingGroup()` for streaming rows.

### 🔧 CI / CD Pipeline

The continuous integration pipeline (GitHub Actions) was stood up and hardened across multiple iterations:

- GitHub Actions workflow (`ci.yml`) on every push to `main`.
- Separated build and test steps for clearer diagnostics.
- Max CPU parallelism (`-Xswiftc -j$(sysctl -n hw.ncpu)`) and Xcode caching.
- Test timeouts slashed to prevent CI hangs (tool dispatch tests rewritten with static registry).
- Release build re-enabled on every push after optimizations brought total time under 10 minutes.
- Signing key files added to `.gitignore` for security.

### 🧪 Tests

- **10 test files** covering tool dispatch, AI service configuration, skill loading, and view models.
- `ToolDispatchTests` rewritten to use a static registry (no live tool execution) for fast, deterministic CI runs.
- Correct assertions for `OpenRouterService` timeouts and graceful skipping of built-in skills in CI.

### 📦 Distribution

- `make run` — debug build and launch
- `make app` — release `.app` bundle
- `make dmg` — release `.app` + `.dmg` disk image
- `G-Rump.command` — double-click launcher
- See [DISTRIBUTION.md](DISTRIBUTION.md) for signing & notarization.

### 📋 Full Commit History

| Date | Commit | Description |
|---|---|---|
| 2026-02-24 | `f014a7c` | Initial commit: G-Rump MAC OS project |
| 2026-02-24 | `2d58bb2` | Update Skill, ToolDefinitions, and ToolDispatchTests |
| 2026-02-24 | `9a6198b` | Fix test compilation errors |
| 2026-02-24 | `55d7af9` | CI: bump timeout to 35 min, split test build/run |
| 2026-02-24 | `a8c37b9` | Fix(ci): remove 10-minute timeout limit on test step |
| 2026-02-24 | `1ab4f2f` | Fix(tests): add 5 s timeout per tool call to prevent CI hang |
| 2026-02-24 | `bcd364e` | CI: optimize build pipeline — collapse builds, add parallelism |
| 2026-02-24 | `e514207` | CI: slash build to < 10 min — drop release build, run tests only |
| 2026-02-24 | `b077ab3` | Test: slash tool dispatch timeouts from 5 s to 0.5 s per tool |
| 2026-02-24 | `9ba003d` | CI: optimize build for < 10 min — max CPU, caching, faster timeouts |
| 2026-02-24 | `ba7926e` | Test: speed up ToolDispatchTests with 10 ms timeout race |
| 2026-02-24 | `4d82634` | Fix: rewrite ToolDispatchTests to use static registry |
| 2026-02-24 | `0b87a34` | Fix: correct test assertions for CI |
| 2026-02-24 | `ee46755` | CI: enable release build on every push to main |
| 2026-02-24 | `7e5d30e` | Chore: add signing key files to .gitignore |

---

### System Requirements

- **macOS 14+ (Sonoma)**
- **Swift 5.9+**
- Xcode 15+ (for building from source)

---

*Built with ❤️ in Swift & SwiftUI.*
