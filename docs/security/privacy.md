# Privacy

G-Rump prioritizes user privacy: your API keys stay in the Keychain, there is no
backend, and nothing is sent anywhere except directly to the AI provider you
chose.

## Privacy Dashboard

**Settings → Privacy** shows:
- **Data flow visualization** — Which data goes where (local vs. the selected cloud provider)
- **Apple Silicon status** — Chip, RAM, hardware capabilities
- **Privacy manifest generator** — Generate PrivacyInfo.xcprivacy for your projects

## Data Flow

The app calls providers directly — there is no G-Rump backend in the path.

| Destination | What's Sent | When |
|---|---|---|
| **Local** | Nothing leaves the Mac | File reads, shell, git, and other local tools |
| **Cloud Provider** | Conversation context + tool results | Sent to the active provider (Anthropic, OpenAI, Google, or OpenRouter) |

## Privacy Manifest Generator

`PrivacyManifestGenerator` creates Apple-required PrivacyInfo.xcprivacy files documenting:
- API usage declarations
- Data collection practices
- Tracking domains

Access via **Settings → Privacy → Generate Privacy Manifest**.

## On-Device Processing

Apple frameworks used locally (no data leaves the Mac):
- **Secure Enclave** — Key storage and biometric auth
- **NaturalLanguage** — Text analysis, language detection, and local embeddings for memory recall
- **Vision** — OCR and document scanning
