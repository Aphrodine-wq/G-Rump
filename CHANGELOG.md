# Changelog

All notable changes to G-Rump are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

The reliability-and-quality release: the agent loop stops trusting "the
model went quiet" as proof of "done", Claude Fable 5 is fully supported,
adaptive thinking raises coding quality on every current Claude model, runs
can go twice as long, and chat responses got a rendering overhaul — faster,
more correct markdown, aligned tables, JSON highlighting, and reopenable
thought processes.

### Added

- **Claude Fable 5 works end-to-end.** Fable signs every reasoning block and
  expects them back: the app now captures native thinking blocks (including
  redacted ones) from the stream and replays them unchanged — first in the
  assistant turn — so tool-use continuations no longer risk rejection. When
  Fable's safety classifiers decline a request (HTTP 200, `refusal` stop
  reason), the chat says so instead of stopping silently.
- **Adaptive thinking on by default.** Anthropic requests on models that
  support it (Opus 4.6+, Sonnet 4.6+, Sonnet 5, Fable 5) now ask for
  `thinking: adaptive` — the recommended mode for coding and agentic work.
  Opus 4.8, the app default, previously ran with thinking off entirely.
- **Mode switches flow mid-conversation.** Changing Plan/Build/Spec with ⇧⇥
  or the status-bar switcher now drops an explicit pivot note into the
  conversation, so the model carries context forward under the new mode
  instead of silently receiving different instructions.
- **Longer autonomous runs.** Max agent steps default doubled to 400 and the
  ceiling raised to 2,000 (Settings → Behavior).
- **Response quality contract.** The default system prompt now spells out
  how answers should read: lead with the outcome, calibrate structure to
  the question, complete sentences over fragment chains, no filler openers,
  `file:line` code references, and honest verified-vs-should-work reporting.
  A new Answering-vs-Acting rule keeps questions from triggering unasked
  edits — problems get diagnosed and a fix proposed, applied only on request.
- **Completion gate.** When a run that changed code (or has open plan steps)
  tries to finish, a fast outside check audits the original request first —
  open plan steps block completion deterministically; otherwise a light-model
  judge reviews changed files, build status, and the final message. Fails
  open, max 2 re-entries, off-switch in Settings → Behavior.
- **Auto-verify after edits.** At the completion point, if the run edited
  code and never proved a green build, the project builds automatically
  (ecosystem auto-detect or `buildCommand` in `.grump/config.json`) and
  failures go back to the agent for fixing — max 3 cycles, then an honest
  give-up note. Tests are strictly opt-in via `testCommand`.
- **`update_plan` tool.** The agent keeps a tracked checklist
  (pending / in_progress / done); the current plan rides along on every
  request and Build mode is instructed to plan first on multi-step tasks.
- **Anthropic prompt caching.** Three ephemeral breakpoints (system, tools,
  advancing message prefix) cut per-step cost and latency on long runs.
  Kill switch: `AnthropicPromptCachingEnabled`.
- **Rolling context compaction.** Long runs summarize their oldest turns
  (light model) instead of hard-dropping them; the original request is
  pinned and always survives truncation.
- **Real eval battery.** `scripts/agent-eval.mjs` runs 8 agentic coding
  tasks against the Anthropic API with the app's actual tool schemas
  (`GRump --dump-tools`), graded deterministically; completion-rate history
  lands in `evals/history.jsonl`.
- **Thought process on past messages.** Reasoning traces captured from
  thinking models were persisted but invisible — completed assistant
  messages now show a collapsed "Thought process" disclosure you can reopen
  any time (redacted blocks stay hidden).
- **Markdown tables, done properly.** Separator alignment (`:---`, `:---:`,
  `---:`) is respected per column, ragged rows normalize to the header's
  column count (short rows pad, overflow folds into the last cell), and data
  rows zebra-stripe for scannability.
