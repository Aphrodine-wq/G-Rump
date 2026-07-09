*Historical document — describes the original Qwen Cloud Hackathon build (mid-2026). Kept for provenance; the current architecture is multi-provider with no backend. See [../../ARCHITECTURE.md](../../ARCHITECTURE.md).*

# G-Rump — Global AI Hackathon with Qwen Cloud

**Track: 1 — MemoryAgent** (demonstrated through Track 4 autonomous-agent capabilities)

---

## Inspiration

Every coding agent starts each session blind — you re-explain the repo, the bug,
what you tried yesterday. We wanted an agent with a real memory: one that
accumulates experience across sessions, recalls only what matters within a tight
context window, and *forgets* what's gone stale — and that does real work
autonomously, not just chat. So we took G-Rump, a mature 54K-LOC macOS coding
agent, and rebuilt it entirely on Qwen, with a persistent cognitive memory as the
centerpiece.

## What it does

G-Rump is a native macOS autonomous coding agent powered end-to-end by **Qwen on
Alibaba Cloud (Qwen Cloud / DashScope)**:

- **Persistent cognitive memory (the headline).** Memory is ranked by
  **relevance × recency × salience**, recalled within a **fixed token budget**
  (the "limited context window" requirement), and **consolidated/forgotten** by a
  periodic "sleep" pass that decays, merges near-duplicates, and prunes stale
  memories. It behaves like a brain, not an append-only vector log.
- **Autonomous coding daemon.** Picks a pending goal, works it on a scratch git
  branch, and requires explicit approval for every mutating action (the
  Conscience safety gate) — end-to-end automation with human-in-the-loop.
- **100+ local tools + MCP.** File, shell, git, Docker, Apple-native, plus MCP
  client/server — all driven by Qwen's tool calling.

## How we built it with Qwen

- **Single provider, by design.** We stripped every other model integration
  (Anthropic, OpenAI, Google, Ollama, on-device) and rebuilt around Qwen's
  OpenAI-compatible DashScope endpoint. Models: Qwen Coder Plus (agentic coding),
  Qwen Max (reasoning/planning), Qwen Plus, Qwen Turbo — with task-aware routing.
- **Tool calling.** The agent loop streams Qwen `tool_calls`, executes locally,
  and returns results with `tool_call_id` for multi-turn tool use.
- **Memory embeddings.** Memories are embedded with Qwen `text-embedding-v4`
  (with a local fallback for offline use).
- **Backend on Alibaba Cloud.** A minimal stateless Node/Express proxy forwards
  chat + embeddings to Qwen; all Alibaba Cloud calls are centralized in
  `backend/alibaba.js`. Deployable on Alibaba ECS or Function Compute.

## Challenges

- Qwen's multi-turn tool-calling had to be exactly right or the autonomous loop
  stalls — we route through the one request builder that preserves
  `tool_call_id` and `tool_choice:auto`, and gate the build on a live tool-call
  round-trip test.
- Turning "context injection" into a real MemoryAgent: budget-aware recall and a
  principled forgetting/consolidation algorithm, fully unit-tested.

## What's next

- Move all memory embeddings fully onto Qwen Cloud and surface the consolidation
  log live in the UI ("watch it forget").
- Multi-agent (Track 3) collaboration across Qwen tiers.

## Built with

Swift, SwiftUI, Node.js, Express, **Qwen (Qwen Cloud / Alibaba DashScope)**,
Model Context Protocol, Alibaba Cloud (ECS / Function Compute).

---

## 3-minute demo script

> Goal: show (1) it runs entirely on Qwen, (2) the autonomous coding loop, and
> (3) the persistent memory recalling across sessions and forgetting stale info.

**0:00–0:25 — Hook + setup.** "This is G-Rump, an autonomous macOS coding agent
running entirely on Qwen." Open Settings → show the single **Qwen** provider and
the model list (Coder Plus / Max / Plus / Turbo). Note the key field is a Qwen /
DashScope key.

**0:25–1:15 — Autonomous coding on Qwen.** Open a small repo. Give the daemon a
goal ("add input validation to the signup form and a test"). Show it: pick the
goal → plan → call tools (read_file, edit_file, run tests) → **approval prompt**
for the write (Conscience gate) → tests pass on a scratch branch. Call out that
every token is Qwen via the Alibaba backend.

**1:15–2:10 — The memory (the headline).** Start a **new session** (or new
conversation). Ask something that depends on the prior session ("what did we
change in the signup flow?"). Show G-Rump recalling it — point at the injected
**"Relevant Memory (recalled within budget)"** block: ranked by relevance and
recency, packed into a token budget. Then trigger the consolidation pass and show
the log: duplicates merged, a stale memory forgotten.

**2:10–2:45 — Architecture + proof.** Show the diagram
(`docs/ARCHITECTURE-QWEN.md`): G-Rump.app → Alibaba backend → Qwen Cloud. `curl`
the deployed `/api/health` showing the `*.aliyuncs.com` host, then a real chat
response — proof the backend runs on Alibaba Cloud calling Qwen.

**2:45–3:00 — Close.** "Open source, MIT, built entirely on Qwen — a coding agent
with a brain." Repo + Track 1.

### Separate deployment-proof recording (required, not part of the demo)

Screen-record: the backend running on an Alibaba Cloud ECS instance (or Function
Compute console), then `curl https://<host>/api/v1/chat/completions` returning a
real Qwen response. Link `backend/alibaba.js` as the code file proving Alibaba
Cloud service usage.
