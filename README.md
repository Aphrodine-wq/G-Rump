# G-Rump

**The grumpy, open-source coding agentic harness for macOS.**

[![CI](https://github.com/Aphrodine-wq/G-Rump/actions/workflows/ci.yml/badge.svg)](https://github.com/Aphrodine-wq/G-Rump/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](./LICENSE)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black)
![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange)

G-Rump is a coding agentic harness — the agent loop, tool system, provider layer,
memory, and safety gates that let an LLM actually do work on your machine — shipped
as a native macOS app. Think Claude Code, Aider, or OpenHands, except it's 62K lines
of Swift instead of a terminal, it remembers what it learned last week, and it has
opinions about your code.

Bring a key from **Anthropic (default), OpenAI, Google, or OpenRouter**. Keys live in
the macOS Keychain, requests go straight to the provider, and there are no accounts,
no telemetry middleman, and no backend.

## Why another coding agent

- **Native macOS, not Electron, not a terminal.** Real SwiftUI, real Keychain, real
  Apple-native tools — Spotlight, OCR, Calendar, `xcodebuild`, `simctl`.
- **A brain, not a chat log.** Cross-session memory ranks by relevance × recency ×
  salience, recalls within a fixed token budget, and *forgets stale context on
  purpose*. It behaves like a memory, not an append-only vector dump.
- **Local-first and BYOK.** Your keys, your machine, your data. The app calls
  providers directly with their native wire formats.
- **A security model built for the job.** This app runs shell commands an LLM asked
  for. The [Security model](#security-model) section says exactly what stands between
  the model and your machine.
- **The grump.** `SOUL.md` and `MIND.md` define the agent's personality and values,
  globally and per project. The default persona is grumpy. That's a feature.

## What's in the harness

| | |
|---|---|
| Agent loop | Multi-turn streaming tool use, parallel tool execution, retries with backoff. Default 200 steps, configurable 5–1000 |
| Tools | **153 native tools** — files, shell, git, Docker, deploy, HTTP, SQLite, OCR/vision, Apple-native |
| MCP | Client (stdio / http / websocket) **and** server — 68 one-click presets, plus G-Rump exposes its own tools on TCP 18790 |
| Agent modes | Plan, Build, Spec — each swaps the system strategy |
| Providers | Anthropic, OpenAI, Google, OpenRouter — native Anthropic + Gemini wire formats, streaming tool calls everywhere |
| Models | Claude Opus 4.8 (default), Fable 5, Sonnet 5, Haiku 4.5, GPT-5.2, GPT-5.3-Codex, Gemini 3 Pro, and OpenRouter routes |
| Memory | 3-tier store (session / project / global), hybrid vector + keyword + recency recall, deliberate forgetting |
| Skills | 73 bundled `SKILL.md` skills in 21 packs, plus your own global and per-project skills with relevance scoring |
| IDE surface | 18 dock panels — project navigator, git, terminal, simulator, tests, logs, profiling — with live SourceKit-LSP diagnostics |
| Autonomy | An opt-in daemon that works queued goals on a scratch branch, behind approval gates, and never pushes |
| Tests | 1,400+ tests, SwiftLint strict, CI on every push |

## Quick start

**Download:** grab `G-Rump-<version>.zip` from the
[latest release](https://github.com/Aphrodine-wq/G-Rump/releases/latest), unzip, and
drag **G-Rump.app** to Applications. Until releases are notarized, macOS will warn on
first launch — use System Settings → Privacy & Security → **Open Anyway**, or clear
the quarantine flag: `xattr -dr com.apple.quarantine /Applications/G-Rump.app`.

**Or build from source** — macOS 14+ and Swift 5.9+ (Xcode or Command Line Tools):

```bash
git clone https://github.com/Aphrodine-wq/G-Rump.git
cd G-Rump
make run
```

Or double-click `G-Rump.command`. Onboarding asks for an API key — it's validated on
save and stored in the Keychain. Other useful targets:

```bash
make app              # release .app bundle
make zip              # downloadable .zip of the .app
swift test --parallel # the test suite
make reset            # wipe app state for a fresh-boot run (keeps your keys)
```

## Architecture

```
Sources/GRump/
├── App/           # entry point, app delegate, root views
├── Models/        # messages, tools, skills, agent modes, panels
├── ViewModels/    # ChatViewModel — the agent loop lives here (+AgentLoop, +ToolExecution, …)
├── Views/         # SwiftUI surfaces: chat, panels, settings, onboarding
├── Services/      # AI providers, tool execution, MCP, LSP, exec approvals
├── Intelligence/  # memory, brain/vault, daemon, analysis, eyes
├── Utilities/     # shared helpers
└── Resources/     # bundled skills, assets, privacy manifest
```

The flow: `runAgentLoop()` streams from the selected provider
(`MultiProviderAIService` — native Anthropic/Gemini formats,
OpenAI-compatible transport for the rest), executes tool calls in parallel
(`ToolExec+*`), feeds results back, and writes what mattered to memory. Deeper
tour in [ARCHITECTURE.md](./ARCHITECTURE.md) and [docs/](./docs).

## Security model

This app executes LLM-directed shell commands. Here is exactly what stands between
the model and your machine:

- **Exec approvals** — four levels per binary: Deny (default), Ask, Allowlist, Allow,
  with Strict / Balanced / Permissive presets. Config lives at
  `~/Library/Application Support/GRump/exec-approvals.json`.
- **The Conscience gate** — a deterministic, fail-closed check that runs *before* any
  mutating tool: it refuses destructive shell patterns, pushes to protected branches,
  writes to secret paths, and actions while a sensitive surface (password field,
  payment page) is on screen. Values come from `MIND.md`.
- **The daemon is off by default** — when you enable it, it works one goal at a time
  on an isolated `grump-daemon/*` scratch branch, asks approval for every write, and
  has no code path that pushes.
- **MCP server host refuses `run_command`** — external clients get tools, not your shell.
- **Keys in the Keychain only** — never UserDefaults, never on disk, never proxied.
- **No sandbox, stated plainly** — shell execution, LSP, and file tools require it.
  That trade-off is documented, not hidden. See [SECURITY.md](./SECURITY.md) for the
  threat model and how to report.

## How it compares

| | G-Rump | Claude Code | Aider | OpenHands |
|---|---|---|---|---|
| Runs as | native macOS app | terminal CLI | terminal CLI | web UI + sandbox |
| Written in | Swift | TypeScript | Python | Python |
| License | MIT | proprietary | Apache-2.0 | MIT |
| BYOK multi-provider | 4 providers | Anthropic-centric | yes | yes |
| Cross-session memory built in | yes | project files | no | no |

All four are good tools. G-Rump's bet is that a coding agent should be a first-class
Mac citizen with a memory, not a process in a terminal.

## Roadmap

No dates. In order:

1. **GRumpKit** — extract the harness into a SwiftPM library so you can build your
   own surface on it: provider layer + model catalog first, then tool definitions +
   MCP client, then tool execution behind a context protocol, then the loop itself as
   an `AgentSession` event stream. Today, building on the harness means forking the
   app; this plan is how that stops being true.
2. **Recursive self-learning loops** — post-task reflection that distills lessons
   into persistent, confidence-scored memory; outcome tracking across sessions; and
   agent-proposed skills you approve as diffs. The substrate (memory, skills,
   outcome signals) ships today; the closed loop is in active development.
3. **Deeper Xcode-grade iOS tooling** — build/run toolbar, streaming build console,
   run-to-simulator loop.

## Contributing

PRs welcome — see [CONTRIBUTING.md](./CONTRIBUTING.md) for the build setup (there's
one SwiftData/SPM gotcha worth reading about), the hard rules (no `print()`,
SwiftLint strict), and how to run the suite. Bugs and ideas go to
[issues](https://github.com/Aphrodine-wq/G-Rump/issues); security reports go through
[SECURITY.md](./SECURITY.md).

> G-Rump started as a hackathon build (Global AI Hackathon with Qwen Cloud, Track 1:
> MemoryAgent) and kept the memory obsession. The historical write-ups live in
> [docs/history/](./docs/history).

## License

MIT — see [LICENSE](./LICENSE). Copyright (c) 2025–2026 James Walton.