- **JSON syntax highlighting.** `json` / `jsonc` / `json5` / `jsonl` /
  `ndjson` blocks highlight literals, strings, and numbers instead of
  rendering flat — the single most common block type in AI output.
- **More inline markdown.** `_italic_` and `__bold__` (word-boundary aware,
  so `snake_case` stays plain) and backslash escapes (`\*` renders a
  literal asterisk).

### Fixed

- **Shell tools were blind to stderr.** `run_command`/`run_build`/friends
  read stderr but never returned it — the agent literally could not see
  compiler errors. stderr is now included and non-zero exits carry a
  deterministic `[exit code: N]` marker.
- **Deep-run stream deaths.** Transient stream errors now retry per turn
  (with backoff) instead of killing any run past step 3.
- **`edit_file` ambiguity.** Multi-location matches now error (with a
  `replace_all` opt-out) instead of silently replacing everything, and a
  whitespace-tolerant fallback handles indentation drift — applied only when
  unambiguous and flagged for re-verification.
- **`.grump/context.md` was ignored** for projects without a
  `config.json`.
- **Truncation could orphan tool results** (API 400s deep into long runs).
- **Streaming could duplicate text fragments.** The incremental markdown
  parser estimated block offsets to skip re-parsing, but the estimates
  undercounted blank lines — mid-stream re-parses could start inside
  already-rendered text and repeat it. Streaming now fully re-parses off
  the main thread (still debounced to ~60fps); correct by construction.
- **Emphasis false positives.** `2 * 3 * 4` no longer italicizes " 3 " —
  emphasis delimiters require non-whitespace flanking.
- **Code blocks clipped at larger content sizes.** Line heights were
  hardcoded for the default text scale; they now scale with the
  content-size preference, keeping the line-number gutter and code aligned.
- **The streaming cursor vanished on long code blocks** once the live view
  truncated to the last 8 lines (it compared against the untruncated list).

### Changed

- **Panel dock is now a single source of truth.** The right-edge sidebar
  renders `PanelTab.dockGroups`, and tests assert every panel appears in
  the dock exactly once — a new panel can no longer be silently unreachable.
- **Chat rendering is dramatically cheaper.** Inline formatting batches
  plain text runs instead of appending one attributed character at a time
  (long paragraphs: thousands of appends → a handful); syntax-highlighted
  code renders one concatenated Text per line instead of one view per token;
  long messages no longer re-split their full content on every hover.

### Removed

- **Dead layout settings.** `panelAlignment`, `quickInputPosition`,
  `secondaryActivityBarVisible`, and `secondarySidebarVisible` persisted to
  UserDefaults but were consumed nowhere; they are gone, along with a
  never-rendered "Quick Input Position" customizer section.
- **The duplicate "Markdown" copy button** on assistant messages — it was
  byte-identical to Copy.
- **The Run button on unlabeled code blocks.** Only explicitly tagged shell
  blocks (`bash`, `zsh`, `sh`, …) offer Run in Terminal; a block with no
  language tag no longer grows a button that silently executes arbitrary
  text.

## [2.1.0] - 2026-07-14

