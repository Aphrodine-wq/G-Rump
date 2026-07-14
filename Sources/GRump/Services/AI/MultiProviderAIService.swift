import Foundation
import Combine

// MARK: - Multi-Provider AI Service
//
// Orchestrates provider/model selection and dispatches chat completions.
// Four providers: Anthropic and Google stream through native request
// builders (MultiProviderAIService+RequestBuilders.swift, parsers in
// SSELineParser+Providers.swift); OpenAI and OpenRouter ride the
// parameterized OpenAICompatibleService transport.

@MainActor
class MultiProviderAIService: ObservableObject {
    static let shared = MultiProviderAIService()
    @Published var currentProvider: AIProvider = .anthropic
    @Published var currentModel: EnhancedAIModel?
    @Published var availableModels: [EnhancedAIModel] = []
    @Published var isConfigured: Bool = false

    let modelRegistry = AIModelRegistry.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        loadConfiguration()
        refreshModels()
        discoverOllamaModels()
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
        if provider == .ollama {
            discoverOllamaModels()
        }
    }

    /// Fire-and-forget Ollama refresh; pickers update via refreshModels().
    func discoverOllamaModels() {
        Task { [weak self] in
            await self?.refreshOllamaModels()
        }
    }

    /// Refresh the registry's Ollama models from the local server. Returns the
    /// discovered model count, or nil when the server is unreachable (the last
    /// known set is kept so an idle server doesn't wipe the picker).
    @discardableResult
    func refreshOllamaModels() async -> Int? {
        let baseURL = AIModelRegistry.shared.getProviderConfig(for: .ollama)?.baseURL
        guard let discovered = await OllamaModelDiscovery.discoverModels(baseURL: baseURL) else {
            return nil
        }
        AIModelRegistry.shared.replaceModels(for: .ollama, with: discovered)
        refreshModels()
        return discovered.count
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
            return Self.errorStream(AIServiceError.noModelSelected)
        }
        guard let config = modelRegistry.getProviderConfig(for: model.provider) else {
            return Self.errorStream(AIServiceError.providerNotConfigured)
        }
        return Self.routedStream(messages: messages, model: model, config: config, tools: tools)
    }

    /// Stream against an explicit model id, independent of the UI selection.
    /// Used by side-consumers (Writing Tools, adversarial review, the model
    /// router). Unknown ids fall back to the app default — a stale persisted
    /// id must never crash a request.
    nonisolated static func stream(
        messages: [Message],
        modelID: String,
        tools: [[String: Any]]? = nil
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        let registry = AIModelRegistry.shared
        let model = registry.getModel(by: modelID) ?? registry.defaultModel()
        guard let config = registry.getProviderConfig(for: model.provider) else {
            return errorStream(AIServiceError.providerNotConfigured)
        }
        return routedStream(messages: messages, model: model, config: config, tools: tools)
    }

    // MARK: - Provider Dispatch

    nonisolated private static func routedStream(
        messages: [Message],
        model: EnhancedAIModel,
        config: ProviderConfiguration,
        tools: [[String: Any]]?
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        // Models without tool support (common for local Ollama models) get an
        // explicit empty tools list — the builders then omit the block entirely.
        let gatedTools: [[String: Any]]? = model.capabilities.supportsTools ? tools : []
        switch model.provider {
        case .openAI:
            return openAICompatibleStream(.openAI, messages: messages, model: model, config: config, tools: gatedTools)
        case .openRouter:
            return openAICompatibleStream(.openRouter, messages: messages, model: model, config: config, tools: gatedTools)
        case .ollama:
            return openAICompatibleStream(.ollama, messages: messages, model: model, config: config, tools: gatedTools)
        case .anthropic:
            return anthropicStream(messages: messages, model: model, config: config, tools: gatedTools)
        case .google:
            return googleStream(messages: messages, model: model, config: config, tools: gatedTools)
        }
    }

    // MARK: - OpenAI-Compatible Streaming (OpenAI, OpenRouter)

    nonisolated private static func openAICompatibleStream(
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

    // MARK: - Native Streaming (Anthropic, Google)

    nonisolated private static func anthropicStream(
        messages: [Message],
        model: EnhancedAIModel,
        config: ProviderConfiguration,
        tools: [[String: Any]]?
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        guard let apiKey = config.apiKey, !apiKey.isEmpty else {
            return errorStream(OpenAICompatibleService.ServiceError.missingAPIKey)
        }
        do {
            let request = try buildAnthropicRequest(
                messages: messages,
                model: model.modelID,
                apiKey: apiKey,
                baseURL: config.baseURL ?? AIProvider.anthropic.defaultBaseURL,
                maxTokens: model.maxOutput,
                tools: tools
            )
            return nativeStream(request: request, parser: .anthropic)
        } catch {
            return errorStream(error)
        }
    }

    nonisolated private static func googleStream(
        messages: [Message],
        model: EnhancedAIModel,
        config: ProviderConfiguration,
        tools: [[String: Any]]?
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        guard let apiKey = config.apiKey, !apiKey.isEmpty else {
            return errorStream(OpenAICompatibleService.ServiceError.missingAPIKey)
        }
        do {
            let request = try buildGoogleRequest(
                messages: messages,
                model: model.modelID,
                apiKey: apiKey,
                baseURL: config.baseURL ?? AIProvider.google.defaultBaseURL,
                maxOutputTokens: model.maxOutput,
                tools: tools
            )
            return nativeStream(request: request, parser: .google)
        } catch {
            return errorStream(error)
        }
    }

    enum NativeParser {
        case anthropic
        case google
    }

    nonisolated private static func nativeStream(
        request: URLRequest,
        parser: NativeParser
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let (bytes, response) = try await StreamingNetwork.session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw OpenAICompatibleService.ServiceError.networkError
                    }

                    guard httpResponse.statusCode == 200 else {
                        var errorData = Data()
                        for try await byte in bytes { errorData.append(byte) }
                        let message = OpenAICompatibleService.parseAPIErrorMessage(errorData)
                        if let errorString = String(data: errorData, encoding: .utf8), message == nil {
                            GRumpLogger.ai.error("API Error: \(errorString)")
                        }
                        throw OpenAICompatibleService.ServiceError.apiError(
                            statusCode: httpResponse.statusCode, message: message)
                    }

                    switch parser {
                    case .anthropic:
                        try await SSELineParser.parseAnthropic(bytes: bytes, continuation: continuation)
                    case .google:
                        try await SSELineParser.parseGoogle(bytes: bytes, continuation: continuation)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    nonisolated private static func errorStream(_ error: Error) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { $0.finish(throwing: error) }
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
