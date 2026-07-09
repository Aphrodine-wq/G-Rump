# Security Policy

G-Rump runs LLM-directed shell commands, file writes, and git operations on your
machine. That makes the boundaries between "the model asked for it," "you
approved it," and "it ran" the most security-sensitive part of the whole app.
This policy is about those boundaries.

## Supported versions

This is a solo-maintained project. **Only the latest release** receives security
fixes. If you're on an older build, upgrade before reporting.

## Reporting a vulnerability

Use **GitHub's private vulnerability reporting** on the repository:

1. Go to the [Security tab](https://github.com/Aphrodine-wq/G-Rump/security).
2. Click **Report a vulnerability**.
3. Include repro steps, the provider/model and agent mode in use, and — where it
   applies — which approval or gate you expected to stop the behavior.

Please don't open a public issue for anything exploitable. You'll get an
acknowledgement within **one week**. Since one person maintains this, fix
timelines depend on severity and complexity — critical remote-exec-class issues
jump the queue.

## What counts as a vulnerability here

G-Rump's threat model assumes the model output is **untrusted**. A malicious repo,
a prompt-injection payload in a file the agent reads, or a hostile MCP tool
result should never be able to reach a destructive action without passing the
gates below. Anything that breaks one of these is in scope:

- **ExecApprovals bypass.** `system_run` is gated by an approval workflow (Deny /
  Ask / Allowlist / Allow, configured at
  `~/Library/Application Support/GRump/exec-approvals.json`). Any path that runs a
  shell command the user did not approve — or that escalates past the configured
  level — is a vulnerability.
- **ConscienceGate bypass.** The Conscience gate is **fail-closed** and sits ahead
  of mutating tools. Any way to reach a mutating tool (file write, delete, git
  mutation) when the gate should have blocked or should have prompted — including
  making it fail *open* — is in scope.
- **Prompt-injection reaching a sink.** A crafted file, tool result, web page, or
  MCP response that causes `system_run` execution or a file write **without the
  expected approval** is a vulnerability, not "the model being dumb." The gates
  are supposed to catch this regardless of what the model was talked into.
- **Keychain / credential handling flaws.** API keys live in the Keychain only and
  are deliberately excluded from the `Codable` config so they never reach
  UserDefaults. Anything that leaks a key to disk, logs, UserDefaults, a network
  request to the wrong host, or another process is in scope. MCP secrets injected
  as env vars for stdio servers count too.
- **MCP server host escapes.** G-Rump exposes its own tools as an MCP server on
  **TCP port 18790**, and that host **refuses `run_command`** by design. Anything
  that resurrects remote command execution through the host — directly, via a
  smuggled tool name, or by tricking a proxied tool into shelling out — is
  **critical**. The same goes for the host binding wider than intended or
  accepting unauthenticated mutating calls.
- **Autonomous daemon containment breaks.** The autonomous daemon is supposed to
  work goals on an isolated scratch branch behind per-write approval. Anything
  that lets it commit to the user's working branch, push to a remote, or act
  outside its scratch branch without approval is in scope.

## What is *not* a vulnerability

These are deliberate design decisions. Reports asking us to "fix" them will be
closed as intended behavior.

- **The app is not sandboxed.** G-Rump's entitlements disable the App Sandbox on
  purpose. Shell execution, SourceKit-LSP, and the file tooling that make it a
  coding agent are fundamentally incompatible with the sandbox — you cannot run
  arbitrary developer tools from inside it. G-Rump is distributed outside the Mac
  App Store for exactly this reason. The security model is *approval gates around
  powerful tools*, not *a sandbox around the process*. "The app can run shell
  commands" is the product, not a bug — the vulnerability would be running them
  **without approval**.
- **Local MCP servers run with your privileges.** MCP stdio servers you configure
  launch as local child processes with your user's permissions, by design. Vet
  the servers you add — a hostile third-party MCP server you installed yourself is
  outside the threat model, the same way a hostile Homebrew formula would be.
