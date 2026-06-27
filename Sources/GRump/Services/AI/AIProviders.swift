// ╔══════════════════════════════════════════════════════════════╗
// ║  AIProviders.swift                                          ║
// ║  Qwen provider — models, capabilities, and the registry      ║
// ╚══════════════════════════════════════════════════════════════╝

import Foundation

// MARK: - AI Provider System

enum AIProvider: String, CaseIterable, Identifiable, Codable {
    case qwen = "qwen"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .qwen: return "Qwen"
        }
    }

    var description: String {
        switch self {
        case .qwen: return "Alibaba Qwen models via Qwen Cloud (DashScope)"
        }
    }

    var requiresAPIKey: Bool {
        switch self {
        case .qwen: return true
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .qwen: return "https://dashscope-intl.aliyuncs.com/compatible-mode/v1"
        }
    }
}

// MARK: - Model Mode

struct ModelMode: Codable, Equatable, Identifiable {
    let id: String
    let displayName: String
    let apiModelID: String?
    let overrideContextWindow: Int?
    let overrideMaxOutput: Int?

    init(id: String, displayName: String, apiModelID: String? = nil, overrideContextWindow: Int? = nil, overrideMaxOutput: Int? = nil) {
        self.id = id
        self.displayName = displayName
        self.apiModelID = apiModelID
        self.overrideContextWindow = overrideContextWindow
        self.overrideMaxOutput = overrideMaxOutput
    }
}

// MARK: - Enhanced AI Model

struct EnhancedAIModel: Identifiable, Codable, Equatable {
    let id: String
    let provider: AIProvider
    let modelID: String
    let displayName: String
    let description: String
    let contextWindow: Int
    let maxOutput: Int
    let requiresPaidTier: Bool
    let capabilities: ModelCapabilities
    let pricing: ModelPricing?
    let modes: [ModelMode]

    var rawValue: String { modelID }

    var hasModes: Bool { !modes.isEmpty }

    func effectiveModelID(mode: ModelMode?) -> String {
        guard let mode = mode, let override = mode.apiModelID else { return modelID }
        return override
    }

    func effectiveContextWindow(mode: ModelMode?) -> Int {
        mode?.overrideContextWindow ?? contextWindow
    }

    func effectiveMaxOutput(mode: ModelMode?) -> Int {
        mode?.overrideMaxOutput ?? maxOutput
    }

    init(id: String, provider: AIProvider, modelID: String, displayName: String, description: String,
         contextWindow: Int, maxOutput: Int, requiresPaidTier: Bool, capabilities: ModelCapabilities,
         pricing: ModelPricing?, modes: [ModelMode] = []) {
        self.id = id
        self.provider = provider
        self.modelID = modelID
        self.displayName = displayName
        self.description = description
        self.contextWindow = contextWindow
        self.maxOutput = maxOutput
        self.requiresPaidTier = requiresPaidTier
        self.capabilities = capabilities
        self.pricing = pricing
        self.modes = modes
    }

    static func == (lhs: EnhancedAIModel, rhs: EnhancedAIModel) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Model Capabilities

struct ModelCapabilities: Codable, Equatable {
    let supportsTools: Bool
    let supportsVision: Bool
    let supportsStreaming: Bool
    let supportsFunctionCalling: Bool
    let supportsJSONMode: Bool
    let maxTokens: Int?
    let supportsSystemMessages: Bool
    let supportsParallelToolUse: Bool

    static let `default` = ModelCapabilities(
        supportsTools: true,
        supportsVision: false,
        supportsStreaming: true,
        supportsFunctionCalling: true,
        supportsJSONMode: false,
        maxTokens: nil,
        supportsSystemMessages: true,
        supportsParallelToolUse: false
    )
}

// MARK: - Model Pricing

struct ModelPricing: Codable, Equatable {
    let inputPricePer1K: Double  // Price per 1K input tokens
    let outputPricePer1K: Double // Price per 1K output tokens
    let currency: String

    var formattedInputPrice: String {
        return String(format: "%.4f %@", inputPricePer1K, currency)
    }

    var formattedOutputPrice: String {
        return String(format: "%.4f %@", outputPricePer1K, currency)
    }
}

// MARK: - Provider Configuration

struct ProviderConfiguration: Codable {
    let provider: AIProvider
    var apiKey: String?
    var baseURL: String?
    var isEnabled: Bool = true
    var customHeaders: [String: String] = [:]

    init(provider: AIProvider, apiKey: String? = nil, baseURL: String? = nil) {
        self.provider = provider
        self.apiKey = apiKey
        self.baseURL = baseURL ?? provider.defaultBaseURL
    }
}

// MARK: - Model Registry

final class AIModelRegistry: @unchecked Sendable {
    static let shared = AIModelRegistry()

    private var models: [EnhancedAIModel] = []
    private var providerConfigs: [AIProvider: ProviderConfiguration] = [:]

    private init() {
        loadDefaultModels()
        loadProviderConfigurations()
    }

    // MARK: - Public Interface

    func getAllModels() -> [EnhancedAIModel] {
        return models.sorted { $0.displayName < $1.displayName }
    }

    func getModels(for provider: AIProvider) -> [EnhancedAIModel] {
        return models.filter { $0.provider == provider }
            .sorted { $0.displayName < $1.displayName }
    }

    func getModel(by id: String) -> EnhancedAIModel? {
        return models.first { $0.id == id }
    }

    func getProviderConfig(for provider: AIProvider) -> ProviderConfiguration? {
        return providerConfigs[provider]
    }

    func setProviderConfig(_ config: ProviderConfiguration) {
        providerConfigs[config.provider] = config
        saveProviderConfigurations()
    }

    func isProviderConfigured(_ provider: AIProvider) -> Bool {
        guard let config = providerConfigs[provider] else { return false }
        if !provider.requiresAPIKey { return true }
        return !(config.apiKey?.isEmpty ?? true)
    }

    // MARK: - Model Loading (catalog in AIModelCatalog.swift)

    private func loadDefaultModels() {
        models = defaultModelCatalog()
    }

    // MARK: - Configuration Management

    private func loadProviderConfigurations() {
        if let data = UserDefaults.standard.data(forKey: "AIProviderConfigurations"),
           let configs = try? JSONDecoder().decode([ProviderConfiguration].self, from: data) {
            for config in configs {
                providerConfigs[config.provider] = config
            }
        }

        // Set up default configurations for unconfigured providers
        for provider in AIProvider.allCases {
            if providerConfigs[provider] == nil {
                providerConfigs[provider] = ProviderConfiguration(provider: provider)
            }
        }
    }

    private func saveProviderConfigurations() {
        let configs = Array(providerConfigs.values)
        if let data = try? JSONEncoder().encode(configs) {
            UserDefaults.standard.set(data, forKey: "AIProviderConfigurations")
        }
    }

}
