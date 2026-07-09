import Foundation

// MARK: - Default Model Catalog
//
// Current-generation models for the four first-class providers. Anthropic is
// the flagship provider (Claude Opus 4.8 is the app default); OpenRouter
// carries passthrough routes, including the legacy Qwen lane. `id` ==
// `modelID` == the exact wire id. This file is deliberately a single data
// table — when a vendor ships new models, edit here only.
//
// Pricing is USD per 1K tokens (Anthropic verified 2026-07; others render "—"
// until verified). gpt-5.3-codex serves both chat-completions and Responses
// per OpenAI's model page — live round-trip pending a key (Session A P5).

extension AIModelRegistry {

    // MARK: - Shared Capabilities

    static let fullCaps = ModelCapabilities(
        supportsTools: true, supportsVision: true, supportsStreaming: true,
        supportsFunctionCalling: true, supportsJSONMode: true, maxTokens: nil,
        supportsSystemMessages: true, supportsParallelToolUse: true
    )

    static let textCaps = ModelCapabilities(
        supportsTools: true, supportsVision: false, supportsStreaming: true,
        supportsFunctionCalling: true, supportsJSONMode: true, maxTokens: nil,
        supportsSystemMessages: true, supportsParallelToolUse: true
    )

    // MARK: - Catalog

    func defaultModelCatalog() -> [EnhancedAIModel] {
        let full = Self.fullCaps
        let text = Self.textCaps

        return [
            // MARK: Anthropic
            EnhancedAIModel(
                id: "claude-opus-4-8",
                provider: .anthropic,
                modelID: "claude-opus-4-8",
                displayName: "Claude Opus 4.8",
                description: "Default — long-horizon agentic coding and the strongest all-rounder",
                contextWindow: 1_000_000,
                maxOutput: 128_000,
                requiresPaidTier: false,
                capabilities: full,
                pricing: ModelPricing(inputPricePer1K: 0.005, outputPricePer1K: 0.025, currency: "USD")
            ),
            EnhancedAIModel(
                id: "claude-fable-5",
                provider: .anthropic,
                modelID: "claude-fable-5",
                displayName: "Claude Fable 5",
                description: "Anthropic's most capable model — premium, pick it deliberately",
                contextWindow: 1_000_000,
                maxOutput: 128_000,
                requiresPaidTier: true,
                capabilities: full,
                pricing: ModelPricing(inputPricePer1K: 0.010, outputPricePer1K: 0.050, currency: "USD")
            ),
            EnhancedAIModel(
                id: "claude-sonnet-5",
                provider: .anthropic,
                modelID: "claude-sonnet-5",
                displayName: "Claude Sonnet 5",
                description: "Near-Opus coding quality at a third of the price",
                contextWindow: 1_000_000,
                maxOutput: 128_000,
                requiresPaidTier: false,
                capabilities: full,
                pricing: ModelPricing(inputPricePer1K: 0.003, outputPricePer1K: 0.015, currency: "USD")
            ),
            EnhancedAIModel(
                id: "claude-haiku-4-5",
                provider: .anthropic,
                modelID: "claude-haiku-4-5",
                displayName: "Claude Haiku 4.5",
                description: "Fastest and cheapest — drafting, lookups, light edits",
                contextWindow: 200_000,
                maxOutput: 64_000,
                requiresPaidTier: false,
                capabilities: full,
                pricing: ModelPricing(inputPricePer1K: 0.001, outputPricePer1K: 0.005, currency: "USD")
            ),

            // MARK: OpenAI
            EnhancedAIModel(
                id: "gpt-5.2",
                provider: .openAI,
                modelID: "gpt-5.2",
                displayName: "GPT-5.2",
                description: "OpenAI's general flagship — reasoning and broad tasks",
                contextWindow: 400_000,
                maxOutput: 128_000,
                requiresPaidTier: false,
                capabilities: full,
                pricing: nil
            ),
            EnhancedAIModel(
                id: "gpt-5.3-codex",
                provider: .openAI,
                modelID: "gpt-5.3-codex",
                displayName: "GPT-5.3 Codex",
                description: "OpenAI's agentic coding model",
                contextWindow: 400_000,
                maxOutput: 128_000,
                requiresPaidTier: false,
                capabilities: full,
                pricing: nil
            ),

            // MARK: Google
            EnhancedAIModel(
                id: "gemini-3-pro",
                provider: .google,
                modelID: "gemini-3-pro",
                displayName: "Gemini 3 Pro",
                description: "Google's flagship — strong multimodal reasoning",
                contextWindow: 1_000_000,
                maxOutput: 65_536,
                requiresPaidTier: false,
                capabilities: full,
                pricing: nil
            ),
            EnhancedAIModel(
                id: "gemini-2.5-flash",
                provider: .google,
                modelID: "gemini-2.5-flash",
                displayName: "Gemini 2.5 Flash",
                description: "Fast and cheap Gemini for high-volume work",
                contextWindow: 1_000_000,
                maxOutput: 65_536,
                requiresPaidTier: false,
                capabilities: full,
                pricing: nil
            ),

            // MARK: OpenRouter (passthrough routes)
            EnhancedAIModel(
                id: "anthropic/claude-sonnet-5",
                provider: .openRouter,
                modelID: "anthropic/claude-sonnet-5",
                displayName: "Claude Sonnet 5 (OpenRouter)",
                description: "Sonnet 5 routed through OpenRouter",
                contextWindow: 1_000_000,
                maxOutput: 128_000,
                requiresPaidTier: false,
                capabilities: full,
                pricing: nil
            ),
            EnhancedAIModel(
                id: "openai/gpt-5.3-codex",
                provider: .openRouter,
                modelID: "openai/gpt-5.3-codex",
                displayName: "GPT-5.3 Codex (OpenRouter)",
                description: "Codex routed through OpenRouter",
                contextWindow: 400_000,
                maxOutput: 128_000,
                requiresPaidTier: false,
                capabilities: full,
                pricing: nil
            ),
            EnhancedAIModel(
                id: "google/gemini-3-pro",
                provider: .openRouter,
                modelID: "google/gemini-3-pro",
                displayName: "Gemini 3 Pro (OpenRouter)",
                description: "Gemini 3 Pro routed through OpenRouter",
                contextWindow: 1_000_000,
                maxOutput: 65_536,
                requiresPaidTier: false,
                capabilities: full,
                pricing: nil
            ),
            EnhancedAIModel(
                id: "qwen/qwen3-coder",
                provider: .openRouter,
                modelID: "qwen/qwen3-coder",
                displayName: "Qwen3 Coder (OpenRouter)",
                description: "The legacy Qwen coding lane, via OpenRouter",
                contextWindow: 262_144,
                maxOutput: 65_536,
                requiresPaidTier: false,
                capabilities: text,
                pricing: nil
            )
        ]
    }
}
