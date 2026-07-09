# AI Providers

G-Rump is multi-provider. Bring your own key for any of four providers; the app
speaks each provider's wire format directly — there is no backend.

## Supported Providers

| Provider | Type | Models |
|---|---|---|
| **Anthropic** (default) | Cloud | Claude Opus 4.8 (default), Claude Fable 5 (premium, manual select), Claude Sonnet 5, Claude Haiku 4.5 |
| **OpenAI** | Cloud | GPT-5.2, GPT-5.3-Codex |
| **Google** | Cloud | Gemini 3 Pro, Gemini 2.5 Flash |
| **OpenRouter** | Cloud | Routes to Claude Sonnet 5, GPT-5.3-Codex, Gemini 3 Pro, Qwen3 Coder |

The model catalog lives in a single data file, `AIModelCatalog.swift`. The
registry default is **claude-opus-4-8**. Fable 5 is premium and never
auto-selected — you pick it explicitly.

## Configuration

API keys are stored in the **macOS Keychain only**, one account per provider.
`ProviderConfiguration` excludes the key from serialization, so keys never touch
UserDefaults or any config file. Configure in **Settings → Providers**.

### Key validation on save

When you save a key, `AIKeyValidator` runs a cheap authenticated probe
(a `/models` GET; OpenRouter uses `/key`) and reports **verified**, **rejected**,
or **could-not-verify** inline in Settings and onboarding. Keys always save
first — a failed probe warns you, it never blocks the save or removes the key.
Probes send the key in headers only (Google via `x-goog-api-key`), never in a URL.

## Dispatch

`MultiProviderAIService` routes each request to the right transport:

- **Anthropic** and **Google** use their native wire formats with streaming
  tool calls.
- **OpenAI** and **OpenRouter** ride a shared parameterized
  `OpenAICompatibleService` transport.

Anthropic requests pin `anthropic-version: 2023-06-01` and omit temperature
(Claude 4.7+/5 models reject it). All providers normalize stop reasons to the
same `tool_calls` / `stop` signals, so the agent loop drives identically
everywhere.

## Model Router

`ModelRouter` selects a model based on:
- Task complexity (light tasks → a smaller model, heavy tasks → a larger one)
- The active provider (routing picks provider-aware heavy/light chains)
- User preference (per-conversation or global default)

The router never auto-routes to Fable 5.

## Streaming

All providers stream responses token-by-token. Streaming animation styles:
- **Smooth** — Animated token appearance
- **Typewriter** — Character-by-character
- **Instant** — Full blocks appear at once

Configure in **Settings → Streaming**.

## Settings migration

A one-shot migration (flag `ProviderMigration_v1`) runs from
`AIModelRegistry.init` to remap any single-provider-era configuration: provider
and model IDs are updated and stray keys are hoisted into the Keychain. No manual
steps.
