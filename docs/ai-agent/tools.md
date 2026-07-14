# Tools

G-Rump provides 160 tools the AI agent can invoke during conversations.

## Tool Categories

| Category | Examples |
|---|---|
| **File System** | `read_file`, `write_file`, `list_directory`, `find_files`, `grep_search` |
| **Shell** | `system_run` — executes shell commands with exec approval security |
| **Git** | `git_status`, `git_diff`, `git_commit`, `git_log`, `git_branch` |
| **Browser** | `web_search`, `read_url`, `browser_screenshot` |
| **Docker** | `docker_run`, `docker_build`, `docker_compose` |
| **Apple Native** | `spotlight_search`, `keychain_read`, `calendar_events`, `ocr_image`, `xcodebuild` |
| **Cloud Deploy** | `deploy_netlify`, `deploy_vercel`, `deploy_fly` |
| **Notification** | `system_notify` — sends macOS notifications |
| **Screen** | `screen_snapshot`, `window_snapshot`, `camera_snap` |
| **Code Analysis** | `analyze_swift`, `symbol_graph`, `lsp_diagnostics` |

## Execution Flow

```
ChatViewModel receives tool_use block from AI
  → ToolExecutor.execute(tool, parameters)
    → Exec Approval check (for system_run)
    → Tool implementation runs (async)
    → Result returned to AI as tool_result
    → AI continues with next response or tool call
```

## Tool Definitions

Tools are defined in `ToolDefinitions.swift` as an array of `Tool` structs, each with:
- `name` — Tool identifier (e.g., `"read_file"`)
- `description` — What the tool does
- `inputSchema` — JSON Schema for parameters
- `category` — Grouping category

## Exec Approvals (system_run)

Shell execution is gated by `ExecApprovalsStorage`:
- **Config file**: `~/Library/Application Support/GRump/exec-approvals.json`
- **Levels**: Deny (default), Ask, Allowlist, Allow
- **Ask mode**: Dialog lets user choose Run Once, Always Allow, or Deny
- Configure in **Settings → Security**

## Tool Allowlists

Projects can restrict available tools via `.grump/config.json`:
```json
{
  "toolAllowlist": ["read_file", "write_file", "grep_search"]
}
```

## Adding a New Tool

1. Define the tool in `ToolDefinitions.swift`
2. Implement the handler in the appropriate tool executor
3. Add the tool name to any relevant category arrays
4. Document the tool in this file
