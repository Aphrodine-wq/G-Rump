# Changelog

All notable changes to G-Rump are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow
[Semantic Versioning](https://semver.org/).

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
