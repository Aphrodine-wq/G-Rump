import Foundation

// MARK: - Default Model Catalog
//
// All built-in model definitions (Anthropic, OpenAI, Google, OpenRouter, On-Device).
// Extracted from AIProviders.swift for maintainability — this file is data-heavy
// and changes often when new models are released.

extension AIModelRegistry {

    // MARK: - Shared Capabilities

    static let fullCaps = ModelCapabilities(
        supportsTools: true, supportsVision: true, supportsStreaming: true,
        supportsFunctionCalling: true, supportsJSONMode: true, maxTokens: nil,
        supportsSystemMessages: true, supportsParallelToolUse: true
    )

    static let basicCaps = ModelCapabilities(
        supportsTools: true, supportsVision: false, supportsStreaming: true,
        supportsFunctionCalling: true, supportsJSONMode: false, maxTokens: nil,
        supportsSystemMessages: true, supportsParallelToolUse: false
    )

    // MARK: - Catalog

    func defaultModelCatalog() -> [EnhancedAIModel] {
        let full = Self.fullCaps
        let basic = Self.basicCaps

        return [

            // ──────────────────────────────────────────────
            // MARK: Anthropic (Direct API)
            // ──────────────────────────────────────────────

            EnhancedAIModel(
                id: "anthropic-claude-opus-4.6",
                provider: .anthropic,
                modelID: "claude-opus-4-6-20250827",
                displayName: "Claude Opus 4.6",
                description: "Flagship frontier — complex coding, agents, extended thinking",
                contextWindow: 200_000,
                maxOutput: 65_536,
                requiresPaidTier: true,
                capabilities: full,
                pricing: ModelPricing(inputPricePer1K: 0.015, outputPricePer1K: 0.075, currency: "USD"),
                modes: [
                    ModelMode(id: "standard", displayName: "Standard"),
                    ModelMode(id: "thinking", displayName: "Thinking"),
                    ModelMode(id: "fast", displayName: "Fast", apiModelID: "claude-opus-4-6-fast-20250827"),
                    ModelMode(id: "1m", displayName: "1M Context", overrideContextWindow: 1_000_000)
                ]
            ),

            EnhancedAIModel(
                id: "anthropic-claude-sonnet-4.6",
                provider: .anthropic,
                modelID: "claude-sonnet-4-6-20250827",
                displayName: "Claude Sonnet 4.6",
                description: "Frontier Sonnet — coding, agents, professional work",
                contextWindow: 200_000,
                maxOutput: 16_384,
                requiresPaidTier: true,
                capabilities: full,
                pricing: ModelPricing(inputPricePer1K: 0.003, outputPricePer1K: 0.015, currency: "USD"),
                modes: [
                    ModelMode(id: "standard", displayName: "Standard"),
                    ModelMode(id: "thinking", displayName: "Thinking"),
                    ModelMode(id: "fast", displayName: "Fast", apiModelID: "claude-sonnet-4-6-fast-20250827")
                ]
            ),

            EnhancedAIModel(
                id: "anthropic-claude-sonnet-4",
                provider: .anthropic,
                modelID: "claude-sonnet-4-20250514",
                displayName: "Claude Sonnet 4",
                description: "Balanced coding and reasoning, excellent tool use",
                contextWindow: 200_000,
                maxOutput: 16_000,
                requiresPaidTier: false,
                capabilities: full,
                pricing: ModelPricing(inputPricePer1K: 0.003, outputPricePer1K: 0.015, currency: "USD")
            ),

            EnhancedAIModel(
                id: "anthropic-claude-3-5-haiku",
                provider: .anthropic,
                modelID: "claude-3-5-haiku-20241022",
                displayName: "Claude 3.5 Haiku",
                description: "Fast and compact, great for simple tasks and high throughput",
                contextWindow: 200_000,
                maxOutput: 8_192,
                requiresPaidTier: false,
                capabilities: ModelCapabilities(
                    supportsTools: true, supportsVision: true, supportsStreaming: true,
                    supportsFunctionCalling: true, supportsJSONMode: false, maxTokens: nil,
                    supportsSystemMessages: true, supportsParallelToolUse: false
                ),
                pricing: ModelPricing(inputPricePer1K: 0.0008, outputPricePer1K: 0.004, currency: "USD")
            ),

            // ──────────────────────────────────────────────
            // MARK: OpenAI (Direct API)
            // ──────────────────────────────────────────────

            EnhancedAIModel(
                id: "openai-codex-5.3",
                provider: .openAI,
                modelID: "codex-5.3",
                displayName: "Codex 5.3",
                description: "OpenAI's latest coding model — agentic, multi-file, deep reasoning",
                contextWindow: 200_000,
                maxOutput: 65_536,
                requiresPaidTier: true,
                capabilities: full,
                pricing: ModelPricing(inputPricePer1K: 0.005, outputPricePer1K: 0.02, currency: "USD"),
                modes: [
                    ModelMode(id: "standard", displayName: "Standard"),
                    ModelMode(id: "reasoning", displayName: "Reasoning", apiModelID: "codex-5.3-reasoning"),
                    ModelMode(id: "fast", displayName: "Fast", apiModelID: "codex-5.3-fast")
                ]
            ),

            EnhancedAIModel(
                id: "openai-gpt-4o",
                provider: .openAI,
                modelID: "gpt-4o",
                displayName: "GPT-4o",
                description: "Multimodal flagship with vision and audio",
                contextWindow: 128_000,
                maxOutput: 16_384,
                requiresPaidTier: false,
                capabilities: full,
                pricing: ModelPricing(inputPricePer1K: 0.0025, outputPricePer1K: 0.01, currency: "USD")
            ),

            EnhancedAIModel(
                id: "openai-gpt-4o-mini",
                provider: .openAI,
                modelID: "gpt-4o-mini",
                displayName: "GPT-4o Mini",
                description: "Fast multimodal model for most tasks",
                contextWindow: 128_000,
                maxOutput: 16_384,
                requiresPaidTier: false,
                capabilities: full,
                pricing: ModelPricing(inputPricePer1K: 0.00015, outputPricePer1K: 0.0006, currency: "USD")
            ),

            EnhancedAIModel(
                id: "openai-o3",
                provider: .openAI,
                modelID: "o3",
                displayName: "o3",
                description: "Advanced reasoning model for complex problems",
                contextWindow: 200_000,
                maxOutput: 100_000,
                requiresPaidTier: true,
                capabilities: full,
                pricing: ModelPricing(inputPricePer1K: 0.01, outputPricePer1K: 0.04, currency: "USD")
            ),

            EnhancedAIModel(
                id: "openai-o3-mini",
                provider: .openAI,
                modelID: "o3-mini",
                displayName: "o3 Mini",
                description: "Fast reasoning model, cost-efficient",
                contextWindow: 200_000,
                maxOutput: 100_000,
                requiresPaidTier: false,
                capabilities: full,
                pricing: ModelPricing(inputPricePer1K: 0.00115, outputPricePer1K: 0.0044, currency: "USD")
            ),

            EnhancedAIModel(
                id: "openai-o4-mini",
                provider: .openAI,
                modelID: "o4-mini",
                displayName: "o4 Mini",
                description: "Latest reasoning model with tool use and vision",
                contextWindow: 200_000,
                maxOutput: 100_000,
                requiresPaidTier: false,
                capabilities: full,
                pricing: ModelPricing(inputPricePer1K: 0.00115, outputPricePer1K: 0.0044, currency: "USD")
            ),

            // ──────────────────────────────────────────────
            // MARK: Google Gemini (Direct API)
            // ──────────────────────────────────────────────

            EnhancedAIModel(
                id: "google-gemini-3.1-pro",
                provider: .google,
                modelID: "gemini-3.1-pro",
                displayName: "Gemini 3.1 Pro",
                description: "Flagship reasoning, complex coding, 1M context window",
                contextWindow: 1_000_000,
                maxOutput: 65_536,
                requiresPaidTier: true,
                capabilities: full,
                pricing: ModelPricing(inputPricePer1K: 0.00125, outputPricePer1K: 0.01, currency: "USD")
            ),

            EnhancedAIModel(
                id: "google-gemini-3.1-flash",
                provider: .google,
                modelID: "gemini-3.1-flash",
                displayName: "Gemini 3.1 Flash",
                description: "Speed king — fast iteration, great for drafting and exploration",
                contextWindow: 1_000_000,
                maxOutput: 65_536,
                requiresPaidTier: false,
                capabilities: full,
                pricing: ModelPricing(inputPricePer1K: 0.00015, outputPricePer1K: 0.0006, currency: "USD")
            ),

            // ──────────────────────────────────────────────
            // MARK: OpenRouter (Multi-Provider)
            // ──────────────────────────────────────────────

            EnhancedAIModel(
                id: "openrouter-claude-opus-4.6",
                provider: .openRouter,
                modelID: "anthropic/claude-opus-4.6",
                displayName: "Claude Opus 4.6",
                description: "Flagship frontier model via OpenRouter — complex coding, agents, long context",
                contextWindow: 1_000_000,
                maxOutput: 65_536,
                requiresPaidTier: true,
                capabilities: full,
                pricing: ModelPricing(inputPricePer1K: 0.015, outputPricePer1K: 0.075, currency: "USD"),
                modes: [
                    ModelMode(id: "standard", displayName: "Standard"),
                    ModelMode(id: "thinking", displayName: "Thinking"),
                    ModelMode(id: "fast", displayName: "Fast", apiModelID: "anthropic/claude-opus-4.6:fast"),
                    ModelMode(id: "1m", displayName: "1M Context", overrideContextWindow: 1_000_000)
                ]
            ),

            EnhancedAIModel(
                id: "openrouter-claude-sonnet-4.6",
                provider: .openRouter,
                modelID: "anthropic/claude-sonnet-4.6",
                displayName: "Claude Sonnet 4.6",
                description: "Frontier Sonnet via OpenRouter — coding, agents, professional work",
                contextWindow: 200_000,
                maxOutput: 16_384,
                requiresPaidTier: true,
                capabilities: full,
                pricing: ModelPricing(inputPricePer1K: 0.003, outputPricePer1K: 0.015, currency: "USD"),
                modes: [
                    ModelMode(id: "standard", displayName: "Standard"),
                    ModelMode(id: "thinking", displayName: "Thinking"),
                    ModelMode(id: "fast", displayName: "Fast", apiModelID: "anthropic/claude-sonnet-4.6:fast")
                ]
            ),

            EnhancedAIModel(
                id: "openrouter-claude-sonnet-4",
                provider: .openRouter,
                modelID: "anthropic/claude-sonnet-4",
                displayName: "Claude Sonnet 4",
                description: "Balanced coding and reasoning via OpenRouter",
                contextWindow: 200_000,
                maxOutput: 16_000,
                requiresPaidTier: false,
                capabilities: full,
                pricing: ModelPricing(inputPricePer1K: 0.003, outputPricePer1K: 0.015, currency: "USD")
            ),

            EnhancedAIModel(
                id: "openrouter-gemini-3.1-pro",
                provider: .openRouter,
                modelID: "google/gemini-3.1-pro",
                displayName: "Gemini 3.1 Pro",
                description: "Flagship reasoning via OpenRouter, 1M context",
                contextWindow: 1_000_000,
                maxOutput: 65_536,
                requiresPaidTier: true,
                capabilities: full,
                pricing: ModelPricing(inputPricePer1K: 0.00125, outputPricePer1K: 0.01, currency: "USD")
            ),

            EnhancedAIModel(
                id: "openrouter-gemini-3.1-flash",
                provider: .openRouter,
                modelID: "google/gemini-3.1-flash",
                displayName: "Gemini 3.1 Flash",
                description: "Speed king via OpenRouter — fast iteration",
                contextWindow: 1_000_000,
                maxOutput: 65_536,
                requiresPaidTier: false,
                capabilities: full,
                pricing: ModelPricing(inputPricePer1K: 0.00015, outputPricePer1K: 0.0006, currency: "USD")
            ),

            EnhancedAIModel(
                id: "openrouter-codex-5.3",
                provider: .openRouter,
                modelID: "openai/codex-5.3",
                displayName: "Codex 5.3",
                description: "OpenAI's latest coding model via OpenRouter",
                contextWindow: 200_000,
                maxOutput: 65_536,
                requiresPaidTier: true,
                capabilities: full,
                pricing: ModelPricing(inputPricePer1K: 0.005, outputPricePer1K: 0.02, currency: "USD"),
                modes: [
                    ModelMode(id: "standard", displayName: "Standard"),
                    ModelMode(id: "reasoning", displayName: "Reasoning", apiModelID: "openai/codex-5.3-reasoning"),
                    ModelMode(id: "fast", displayName: "Fast", apiModelID: "openai/codex-5.3-fast")
                ]
            ),

            EnhancedAIModel(
                id: "openrouter-kimi-k2.5",
                provider: .openRouter,
                modelID: "moonshotai/kimi-k2.5",
                displayName: "Kimi K2.5",
                description: "Strong reasoning and visual coding, top tool use",
                contextWindow: 200_000,
                maxOutput: 16_384,
                requiresPaidTier: true,
                capabilities: full,
                pricing: ModelPricing(inputPricePer1K: 0.002, outputPricePer1K: 0.008, currency: "USD")
            ),

            // ──────────────────────────────────────────────
            // MARK: OpenRouter — Free Models
            // ──────────────────────────────────────────────

            EnhancedAIModel(
                id: "openrouter-deepseek-chat",
                provider: .openRouter,
                modelID: "deepseek/deepseek-chat-v3-0324:free",
                displayName: "DeepSeek V3",
                description: "Strong coder, free DeepSeek V3",
                contextWindow: 164_000,
                maxOutput: 16_384,
                requiresPaidTier: false,
                capabilities: basic,
                pricing: nil
            ),

            EnhancedAIModel(
                id: "openrouter-qwen3-coder",
                provider: .openRouter,
                modelID: "qwen/qwen3-coder:free",
                displayName: "Qwen3 Coder 480B",
                description: "Best free coding model, 480B MoE, agentic tool use",
                contextWindow: 262_144,
                maxOutput: 32_768,
                requiresPaidTier: false,
                capabilities: basic,
                pricing: nil
            ),

            EnhancedAIModel(
                id: "openrouter-deepseek-r1",
                provider: .openRouter,
                modelID: "deepseek/deepseek-r1-0528:free",
                displayName: "DeepSeek R1",
                description: "Open-source reasoning on par with o1, 164K context",
                contextWindow: 164_000,
                maxOutput: 32_768,
                requiresPaidTier: false,
                capabilities: basic,
                pricing: nil
            ),

            EnhancedAIModel(
                id: "openrouter-gpt-oss-120b",
                provider: .openRouter,
                modelID: "openai/gpt-oss-120b:free",
                displayName: "GPT-OSS 120B",
                description: "OpenAI open-weight MoE, native tool use & reasoning",
                contextWindow: 128_000,
                maxOutput: 16_384,
                requiresPaidTier: false,
                capabilities: basic,
                pricing: nil
            ),

            EnhancedAIModel(
                id: "openrouter-trinity-large",
                provider: .openRouter,
                modelID: "arcee-ai/trinity-large-preview:free",
                displayName: "Trinity Large 400B",
                description: "400B MoE, trained for agentic coding (Cline/OpenCode)",
                contextWindow: 128_000,
                maxOutput: 16_384,
                requiresPaidTier: false,
                capabilities: basic,
                pricing: nil
            ),

            EnhancedAIModel(
                id: "openrouter-step-3.5-flash",
                provider: .openRouter,
                modelID: "stepfun/step-3.5-flash:free",
                displayName: "Step 3.5 Flash",
                description: "196B MoE, blazing fast at 256K context",
                contextWindow: 256_000,
                maxOutput: 16_384,
                requiresPaidTier: false,
                capabilities: basic,
                pricing: nil
            ),

            EnhancedAIModel(
                id: "openrouter-llama-3.3-70b",
                provider: .openRouter,
                modelID: "meta-llama/llama-3.3-70b-instruct:free",
                displayName: "Llama 3.3 70B",
                description: "Meta's best open-weight 70B, multilingual coding",
                contextWindow: 128_000,
                maxOutput: 16_384,
                requiresPaidTier: false,
                capabilities: basic,
                pricing: nil
            ),

            EnhancedAIModel(
                id: "openrouter-glm-4.5-air",
                provider: .openRouter,
                modelID: "z-ai/glm-4.5-air:free",
                displayName: "GLM 4.5 Air",
                description: "Agent-first model with thinking mode, tool use",
                contextWindow: 128_000,
                maxOutput: 16_384,
                requiresPaidTier: false,
                capabilities: basic,
                pricing: nil
            ),

            // ──────────────────────────────────────────────
            // MARK: On-Device (Apple Silicon)
            // ──────────────────────────────────────────────

            EnhancedAIModel(
                id: "ondevice-apple-foundation",
                provider: .onDevice,
                modelID: "apple-foundation-model",
                displayName: "Apple Foundation Model",
                description: "On-device Apple Intelligence — zero cost, zero latency, full privacy",
                contextWindow: 32_000,
                maxOutput: 4_096,
                requiresPaidTier: false,
                capabilities: ModelCapabilities(
                    supportsTools: true, supportsVision: false, supportsStreaming: true,
                    supportsFunctionCalling: true, supportsJSONMode: false, maxTokens: nil,
                    supportsSystemMessages: true, supportsParallelToolUse: false
                ),
                pricing: nil
            ),

            EnhancedAIModel(
                id: "ondevice-coreml",
                provider: .onDevice,
                modelID: "coreml-local",
                displayName: "Core ML Local",
                description: "Custom Core ML model — bring your own GGUF or MLX model",
                contextWindow: 8_192,
                maxOutput: 2_048,
                requiresPaidTier: false,
                capabilities: ModelCapabilities.default,
                pricing: nil
            )
        ]
    }
}
