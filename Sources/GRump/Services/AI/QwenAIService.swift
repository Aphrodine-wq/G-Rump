import Foundation
import Combine

// MARK: - AI Service (Qwen Cloud)
//
// Single-provider service. All chat completions route through the
// OpenAICompatibleService transport, configured for Qwen Cloud (Alibaba
// DashScope, OpenAI-compatible), carrying the tool-call-complete body the agent
// loop depends on. The multi-provider dispatch is restored in a later phase.

@MainActor
class QwenAIService: ObservableObject {
    static let shared = QwenAIService()
    @Published var currentProvider: AIProvider = .qwen
    @Published var currentModel: EnhancedAIModel?
    @Published var availableModels: [EnhancedAIModel] = []
    @Published var isConfigured: Bool = false

    let modelRegistry = AIModelRegistry.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        loadConfiguration()
        refreshModels()
    }

    // MARK: - Configuration

    private func loadConfiguration() {
        // Provider is always Qwen now; only the model selection is restored.
        currentProvider = .qwen
        if let modelID = UserDefaults.standard.string(forKey: "CurrentAIModel") {
            currentModel = modelRegistry.getModel(by: modelID)
        }
        updateConfigurationStatus()
    }

    private func saveConfiguration() {
        UserDefaults.standard.set(currentProvider.rawValue, forKey: "CurrentAIProvider")
        UserDefaults.standard.set(currentModel?.id, forKey: "CurrentAIModel")
    }

    private func updateConfigurationStatus() {
        isConfigured = modelRegistry.isProviderConfigured(currentProvider)
    }

    // MARK: - Model Management

    func refreshModels() {
        availableModels = modelRegistry.getModels(for: currentProvider)

        // If current model is not in the available models, select the first one
        if let currentModel = currentModel,
           !availableModels.contains(where: { $0.id == currentModel.id }) {
            self.currentModel = availableModels.first
        } else if currentModel == nil {
            currentModel = availableModels.first
        }

        updateConfigurationStatus()
    }

    func selectProvider(_ provider: AIProvider) {
        currentProvider = provider
        refreshModels()
        saveConfiguration()
    }

    func selectModel(_ model: EnhancedAIModel) {
        currentModel = model
        saveConfiguration()
    }

    func configureProvider(_ provider: AIProvider, apiKey: String?, baseURL: String?) {
        let config = ProviderConfiguration(
            provider: provider,
            apiKey: apiKey,
            baseURL: baseURL
        )
        modelRegistry.setProviderConfig(config)

        if provider == currentProvider {
            updateConfigurationStatus()
        }
    }

    // MARK: - Chat Completions

    func streamMessage(
        messages: [Message],
        tools: [[String: Any]]? = nil
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        guard let model = currentModel else {
            return AsyncThrowingStream { $0.finish(throwing: AIServiceError.noModelSelected) }
        }
        guard let config = modelRegistry.getProviderConfig(for: model.provider) else {
            return AsyncThrowingStream { $0.finish(throwing: AIServiceError.providerNotConfigured) }
        }
        return streamQwen(messages: messages, model: model, config: config, tools: tools)
    }

    // MARK: - Qwen Streaming (single transport)

    func streamQwen(
        messages: [Message],
        model: EnhancedAIModel,
        config: ProviderConfiguration,
        tools: [[String: Any]]?
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        let service = OpenAICompatibleService()
        return service.streamMessage(
            messages: messages,
            apiKey: config.apiKey ?? "",
            model: model.modelID,
            maxTokens: model.maxOutput,
            tools: tools
        )
    }
}

// MARK: - Error Types

enum AIServiceError: LocalizedError {
    case noModelSelected
    case providerNotConfigured
    case networkError
    case apiError(Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .noModelSelected:
            return "No AI model selected"
        case .providerNotConfigured:
            return "AI provider not configured"
        case .networkError:
            return "Network error occurred"
        case .apiError(let code):
            return "API error: \(code)"
        case .invalidResponse:
            return "Invalid response from server"
        }
    }
}

// MARK: - Stream Event
// Uses the canonical StreamEvent enum defined in OpenAICompatibleService.swift

// MARK: - Extensions

extension Dictionary {
    func jsonString() -> String {
        if let data = try? JSONSerialization.data(withJSONObject: self),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return "{}"
    }
}
