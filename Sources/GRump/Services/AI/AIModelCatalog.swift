import Foundation

// MARK: - Default Model Catalog
//
// Qwen Cloud (Alibaba DashScope) model definitions. G-Rump was rebuilt entirely
// on Qwen, so this is the full catalog — one provider, a handful of tiers.
// `id` == `modelID` == the exact DashScope wire id.

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
            EnhancedAIModel(
                id: "qwen-coder-plus",
                provider: .qwen,
                modelID: "qwen-coder-plus",
                displayName: "Qwen Coder Plus",
                description: "Agentic coding model — multi-file edits, strong tool use",
                contextWindow: 1_000_000,
                maxOutput: 65_536,
                requiresPaidTier: false,
                capabilities: full,
                pricing: nil
            ),
            EnhancedAIModel(
                id: "qwen-max",
                provider: .qwen,
                modelID: "qwen-max",
                displayName: "Qwen Max",
                description: "Flagship Qwen — deepest reasoning and planning",
                contextWindow: 32_768,
                maxOutput: 8_192,
                requiresPaidTier: false,
                capabilities: full,
                pricing: nil
            ),
            EnhancedAIModel(
                id: "qwen-plus",
                provider: .qwen,
                modelID: "qwen-plus",
                displayName: "Qwen Plus",
                description: "Balanced reasoning and speed for everyday tasks",
                contextWindow: 131_072,
                maxOutput: 8_192,
                requiresPaidTier: false,
                capabilities: full,
                pricing: nil
            ),
            EnhancedAIModel(
                id: "qwen-turbo",
                provider: .qwen,
                modelID: "qwen-turbo",
                displayName: "Qwen Turbo",
                description: "Fastest, cheapest — drafting and quick iteration",
                contextWindow: 1_000_000,
                maxOutput: 8_192,
                requiresPaidTier: false,
                capabilities: basic,
                pricing: nil
            )
        ]
    }
}