2.1 turns G-Rump from a chat app with tools into a small IDE with an agent in
it: a real build engine with run-to-simulator, a project navigator, an
experimental self-learning loop, and local models via Ollama — no key needed.
Honest note: the newest surfaces (build & run, learning loop) are lightly
battle-tested. They work; they will also surprise you occasionally. The
[roadmap](https://www.g-rump.com/roadmap) tracks what's solid and what's rough.

### Added

- **Build engine + run-to-simulator.** Xcode-style toolbar above the chat:
  ⌘R builds via `xcodebuild` or SPM and, on a simulator destination, continues
  install → launch → live app logs streamed into the new Build console panel
  (Log and Issues tabs, Fix-with-G-Rump, reveal-in-navigator, `xed --line`).
  ⌘⇧. stops. The agent can drive the same loop through `xcrun_simctl` tools.
- **Project navigator.** ⌘0 toggles a left file-tree pane; build issues and
  agent file references reveal straight into it.
- **Self-learning loop (experimental).** Every run's outcome lands in a
  per-project ledger; a reflection pass distills short, confidence-scored
  lessons that ride along on future prompts; strong lesson clusters can become
  skill proposals you approve or reject as diffs in the new Learning panel
  (the 20th dock panel). Off-switch in Settings → Brain. Writes to SOUL.md,
  MIND.md, and skill directories always require approval.
- **Local Ollama provider.** Fifth provider, keyless: models are discovered
  live from `localhost:11434`, tool support is gated per model, and being
  offline is fine. Ollama was cut as dead code in 2.0.0; this is a fresh,
  working implementation. Never auto-routed.
- **Welcome window.** Xcode-style launch window (⇧⌘1): pinned recents, open,
  clone (streaming, cancellable), new project.
- **Developer profile.** Profile → You feeds a capped block (name, role,
  stack, conventions) into the system prompt; Profile → Your Agent embeds the
  SOUL editor.
- **Settings as a real window.** Native `Settings{}` scene on ⌘, — 21 tabs
  regrouped into 7 groups. All legacy entry points still work.
- **Mode-select card.** New conversations open with an inline Plan / Build /
  Spec card gating the first message; ⇧⇥ cycles modes from the input; the
  status bar shows the current mode with a switcher.
- **Onboarding rework.** Six typed steps with real gating; provider step
  validates keys inline (or probes Ollama reachability) and allows an explicit
  "add a key later" deferral. The skills-allowlist overwrite bug is dead.

### Changed

- App icons regenerated on the proper 824pt Apple squircle grid.
- Docs (README, ARCHITECTURE, CLAUDE.md) rewritten against counted reality:
  160 native tools, 67 MCP presets, 20 panels, 73 skills, ~67K LOC, 1,581
  tests.

### Removed

- Empty-state suggestion chips and the mode buttons row (replaced by the
  mode-select card); orphaned ChatAreaView, SpecQuestionsModal,
  RightPanelManager.

## [2.0.0] - 2026-07-09

G-Rump 2.0 is the multi-provider release. The app is no longer tied to a single
AI vendor: bring your own key for Anthropic (default), OpenAI, Google, or
OpenRouter, and G-Rump speaks each provider's native wire format with full
streaming tool calls. The release also lands the cognitive-memory engine, the
brain subsystems, and a large platform cleanup that removes the SaaS
billing layer entirely — G-Rump is now a local-first app with your keys in the
macOS Keychain and no accounts.

### Added

- **Multi-provider AI.** Anthropic (default), OpenAI, Google, and OpenRouter.
  Anthropic and Gemini use native wire formats with streaming tool calls;
  OpenAI and OpenRouter ride a shared parameterized OpenAI-compatible
  transport.
- **2026 model catalog.** Claude Opus 4.8 (default), Claude Fable 5 (premium,
  manual select only), Claude Sonnet 5, Claude Haiku 4.5, GPT-5.2,
  GPT-5.3-Codex, Gemini 3 Pro, Gemini 2.5 Flash, plus OpenRouter routes
  (Claude Sonnet 5, GPT-5.3-Codex, Gemini 3 Pro, Qwen3 Coder).
- **API key validation on save.** Each saved key gets a cheap authenticated
  probe with inline verified / rejected / could-not-verify feedback in both
  Settings and onboarding. Keys always save first; a failed probe warns and
  never blocks.
- **Provider-aware model routing.** Task routing picks sensible heavy/light
  chains within the active provider. Fable 5 is never auto-selected.
- **Automatic settings migration.** One-shot migration of Qwen-era
  configuration: provider and model IDs are remapped and stray keys are
  hoisted into the Keychain. No manual steps.
- **Cognitive memory (Track 1: MemoryAgent).** Cross-session memory with
  relevance x recency x salience ranking, recall within a fixed token budget,
  and deliberate forgetting of stale context.
- **Brain subsystems.** Vault, voice, eyes, mind, and daemon fused into
  the app.
- **Richer chat rendering.** Task lists, inline code pills, images, H4-H6
  headings, improved streaming code blocks, expandable tool timeline with
  line counts and copy buttons, per-message word count, and copy-as-markdown.
- **Keyboard shortcuts, conversation search, collapsible messages, and diff
  copy.**
- **Expanded syntax highlighting.** SQL, YAML, HTML, CSS, and Dockerfile,
  plus decorator support.
- **Code signing and notarization pipeline.** `make sign` / `make package` /
  `make notarize` for signed, notarized distribution builds.
- **Evaluation harness.** `scripts/judge-verify.mjs` (chat, multi-turn tool
  calling, embeddings) and `scripts/agent-eval.mjs` (4-task agent battery on a
  real tool loop).
- **CI hardening.** SwiftLint strict configuration; green pipeline across
  tests, lint, backend tests, and release build. Suite currently at 1,449
  tests.

### Changed

- Default model is **Claude Opus 4.8** (was Qwen Coder Plus).
- **API keys live exclusively in the macOS Keychain**, one account per
  provider. Keys are never written to UserDefaults or any config file.
- Agent modes consolidated from seven to three: **Plan, Build, Spec**.
- The Node.js backend is now an **optional** stateless proxy; the app calls
  providers directly by default.
- Anthropic requests pin `anthropic-version: 2023-06-01` and omit temperature
  (Claude 4.7+/5 models reject it).
- Themes renamed to neutral names: Snow, Linen, Graphite, Amethyst, Ink.
- Relicensed under **MIT**.

### Fixed

- **Anthropic tool arguments now stream.** `input_json_delta` chunks were
  dropped, so every Anthropic tool call arrived with empty arguments.
- **Anthropic multi-turn tool loops no longer 400.** System prompts ride the
  top-level `system` field, assistant turns emit `tool_use` blocks, and
  max-tokens is set per request.
- **Gemini tool loops work past turn one.** Tool results are now sent as
  `functionResponse` parts.
- **Stop-reason normalization.** All providers normalize to the same
  `tool_calls` / `stop` signals so the agent loop drives identically
  everywhere.
- **Settings key foot-gun removed.** The Account tab's "OpenRouter API key"
  field silently wrote to whichever provider was active; per-provider keys
  live in the Providers tab.
- Headless test crash and all pre-existing test failures; the suite runs
  green.
- 48 deployment gaps closed across security, legal, features, backend, and
  accessibility ahead of distribution.

### Removed

- Billing / platform SaaS layer. JWT auth replaced by an optional
  `APP_API_KEY` gate on the proxy.
- OpenClaw chat-routing subsystem.
- GRumpServer SaaS target.
- Ollama, on-device CoreML, and model-mode dead code.
- "Local Only Mode" privacy toggle and "Fully Local" badge (they gated
  nothing).
- Legacy `AIModel` enum; the typed model catalog is the single source of
  truth.

### Security

- Shell-injection vectors eliminated — subprocess calls use `Process()`
  argument arrays instead of interpolated shell strings.
- MCP hardening: path-traversal protection and authentication on
  `tools/list`.
- `ProviderConfiguration` excludes the API key from serialization, so keys
  cannot leak into UserDefaults backups.
- Key-validation probes send keys in headers only (Google via
  `x-goog-api-key`), never in URLs where they could reach logs.

## [1.0.0] - 2026-02-24

Initial release: a native macOS/iOS autonomous AI coding agent — chat with
streaming responses, 100+ local tools (file, shell, git, Docker, browser,
Apple-native), MCP client and server, skills and SOUL.md personality systems,
approval-gated autonomous daemon, and dual-mode persistence (SwiftData/JSON).

[2.0.0]: https://github.com/Aphrodine-wq/G-Rump/compare/v1.0.0...9659590
[1.0.0]: https://github.com/Aphrodine-wq/G-Rump/releases/tag/v1.0.0
