# Security

G-Rump provides multiple security layers for safe AI agent execution.

## Exec Approvals

Controls which shell commands `system_run` can execute.

### Security Levels
| Level | Behavior |
|---|---|
| **Deny** | Block all shell commands (default) |
| **Ask** | Show approval dialog for each command |
| **Allowlist** | Auto-approve commands matching glob patterns |
| **Allow** | Auto-approve all commands (not recommended) |

### Ask Mode Dialog
When a command is attempted:
- **Run Once** — Execute this time only
- **Always Allow** — Add to allowlist
- **Deny** — Block this command

### Config File
`~/Library/Application Support/GRump/exec-approvals.json`

### Allowlist Patterns
Glob patterns for resolved binary paths:
```json
{
  "security": "ask",
  "askOnMiss": true,
  "allowlist": [
    {"pattern": "/usr/bin/git", "source": "user"},
    {"pattern": "/usr/bin/swift*", "source": "user"}
  ]
}
```

Configure in **Settings → Security → Exec Approvals**.

## Keychain Integration

API keys and credentials are stored in macOS Keychain via `KeychainService`:
- AI provider API keys (one account per provider)
- MCP server credentials

## Secure Enclave

`SecureEnclaveService` provides:
- **Biometric authentication** — Touch ID / Apple Watch unlock
- **Hardware key storage** — Encryption keys stored in Secure Enclave
- **Availability detection** — Checks for Secure Enclave and biometric hardware

Status visible in **Settings → Security → Biometric Lock**.

## Session Audit

**Settings → Security → Commands This Session** shows all `system_run` attempts with:
- Resolved binary path
- Full command string
- Allowed/Denied status
