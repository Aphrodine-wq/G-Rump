# Testing & Evaluating G-Rump

G-Rump's UI is a native macOS app, but **you do not need a Mac to verify that it
works on Qwen.** Its intelligence (model calls, tool calling, embeddings) runs
through a cross-platform backend, and the agent's core logic is covered by an
automated test suite. This doc explains exactly how to test it, at three levels.

| Level | Needs | Verifies |
|---|---|---|
| 1. Qwen integration | Any OS + Node 18 + a Qwen key | The agentic loop on Qwen: chat, multi-turn tool calling, embeddings |
| 2. Automated suites | macOS (or CI) | Agent logic, cognitive memory, request shaping — 1,447 checks |
| 3. Full app | macOS | The end-to-end product (daemon, approval gates, memory in the UI) |

---

## Level 1 — Verify the Qwen integration (any OS, ~30s)

The single most important claim — *that the agentic tool-call loop actually runs
on Qwen* — is verifiable by anyone with a Qwen key, no Mac required:

```bash
QWEN_API_KEY=sk-...  node scripts/judge-verify.mjs
```

It runs three live checks and prints PASS/FAIL (exit 0 = all pass):

1. **Chat connectivity** — a basic Qwen completion.
2. **Multi-turn tool calling** — the agent's lifeblood: Qwen emits a
   `read_file` `tool_call`, we reconstruct its JSON arguments, return a `tool`
   result with the matching `tool_call_id`, and Qwen continues correctly. This
   is the exact loop that powers autonomous coding.
3. **Embeddings** — `text-embedding-v4`, which backs the cognitive memory.

To verify the **Alibaba-hosted backend** specifically (proof it runs on Alibaba
Cloud and calls Qwen), point the script at it:

```bash
BACKEND_URL=https://<your-alibaba-host>  APP_API_KEY=...  node scripts/judge-verify.mjs
```

The backend itself is one Docker command (`backend/README-DEPLOY.md`); all of its
Alibaba Cloud calls are centralized in `backend/alibaba.js`.

---

## Level 2 — Automated test suites (macOS / CI)

```bash
swift test -j 12          # 1,437 app tests (agent logic, modes, memory, request shaping)
cd backend && npm test    # 4 backend tests (health, validation, proxy surface)
```

Tests that directly evidence the hackathon claims:

- **`CognitiveMemoryTests`** (6) — the Track 1 differentiator, proven deterministically:
  - budget-aware recall packs the highest-scoring memories into a fixed token
    window; ranking is relevance × recency × salience;
  - the consolidation pass decays, merges near-duplicates, and forgets stale
    memories (the "timely forgetting" requirement).
- **`QwenServiceTests`** — the request sent to Qwen is OpenAI-compatible: Bearer
  auth, `tool_choice: auto` + `tools`, and **no** foreign fields
  (`provider`, `HTTP-Referer`, `anthropic-version`).
- **`AIProvidersTests` / `ModelsTests`** — the app is single-provider Qwen only.

CI (`.github/workflows/ci.yml`) runs the Swift suite, SwiftLint (strict), and the
backend tests on every push.

---

## Level 3 — The full app (macOS)

```bash
make run     # build debug + launch
```

Onboard with a Qwen (DashScope) key, then exercise the agent:

- **Autonomous coding** — give the daemon a goal; watch it plan, call tools, and
  hit an **approval gate** before any write, working on a scratch branch.
- **Memory across sessions** — in a new session, ask about prior work; the system
  prompt shows a **"Relevant Memory (recalled within budget)"** block.

See `docs/HACKATHON.md` for the 3-minute demo script.

---

## Agent evaluation methodology

Beyond unit tests, the agent is evaluated on **task batteries** — concrete
coding tasks with objective success criteria — and a **memory eval**.

A **runnable, cross-platform agent eval** ships in the repo — it drives Qwen
through the real tool-call loop over a mock repo and scores task completion:

```bash
QWEN_API_KEY=sk-...  node scripts/agent-eval.mjs
```

It runs four scenarios (single read, discover-then-read, find-the-bug,
grep-locate), executes the mock tools, and passes only if the model *used the
tools* and reached the correct answer. Exits 0 if the pass rate ≥ 75%.

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

### Tool-calling reliability (covered by `judge-verify.mjs` + `QwenServiceTests`)

- Qwen emits well-formed `tool_calls`, arguments reconstruct to valid JSON, and
  the `tool_call_id` round-trip continues the conversation — the property the
  autonomous loop depends on.

---

## If you only do one thing

Run `node scripts/judge-verify.mjs` with a Qwen key. If it prints **VERIFIED**,
G-Rump's agentic loop works on Qwen — chat, tool calling, and embeddings — which
is the foundation everything else is built on.
