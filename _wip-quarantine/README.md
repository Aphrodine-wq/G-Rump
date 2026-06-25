# Quarantined WIP (do not build)

These subsystems were added in commit `2f6a706` ("feat: add CodeDNA, workflows,
build pipeline, swarm services, and architecture views") but **never compiled** —
they introduced duplicate top-level types (`StreamEvent`, `ToolCallDelta`,
`BuildError`) that collide with the originals in `OpenRouterService.swift` and
`BuildErrorParser.swift`, producing ~1,800 cascading errors.

They were moved out of `Sources/GRump/` (so SPM ignores them) to restore a green
build for the WALT-brain product work. The core chat app does **not** reference
any of them, so nothing was lost.

Recover anytime via git history, or move a directory back under `Sources/GRump/`
after disambiguating its duplicate types.

| Dir | Original location |
|-----|-------------------|
| `CodeDNA/` | `Sources/GRump/Intelligence/CodeDNA/` |
| `Workflows/` | `Sources/GRump/Intelligence/Workflows/` (note: `WorkflowScheduler` is wanted later for the autonomous daemon, Phase 5) |
| `BuildPipeline/` | `Sources/GRump/Services/BuildPipeline/` |
| `Swarm/` | `Sources/GRump/Services/Swarm/` |
| `Architecture/` | `Sources/GRump/Views/Architecture/` |
