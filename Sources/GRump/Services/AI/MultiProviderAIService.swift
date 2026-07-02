import Foundation
import Combine

// MARK: - Multi-Provider AI Service

@MainActor
class MultiProviderAIService: ObservableObject {
    static let shared = MultiProviderAIService()
    @Published var currentProvider: AIProvider = .anthropic
    @Published var currentModel: EnhancedAIModel?
    @Published var availableModels: [EnhancedAIModel] = []
    @Published var isConfigured: Bool = false

    let modelRegistry = AIModelRegistry.shared
    private var coreMLService: CoreMLInferenceService?
    private var cancellables = Set<AnyCancellable>()

    init() {
        self.coreMLService = CoreMLInferenceService()
        loadConfiguration()
        refreshModels()

        // Auto-refresh local models when provider changes
        $currentProvider
            .sink { [weak self] provider in
                switch provider {
                case .ollama:
                    Task {
                        await self?.modelRegistry.refreshOllamaModels()
                        await MainActor.run {
                            self?.refreshModels()
                        }
                    }
                case .onDevice:
                    Task { @MainActor in
                        self?.coreMLService?.refreshAvailableModels()
                        self?.refreshModels()
                    }
                default:
                    break
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Configuration

    private func loadConfiguration() {
        if let providerString = UserDefaults.standard.string(forKey: "CurrentAIProvider"),
           let provider = AIProvider(rawValue: providerString) {
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
        if currentProvider == .onDevice {
            // On-device models come from CoreMLInferenceService, not the registry
            availableModels = coreMLService?.enhancedModels() ?? []
        } else {
            availableModels = modelRegistry.getModels(for: currentProvider)
        }

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

        // On-device inference does not need a provider config
        if model.provider == .onDevice {
            return streamOnDevice(messages: messages, model: model)
        }

        guard let config = modelRegistry.getProviderConfig(for: model.provider) else {
            return AsyncThrowingStream { $0.finish(throwing: AIServiceError.providerNotConfigured) }
        }

        switch model.provider {
        case .openRouter:
            return streamOpenRouter(messages: messages, model: model, config: config, tools: tools)
        case .openAI:
            return streamOpenAI(messages: messages, model: model, config: config, tools: tools)
        case .anthropic:
            return streamAnthropic(messages: messages, model: model, config: config, tools: tools)
        case .google:
            return streamGoogle(messages: messages, model: model, config: config, tools: tools)
        case .ollama:
            return streamOllama(messages: messages, model: model, config: config, tools: tools)
        case .onDevice:
            return streamOnDevice(messages: messages, model: model) // Already handled above
        }
    }

    // MARK: - Provider-Specific Streaming

    func streamOpenRouter(
        messages: [Message],
        model: EnhancedAIModel,
        config: ProviderConfiguration,
        tools: [[String: Any]]?
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        let openRouterService = OpenRouterService()
        return openRouterService.streamMessage(
            messages: messages,
            apiKey: config.apiKey ?? "",
            model: model.modelID,
            tools: tools
        )
    }

    nonisolated func streamOpenAI(
        messages: [Message],
        model: EnhancedAIModel,
        config: ProviderConfiguration,
        tools: [[String: Any]]?
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        return AsyncThrowingStream<StreamEvent, Error>(bufferingPolicy: .unbounded) { continuation in
            Task {
                do {
                    let request = try buildOpenAIRequest(
                        messages: messages,
                        model: model.modelID,
                        apiKey: config.apiKey ?? "",
                        baseURL: config.baseURL ?? model.provider.defaultBaseURL,
                        tools: tools,
                        stream: true
                    )

                    let (bytes, response) = try await StreamingNetwork.session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw AIServiceError.networkError
                    }

                    guard httpResponse.statusCode == 200 else {
                        throw AIServiceError.apiError(httpResponse.statusCode)
                    }

                    try await SSELineParser.parseOpenAICompatible(bytes: bytes, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    nonisolated func streamAnthropic(
        messages: [Message],
        model: EnhancedAIModel,
        config: ProviderConfiguration,
        tools: [[String: Any]]?
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        return AsyncThrowingStream<StreamEvent, Error> { continuation in
            Task {
                do {
                    let request = try buildAnthropicRequest(
                        messages: messages,
                        model: model.modelID,
                        apiKey: config.apiKey ?? "",
                        baseURL: config.baseURL ?? model.provider.defaultBaseURL,
                        tools: tools,
                        stream: true
                    )

                    let (bytes, response) = try await StreamingNetwork.session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw AIServiceError.networkError
                    }

                    guard httpResponse.statusCode == 200 else {
                        throw AIServiceError.apiError(httpResponse.statusCode)
                    }

                    try await SSELineParser.parseAnthropic(bytes: bytes, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    nonisolated func streamOllama(
        messages: [Message],
        model: EnhancedAIModel,
        config: ProviderConfiguration,
        tools: [[String: Any]]?
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        return AsyncThrowingStream<StreamEvent, Error> { continuation in
            Task {
                do {
                    let request = try buildOllamaRequest(
                        messages: messages,
                        model: model.modelID,
                        baseURL: config.baseURL ?? model.provider.defaultBaseURL,
                        tools: tools,
                        stream: true
                    )

                    let (bytes, response) = try await StreamingNetwork.session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw AIServiceError.networkError
                    }

                    guard httpResponse.statusCode == 200 else {
                        throw AIServiceError.apiError(httpResponse.statusCode)
                    }

                    try await SSELineParser.parseOllamaNDJSON(bytes: bytes, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Google Gemini Streaming

    nonisolated func streamGoogle(
        messages: [Message],
        model: EnhancedAIModel,
        config: ProviderConfiguration,
        tools: [[String: Any]]?
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        return AsyncThrowingStream<StreamEvent, Error> { continuation in
            Task {
                do {
                    let request = try buildGoogleRequest(
                        messages: messages,
                        model: model.modelID,
                        apiKey: config.apiKey ?? "",
                        baseURL: config.baseURL ?? model.provider.defaultBaseURL,
                        tools: tools,
                        maxOutputTokens: model.maxOutput
                    )

                    let (bytes, response) = try await StreamingNetwork.session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw AIServiceError.networkError
                    }

                    guard httpResponse.statusCode == 200 else {
                        throw AIServiceError.apiError(httpResponse.statusCode)
                    }

                    try await SSELineParser.parseGoogleSSE(bytes: bytes, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - On-Device (Core ML) Streaming

    func streamOnDevice(
        messages: [Message],
        model: EnhancedAIModel
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        guard let service = coreMLService else {
            return AsyncThrowingStream { $0.finish(throwing: AIServiceError.providerNotConfigured) }
        }
        return service.streamMessage(messages: messages, maxTokens: model.maxOutput)
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
// Uses the canonical StreamEvent enum defined in OpenRouterService.swift

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
