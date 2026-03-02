# G-Rump

G-Rump is a native macOS AI coding agent with 100+ tools, multi-provider AI, IDE intelligence panels, and deep system integration. Built with Swift and SwiftUI for macOS 14+.

## Features

- **Multi-Provider AI** — Anthropic, OpenAI, Ollama, OpenRouter, and on-device CoreML models
- **100+ Tools** — File, shell, git, docker, browser, cloud deploy, Apple-native (Spotlight, Keychain, Calendar, OCR, xcodebuild), and more
- **IDE Panels** — 17 built-in panels: File Navigator, Git, Tests, Assets, Localization, Profiling, Logs, Terminal, App Store Tools, Apple Docs
- **Skills System** — 40+ bundled SKILL.md files (SwiftUI, async/await, Kubernetes, code review, etc.) plus custom project skills
- **SOUL.md** — Define global and per-project AI personality with templates
- **MCP Integration** — 58 pre-configured MCP servers with Keychain-backed credential vault
- **Agent Modes** — Chat, Plan, Build, Debate, Spec — each with tailored behavior
- **LSP Integration** — Live SourceKit-LSP diagnostics with error/warning badges
- **Themes** — Light, Dark, and Fun themes (Cursor, ChatGPT, Claude, Gemini, Kiro)
- **Layout Customization** — Zen Mode, Activity Bar, customizable panels, keyboard shortcuts

## Quick Start

```bash
# Build and run (debug)
make run

# Build release .app bundle
make app

# Build release .app + .dmg
make dmg

# Reset app state for fresh-boot testing
make reset
```

Or double-click `G-Rump.command` to build and launch.

Requires **macOS 14+** and **Swift 5.9+**.

## Exec Approvals

`system_run` executes shell commands with user-controlled security:

- **Config**: `~/Library/Application Support/GRump/exec-approvals.json`
- **Levels**: Deny (default), Ask, Allowlist, Allow
- When **Ask** is on, a dialog lets you choose: Run Once, Always Allow, or Deny

Configure in **Settings → Security**.

## Project Config

Add `.grump/config.json` in your project root:

```json
{
  "model": "anthropic/claude-3.7-sonnet",
  "systemPrompt": "Custom instructions for this project…",
  "toolAllowlist": ["read_file", "run_command", "web_search"],
  "projectFacts": ["Uses Swift 5.9", "SwiftLint enabled"],
  "maxAgentSteps": 30,
  "contextFile": ".grump/context.md"
}
```

Add `.grump/context.md` for persistent project context injected into every conversation.

## Workflow Presets

**Settings → AI & Model → Workflow Presets** — one-click presets for Refactor, Debug, Read-only research, Extended run (150 steps), and more.

## Permissions (macOS)

- **Notifications** — System Settings → Notifications → G-Rump
- **Screen Recording** — System Settings → Privacy & Security → Screen Recording
- **Accessibility** — System Settings → Privacy & Security → Accessibility

## Distribution

See [DISTRIBUTION.md](DISTRIBUTION.md) for packaging, signing, and notarization instructions.
