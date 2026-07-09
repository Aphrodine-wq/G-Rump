// ╔══════════════════════════════════════════════════════════════╗
// ║  AIProviders.swift                                          ║
// ║  Multi-provider system — providers, models, and the registry ║
// ╚══════════════════════════════════════════════════════════════╝

import Foundation

// MARK: - AI Provider System

enum AIProvider: String, CaseIterable, Identifiable, Codable {
    case anthropic = "anthropic"
    case openAI = "openai"
    case google = "google"
    case openRouter = "openrouter"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .anthropic: return "Anthropic"
        case .openAI: return "OpenAI"
        case .google: return "Google"
        case .openRouter: return "OpenRouter"
        }
    }

    var description: String {
        switch self {
        case .anthropic: return "Claude models via the Anthropic API"
        case .openAI: return "GPT models via the OpenAI API"
        case .google: return "Gemini models via the Google AI API"
        case .openRouter: return "Many models through one OpenRouter key"
        }
    }

    var requiresAPIKey: Bool { true }

    var defaultBaseURL: String {
        switch self {
        case .anthropic: return "https://api.anthropic.com/v1"
        case .openAI: return "https://api.openai.com/v1"
        case .google: return "https://generativelanguage.googleapis.com/v1beta"
        case .openRouter: return "https://openrouter.ai/api/v1"
        }
    }

    /// Keychain account name holding this provider's API key. Keychain is the
    /// single source of truth for keys; the UserDefaults registry never
    /// persists them (ProviderConfiguration excludes apiKey from Codable).
    var keychainAccount: String {
        switch self {
        case .anthropic: return "AnthropicAPIKey"
        case .openAI: return "OpenAIAPIKey"
        case .google: return "GoogleAPIKey"
        case .openRouter: return "OpenRouterAPIKey"
        }
    }

    var iconName: String {
        switch self {
        case .anthropic: return "asterisk"
        case .openAI: return "circle.hexagongrid"
        case .google: return "diamond"
        case .openRouter: return "arrow.triangle.branch"
        }
    }

    var keyPlaceholder: String {
        switch self {
        case .anthropic: return "sk-ant-..."
        case .openAI: return "sk-..."
        case .google: return "AIza..."
        case .openRouter: return "sk-or-..."
        }
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

    var rawValue: String { modelID }

    init(id: String, provider: AIProvider, modelID: String, displayName: String, description: String,
         contextWindow: Int, maxOutput: Int, requiresPaidTier: Bool, capabilities: ModelCapabilities,
         pricing: ModelPricing?) {
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

/// Per-provider settings. `apiKey` is runtime-only — hydrated from the Keychain
/// by the registry and deliberately excluded from Codable so keys never land in
/// UserDefaults (the old dual-storage bug).
struct ProviderConfiguration: Codable {
    let provider: AIProvider
    var apiKey: String?
    var baseURL: String?
    var isEnabled: Bool = true
    var customHeaders: [String: String] = [:]

    private enum CodingKeys: String, CodingKey {
        case provider, baseURL, isEnabled, customHeaders
    }

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
        // One-shot migration of Qwen-era persisted state. Runs here so it is
        // guaranteed to precede every read of provider/model defaults —
        // whichever subsystem touches the registry first pays for it.
        ProviderMigration.runIfNeeded()
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

    /// The app-wide default model: Claude Opus 4.8.
    func defaultModel() -> EnhancedAIModel? {
        return getModel(by: "claude-opus-4-8") ?? getModels(for: .anthropic).first
    }

    /// Sensible default per provider (never Fable — premium, explicit-select only).
    func defaultModel(for provider: AIProvider) -> EnhancedAIModel? {
        let preferred: String
        switch provider {
        case .anthropic: preferred = "claude-opus-4-8"
        case .openAI: preferred = "gpt-5.2"
        case .google: preferred = "gemini-3-pro"
        case .openRouter: preferred = "anthropic/claude-sonnet-5"
        }
        return getModel(by: preferred) ?? getModels(for: provider).first
    }

    func getProviderConfig(for provider: AIProvider) -> ProviderConfiguration? {
        return providerConfigs[provider]
    }

    func setProviderConfig(_ config: ProviderConfiguration) {
        providerConfigs[config.provider] = config
        // Keys ride the config in memory but persist only in the Keychain.
        if let key = config.apiKey {
            setAPIKey(key, for: config.provider)
        }
        saveProviderConfigurations()
    }

    func isProviderConfigured(_ provider: AIProvider) -> Bool {
        guard let config = providerConfigs[provider] else { return false }
        if !provider.requiresAPIKey { return true }
        return !(config.apiKey?.isEmpty ?? true)
    }

    // MARK: - API Keys (Keychain is the only persistence)

    func apiKey(for provider: AIProvider) -> String? {
        providerConfigs[provider]?.apiKey ?? KeychainStorage.get(account: provider.keychainAccount)
    }

    func setAPIKey(_ key: String, for provider: AIProvider) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            KeychainStorage.delete(account: provider.keychainAccount)
        } else {
            KeychainStorage.set(account: provider.keychainAccount, value: trimmed)
        }
        var config = providerConfigs[provider] ?? ProviderConfiguration(provider: provider)
        config.apiKey = trimmed.isEmpty ? nil : trimmed
        providerConfigs[provider] = config
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

        // Hydrate runtime keys from the Keychain.
        for provider in AIProvider.allCases {
            if let key = KeychainStorage.get(account: provider.keychainAccount), !key.isEmpty {
                providerConfigs[provider]?.apiKey = key
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
