# G-Rump — Release Notes

Full, structured release history lives in [CHANGELOG.md](../../CHANGELOG.md).
This page summarizes each release.

## v2.0.0 — Multi-provider (2026-07-09)

G-Rump 2.0 is the multi-provider release. The app is no longer tied to a single
AI vendor and no longer runs through a hosted backend — bring your own key and
G-Rump calls the provider directly.

| Area | Highlights |
|---|---|
| **Multi-provider AI** | Anthropic (default), OpenAI, Google, OpenRouter. Anthropic and Gemini use native wire formats with streaming tool calls; OpenAI and OpenRouter ride a shared OpenAI-compatible transport. |
| **2026 model catalog** | Claude Opus 4.8 (default), Claude Fable 5 (premium, manual select), Claude Sonnet 5, Claude Haiku 4.5, GPT-5.2, GPT-5.3-Codex, Gemini 3 Pro, Gemini 2.5 Flash, plus OpenRouter routes. |
| **Keys in the Keychain** | API keys live exclusively in the macOS Keychain, one account per provider, validated on save by `AIKeyValidator`. No accounts. |
| **Cognitive memory** | Cross-session memory ranked by relevance × recency × salience, recalled within a fixed token budget, with deliberate forgetting of stale context. |
| **Agent modes** | Consolidated to three: Plan, Build, Spec. |
| **Distribution** | Code-signing and notarization pipeline (`make sign` / `make package` / `make notarize`). |
| **License** | Relicensed under MIT. |

Removed in 2.0: the paid SaaS platform layer (accounts and payments), the hosted
backend proxy, the on-device and local-model code paths, and the "Local Only
Mode" toggle. See the [changelog](../../CHANGELOG.md#200---2026-07-09) for the
complete list, including fixes and security hardening.

---

## v1.0.0 — Initial Release (2026-02-24)

The inaugural public release of G-Rump, a native macOS AI coding agent built with
Swift and SwiftUI: chat with streaming responses, a large set of local tools
(file, shell, git, Docker, browser, Apple-native), MCP client and server, the
skills and SOUL.md personality systems, an approval-gated autonomous daemon, and
dual-mode persistence (SwiftData / JSON). See the
[changelog](../../CHANGELOG.md#100---2026-02-24) for details.

The current tool count (153), panel count (18), skill set (~80 plus 21 packs),
MCP presets (~60), theme names, and provider lineup all reflect the 2.0 release
above, not this initial one.

---

## System Requirements

- **macOS 14+ (Sonoma)**
- **Swift 5.9+**
- Xcode 15+ (for building from source)
