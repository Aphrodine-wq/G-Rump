# Testing & Evaluating G-Rump

G-Rump is a native macOS app that calls AI providers directly. Its agent logic —
the tool-call loop, request shaping, cognitive memory, and mode behavior — is
covered by an automated Swift test suite, and the full product is verifiable by
running the app. This doc explains how to test it at three levels.

| Level | Needs | Verifies |
|---|---|---|
| 1. Automated suites | macOS (or CI) | Agent logic, cognitive memory, request shaping — ~1,581 checks |
| 2. Full app | macOS | The end-to-end product (daemon, approval gates, memory in the UI) |
| 3. Legacy smoke tests | Any OS + Node 18 + an OpenAI-compatible key | A chat / tool-call / embeddings round-trip (historical tooling) |

---

## Level 1 — Automated test suites (macOS / CI)

```bash
swift test -j 12          # ~1,581 app tests (agent logic, modes, memory, request shaping)
```

Tests that directly evidence the core claims:

- **`CognitiveMemoryTests`** — the memory engine, proven deterministically:
  - budget-aware recall packs the highest-scoring memories into a fixed token
    window; ranking is relevance × recency × salience;
  - the consolidation pass decays, merges near-duplicates, and forgets stale
    memories (the "timely forgetting" requirement).
- **Provider request-shaping tests** — each provider's request is well-formed:
  Anthropic pins `anthropic-version: 2023-06-01` and omits temperature, Google
  uses native `functionResponse` parts, and OpenAI/OpenRouter ride the shared
  OpenAI-compatible transport.
- **`AIProvidersTests` / `ModelsTests`** — the multi-provider catalog and routing
  behave as specified (default `claude-opus-4-8`; Fable 5 never auto-routed).

CI (`.github/workflows/ci.yml`) runs the Swift suite and SwiftLint (strict) on
every push.

---

## Level 2 — The full app (macOS)

```bash
make run     # build debug + launch
```

Onboard with a provider key (Anthropic by default), then exercise the agent:

- **Autonomous coding** — give the daemon a goal; watch it plan, call tools, and
  hit an **approval gate** before any write, working on a scratch branch.
- **Memory across sessions** — in a new session, ask about prior work; the system
  prompt shows a **"Relevant Memory (recalled within budget)"** block.

---

## Level 3 — Legacy smoke tests (any OS)

Two Node scripts remain in `scripts/` from the original single-provider build:

```bash
node scripts/judge-verify.mjs      # chat, multi-turn tool calling, embeddings
node scripts/agent-eval.mjs        # 4-task agent battery on a real tool loop
```

They exercise an OpenAI-compatible chat / tool-call / embeddings loop and can be
pointed at any OpenAI-compatible endpoint (for example, an OpenRouter base URL)
through their `*_BASE_URL` / `*_MODEL` environment overrides. Their built-in
defaults, and the optional proxy path they support, target infrastructure that no
longer ships — **treat these scripts as historical**. The supported verification
is the Swift suite in Level 1.

---

## Agent evaluation methodology

Beyond unit tests, the agent is evaluated on **task batteries** — concrete
coding tasks with objective success criteria — and a **memory eval**.

### Coding task battery (full app/daemon on macOS; scored 0–1)

| # | Task | Success criteria |
|---|---|---|
| 1 | "Add input validation to function X and a test" | Edits the right file; test added; `swift test`/`pytest` passes |
| 2 | "Find where Y is configured and change it to Z" | Locates via grep/read; minimal correct diff |
| 3 | "Fix the failing test in module M" | Reproduces, fixes root cause, suite goes green |
| 4 | "Refactor duplicated logic in file F" | Behavior preserved (tests pass); duplication reduced |

Scored on: task completion, tool-call correctness (no malformed calls / loops),
and minimality of the diff. The approval gate keeps a human in the loop, so
"unsafe action attempted" is also tracked.

### Memory recall/forgetting eval (covered by `CognitiveMemoryTests`)

- **Recall** — a fact stored in session 1 is recalled in session 2 *within the
  token budget*, ranked above noise by relevance × recency × salience.
- **Forgetting** — a stale, low-salience memory is demoted/pruned by the
  consolidation pass; near-duplicates merge into one reinforced memory.

### Tool-calling reliability

- The agent loop drives every provider identically: models emit well-formed
  `tool_calls`, arguments reconstruct to valid JSON, and the tool-result
  round-trip continues the conversation — the property the autonomous loop
  depends on.

---

## If you only do one thing

Run `swift test`. A green suite means G-Rump's agent logic — the tool-call loop,
provider request shaping, and the cognitive memory — works, which is the
foundation everything else is built on.
