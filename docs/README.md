# G-Rump Documentation

Comprehensive documentation for the G-Rump AI coding agent.

## Table of Contents

### Core
- [Architecture](core/architecture.md) — App structure, data flow, entry points
- [Themes](core/themes.md) — Theme system, palettes, creating custom themes
- [Design Tokens](core/design-tokens.md) — Typography, spacing, radii, borders, animations
- [Settings](core/settings.md) — All settings tabs and what they control

### AI & Agent
- [AI Providers](ai-agent/ai-providers.md) — Anthropic, OpenAI, Google, OpenRouter
- [Agent Modes](ai-agent/agent-modes.md) — Plan, Build, Spec
- [Tools](ai-agent/tools.md) — All 153 tools, categories, execution flow
- [Skills](ai-agent/skills.md) — Skills system, bundled skills, custom project skills
- [Soul](ai-agent/soul.md) — SOUL.md personality system, templates

### IDE Features
- [Panels](ide/panels.md) — All 18 IDE panels
- [Layout](ide/layout.md) — Layout customization, Zen Mode, Activity Bar
- [Keyboard Shortcuts](ide/keyboard-shortcuts.md) — Complete shortcut reference
- [LSP](ide/lsp.md) — SourceKit-LSP integration, diagnostics, symbol graph

### Integration
- [MCP](integration/mcp.md) — MCP server integration, credential vault
- [Notifications](integration/notifications.md) — Notifications, Focus Filters, App Intents

### Security & Privacy
- [Security](security/security.md) — Exec approvals, Keychain, Secure Enclave
- [Privacy](security/privacy.md) — Privacy manifest, on-device processing

### Data & Config
- [Project Config](data-config/project-config.md) — .grump/config.json, context files, presets
- [Data Persistence](data-config/data-persistence.md) — SwiftData models, JSON fallback, export/import

### Release
- [Distribution](release/distribution.md) — Building, signing, notarization, DMG, Sparkle
- [Release Notes](release/release-notes.md) — Version history and changelog
- [Testing](release/testing.md) — Test suite, CI pipeline
- [Onboarding](release/onboarding.md) — Onboarding flow, first-run experience
- [Accessibility](release/accessibility.md) — A11y audit panel, VoiceOver, Dynamic Type

### History
Provenance from the original Qwen Cloud Hackathon build. These describe dead systems and are kept only for reference — the current app is multi-provider with no backend.
- [Qwen Architecture](history/ARCHITECTURE-QWEN.md) — the original single-provider, backend-proxied design
- [Hackathon](history/HACKATHON.md) — the Qwen Cloud Hackathon submission and demo script
