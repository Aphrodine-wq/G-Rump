# Agent Modes

G-Rump has three agent modes, each tailoring the AI's behavior for a different
workflow. Modes are defined in `Sources/GRump/Models/Agent/AgentMode.swift`.

## Modes

### Plan
Creates a detailed plan before writing any code. The agent thinks through the
work, lays out the steps, and gets alignment before touching the codebase. Best
for complex, multi-file changes where you want to agree on the approach first.

### Build
The "Build" mode (`fullStack` internally). Builds complete features end-to-end
across the full stack — the agent reads, writes, and runs commands to implement
the whole feature, not just a slice. Best for greenfield work and end-to-end
feature delivery.

### Spec
Asks clarifying questions to refine requirements before acting. Rather than
guessing at ambiguous requests, the agent pins down the requirements first. Best
for loosely-specified work where the shape of the task isn't settled yet.

## Mode Selection

Mode is selected via the mode selector row in the chat area (below the input
bar). Each mode has its own accent color — Plan is blue, Build is green, Spec is
teal — and the current mode persists per conversation.

## Workflow Presets

Presets combine a mode with a model, system prompt, and optional tool subset.
Configure in **Settings → Presets**.

Built-in presets:
- **Refactor** — Build mode + focused tool subset
- **Debug** — Plan mode + diagnostic tools
- **Read-only** — Plan mode + read-only tools (no writes)
- **Extended Run** — Build mode + a higher max agent step limit
