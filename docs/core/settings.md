# Settings

G-Rump has 20 settings tabs organized into categories.

## Settings Tabs

### General
| Tab | Description |
|---|---|
| **Appearance** | Theme, accent color, density, content size, streaming animation |
| **Notifications** | System notifications, sounds, Focus Filters, menu bar extra |
| **Shortcuts** | Keyboard shortcut reference |
| **Updates** | Sparkle auto-update preferences |
| **About** | Version info, credits, restart onboarding |

### AI & Model
| Tab | Description |
|---|---|
| **Providers** | API keys for Anthropic, OpenAI, Google, OpenRouter (validated on save) |
| **Behavior** | System prompt, temperature, max tokens, agent step limit |
| **Streaming** | Animation style, token buffer size |
| **Advanced** | Context window, retry policy, timeout settings |
| **Presets** | Workflow presets (Refactor, Debug, Read-only, Extended) |

### Workspace
| Tab | Description |
|---|---|
| **Project** | Working directory selection |
| **Skills** | Skill management, ClawHub integration |
| **MCP** | MCP server configuration and credentials |
| **Soul** | SOUL.md personality editor |
| **OpenClaw** | OpenClaw integration settings |
| **Tools** | Tool enable/disable, custom tool definitions |

### Data & Privacy
| Tab | Description |
|---|---|
| **Data** | Export/import conversations and settings |
| **Memory** | Project memory management |
| **Privacy** | Privacy dashboard, privacy manifest |

### Security (macOS only)
| Tab | Description |
|---|---|
| **Security** | Exec approvals, biometric lock, permissions |

## Key Files

- `SettingsView.swift` — Main settings view, tab enum, tab routing
- `Views/Settings/Settings+TabViews.swift` — Individual tab content views
- `PrivacyDashboardView.swift` — Privacy dashboard and manifest generator

## Persistence

All settings use `@AppStorage` (backed by `UserDefaults`) except:
- Exec approvals → JSON file
- Skills → SKILL.md files on disk
- MCP credentials → Keychain
