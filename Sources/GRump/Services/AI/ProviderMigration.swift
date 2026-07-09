import Foundation

// MARK: - Provider Migration (Qwen era → multi-provider)
//
// One-shot startup migration for state persisted by the Qwen-only build.
// Invoked from AIModelRegistry.init so it is guaranteed to run before any
// subsystem reads provider or model defaults. Idempotent via the
// `ProviderMigration_v1` flag.
//
// IMPORTANT: this must never touch AIModelRegistry.shared — it runs inside
// the registry's own init and re-entrant access would deadlock the lazy
// static. Everything here is pure UserDefaults + Keychain.

enum ProviderMigration {

    static let flagKey = "ProviderMigration_v1"

    static func runIfNeeded(
        defaults: UserDefaults = .standard,
        keychainSet: (String, String) -> Void = { KeychainStorage.set(account: $0, value: $1) }
    ) {
        guard !defaults.bool(forKey: flagKey) else { return }

        // 1. Hoist stray plaintext API keys out of the old UserDefaults registry
        //    JSON into the Keychain. Lenient JSONSerialization decode — the typed
        //    decoder throws on "qwen" provider entries. The Qwen key lands under
        //    the legacy QwenAPIKey account, left in place unused.
        if let data = defaults.data(forKey: "AIProviderConfigurations"),
           let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            for entry in raw {
                guard let key = entry["apiKey"] as? String, !key.isEmpty,
                      let providerRaw = entry["provider"] as? String else { continue }
                let account: String
                switch providerRaw {
                case "qwen": account = "QwenAPIKey"
                case "anthropic": account = "AnthropicAPIKey"
                case "openai": account = "OpenAIAPIKey"
                case "google": account = "GoogleAPIKey"
                case "openrouter": account = "OpenRouterAPIKey"
                default: continue
                }
                keychainSet(account, key)
            }
        }

        // 2. Drop the old registry blob — it may contain "qwen" entries the new
        //    typed decoder rejects. The registry reseeds provider defaults.
        defaults.removeObject(forKey: "AIProviderConfigurations")

        // 3. Provider selection: anything that isn't a live provider becomes
        //    Anthropic (the new default).
        let savedProvider = defaults.string(forKey: "CurrentAIProvider") ?? ""
        if AIProvider(rawValue: savedProvider) == nil {
            defaults.set(AIProvider.anthropic.rawValue, forKey: "CurrentAIProvider")
        }

        // 4. Model selection: map stale ids to the closest current tier.
        if let modelID = defaults.string(forKey: "CurrentAIModel") {
            defaults.set(ModelIDMigration.map(modelID), forKey: "CurrentAIModel")
        }

        // 5. Dead keys from the Qwen build.
        defaults.removeObject(forKey: "QwenBaseURL")
        defaults.removeObject(forKey: "SelectedModel")

        defaults.set(true, forKey: flagKey)
    }
}

// MARK: - Model ID Migration

enum ModelIDMigration {

    /// Maps a persisted model id from any prior build to a current catalog id.
    /// Pure string rules — no registry access (see deadlock note above).
    /// Current-generation ids pass through untouched; stale ids map by tier:
    /// light tiers → Haiku, mid tiers → Sonnet, everything else → Opus.
    static func map(_ id: String) -> String {
        let lower = id.lowercased()

        // Already a current id (Claude / GPT / Gemini / OpenRouter route).
        if lower.hasPrefix("claude-") || lower.hasPrefix("gpt-")
            || lower.hasPrefix("gemini-") || lower.contains("/") {
            return id
        }

        if ["turbo", "flash", "mini", "haiku"].contains(where: lower.contains) {
            return "claude-haiku-4-5"
        }
        if ["sonnet", "plus"].contains(where: lower.contains) {
            return "claude-sonnet-5"
        }
        return "claude-opus-4-8"
    }
}
