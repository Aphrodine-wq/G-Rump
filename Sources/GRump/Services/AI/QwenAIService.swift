import Foundation
import Combine

// MARK: - AI Service (multi-provider)
//
// Orchestrates provider/model selection and dispatches chat completions.
// OpenAI and OpenRouter ride the parameterized OpenAICompatibleService
// transport; the native Anthropic and Google request builders are restored in
// the next phase — until then those providers surface a clear error instead
// of silently posting Anthropic payloads to the wrong host.

@MainActor
class QwenAIService: ObservableObject {
    static let shared = QwenAIService()
    @Published var currentProvider: AIProvider = .anthropic
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
        if let saved = UserDefaults.standard.string(forKey: "CurrentAIProvider"),
           let provider = AIProvider(rawValue: saved) {
            currentProvider = provider
        }
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

        // If the current model doesn't belong to this provider, fall back to
        // the provider's default (Opus 4.8 for Anthropic — never Fable).
        if let currentModel = currentModel,
           !availableModels.contains(where: { $0.id == currentModel.id }) {
            self.currentModel = modelRegistry.defaultModel(for: currentProvider)
        } else if currentModel == nil {
            currentModel = modelRegistry.defaultModel(for: currentProvider)
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

        switch model.provider {
        case .openAI:
            return streamOpenAICompatible(.openAI, messages: messages, model: model, config: config, tools: tools)
        case .openRouter:
            return streamOpenAICompatible(.openRouter, messages: messages, model: model, config: config, tools: tools)
        case .anthropic, .google:
            // Native request builders land in the next phase of the provider
            // pivot. Failing loudly beats posting the wrong wire format.
            let name = model.provider.displayName
            return AsyncThrowingStream { $0.finish(throwing: AIServiceError.nativeProviderPending(name)) }
        }
    }

    // MARK: - OpenAI-Compatible Streaming (OpenAI, OpenRouter)

    private func streamOpenAICompatible(
        _ configuration: OpenAICompatibleService.Configuration,
        messages: [Message],
        model: EnhancedAIModel,
        config: ProviderConfiguration,
        tools: [[String: Any]]?
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        var transportConfig = configuration
        // Respect a per-provider base URL override from Settings.
        if let baseURL = config.baseURL, !baseURL.isEmpty {
            transportConfig.baseURL = baseURL
        }
        let service = OpenAICompatibleService(configuration: transportConfig)
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
    case nativeProviderPending(String)
    case networkError
    case apiError(Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .noModelSelected:
            return "No AI model selected"
        case .providerNotConfigured:
            return "AI provider not configured"
        case .nativeProviderPending(let name):
            return "\(name) support is still being wired up. Pick an OpenAI or OpenRouter model for now."
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
