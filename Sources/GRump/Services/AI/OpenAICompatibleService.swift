import Foundation

// MARK: - OpenAI-Compatible Transport
//
// Parameterized transport for any OpenAI-compatible chat-completions endpoint.
// A `Configuration` selects the base URL, extra headers, the max-tokens field
// name, OpenRouter routing hints, and whether to send `temperature`. This one
// transport serves Qwen (Alibaba DashScope), OpenAI, and OpenRouter; the native
// Anthropic and Google providers use their own request builders.
//
// The output-token cap arrives as an explicit `maxTokens` parameter — the caller
// sources it from the selected model, so the transport no longer reaches back
// into the legacy `AIModel` enum.

class OpenAICompatibleService {

    // MARK: - Configuration

    /// Per-provider transport configuration. Pure value type — use one of the
    /// static factories (`.qwen`, `.openAI`, `.openRouter`) or build a custom one.
    struct Configuration {
        /// The `/v1` root (no trailing slash, no `/chat/completions`).
        var baseURL: String
        /// Additional headers merged into every request.
        var extraHeaders: [String: String]
        /// JSON field carrying the output-token cap: `max_tokens` or
        /// `max_completion_tokens` (newer OpenAI models require the latter).
        var maxTokensField: String
        /// When true, attach OpenRouter routing headers (HTTP-Referer, X-Title,
        /// X-Client-Platform) and the `provider` routing block. DashScope 400s on
        /// these, so it stays false for Qwen.
        var includeOpenRouterRouting: Bool
        /// When true, send `temperature`. Claude 4.7+/5 reject it, so the native
        /// Anthropic builder omits it; here it gates OpenAI/OpenRouter/Qwen.
        var includeTemperature: Bool
        /// Human-readable provider name for logging/error copy.
        var providerLabel: String

        init(
            baseURL: String,
            extraHeaders: [String: String] = [:],
            maxTokensField: String = "max_tokens",
            includeOpenRouterRouting: Bool = false,
            includeTemperature: Bool = true,
            providerLabel: String = "AI"
        ) {
            self.baseURL = baseURL
            self.extraHeaders = extraHeaders
            self.maxTokensField = maxTokensField
            self.includeOpenRouterRouting = includeOpenRouterRouting
            self.includeTemperature = includeTemperature
            self.providerLabel = providerLabel
        }

        /// Qwen Cloud (Alibaba DashScope). Honors the `QwenBaseURL` override so the
        /// mainland host can be swapped in without a rebuild.
        static var qwen: Configuration {
            let configured = UserDefaults.standard.string(forKey: "QwenBaseURL")?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let base = (configured?.isEmpty == false ? configured! : "https://dashscope-intl.aliyuncs.com/compatible-mode/v1")
            return Configuration(baseURL: base, providerLabel: "Qwen")
        }

        /// OpenAI. Newer models (gpt-5.x) require `max_completion_tokens`.
        static var openAI: Configuration {
            Configuration(
                baseURL: "https://api.openai.com/v1",
                maxTokensField: "max_completion_tokens",
                providerLabel: "OpenAI"
            )
        }

        /// OpenRouter. Restores the routing headers + `provider` block that the
        /// Qwen build had to drop (DashScope rejected the unknown fields).
        static var openRouter: Configuration {
            Configuration(
                baseURL: "https://openrouter.ai/api/v1",
                includeOpenRouterRouting: true,
                providerLabel: "OpenRouter"
            )
        }
    }

    let configuration: Configuration

    init(configuration: Configuration = .qwen) {
        self.configuration = configuration
    }

    /// The resolved chat-completions endpoint for this configuration.
    private var chatCompletionsURL: URL {
        let base = configuration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: base + "/chat/completions")
            ?? URL(string: "https://dashscope-intl.aliyuncs.com/compatible-mode/v1/chat/completions")!
    }

    // MARK: - Streaming

    /// Stream directly from the configured provider with the user's API key.
    func streamMessage(
        messages: [Message],
        apiKey: String,
        model: String,
        maxTokens: Int,
        tools: [[String: Any]]? = nil
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        let request = try? buildRequest(messages: messages, apiKey: apiKey, model: model, maxTokens: maxTokens, stream: true, tools: tools)
        guard let req = request else {
            return AsyncThrowingStream { $0.finish(throwing: ServiceError.missingAPIKey) }
        }
        return streamWithRequest(req)
    }

    /// Stream via the slim G-Rump backend proxy. Bearer auth uses the shared
    /// APP_API_KEY (empty is allowed: the backend runs open in local dev).
    func streamMessageViaBackend(
        messages: [Message],
        model: String,
        maxTokens: Int,
        backendBaseURL: String,
        appAPIKey: String,
        tools: [[String: Any]]? = nil
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        guard let req = try? buildBackendRequest(messages: messages, model: model, maxTokens: maxTokens, stream: true, backendBaseURL: backendBaseURL, appAPIKey: appAPIKey, tools: tools) else {
            return AsyncThrowingStream { $0.finish(throwing: ServiceError.networkError) }
        }
        return streamWithRequest(req)
    }

    private func streamWithRequest(_ request: URLRequest) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let (bytes, response) = try await StreamingNetwork.session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw ServiceError.networkError
                    }

                    guard httpResponse.statusCode == 200 else {
                        var errorData = Data()
                        for try await byte in bytes { errorData.append(byte) }
                        let message = Self.parseAPIErrorMessage(errorData)
                        if let errorString = String(data: errorData, encoding: .utf8), message == nil {
                            GRumpLogger.ai.error("API Error: \(errorString)")
                        }
                        throw ServiceError.apiError(statusCode: httpResponse.statusCode, message: message)
                    }

                    try await SSELineParser.parseOpenAICompatible(bytes: bytes, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Request Builders

    func buildRequest(
        messages: [Message],
        apiKey: String,
        model: String,
        maxTokens: Int,
        stream: Bool,
        tools: [[String: Any]]? = nil
    ) throws -> URLRequest {
        guard !apiKey.isEmpty else { throw ServiceError.missingAPIKey }

        var request = URLRequest(url: chatCompletionsURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        for (field, value) in configuration.extraHeaders {
            request.addValue(value, forHTTPHeaderField: field)
        }
        // OpenRouter routing hints — off for DashScope, which rejects them.
        if configuration.includeOpenRouterRouting {
            request.addValue("https://www.g-rump.com", forHTTPHeaderField: "HTTP-Referer")
            request.addValue("G-Rump", forHTTPHeaderField: "X-Title")
            #if os(macOS)
            request.addValue("macos-native", forHTTPHeaderField: "X-Client-Platform")
            #else
            request.addValue("ios-native", forHTTPHeaderField: "X-Client-Platform")
            #endif
        }
        request.httpBody = try buildBody(messages: messages, model: model, maxTokens: maxTokens, stream: stream, tools: tools)
        return request
    }

    func buildBackendRequest(
        messages: [Message],
        model: String,
        maxTokens: Int,
        stream: Bool,
        backendBaseURL: String,
        appAPIKey: String,
        tools: [[String: Any]]? = nil
    ) throws -> URLRequest {
        let base = backendBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + "/api/v1/chat/completions") else { throw ServiceError.networkError }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        // Only attach the bearer when a key is set; the backend is open in local dev.
        let key = appAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty {
            request.addValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try buildBody(messages: messages, model: model, maxTokens: maxTokens, stream: stream, tools: tools)
        return request
    }

    private func buildBody(messages: [Message], model: String, maxTokens: Int, stream: Bool, tools: [[String: Any]]? = nil) throws -> Data {
        var apiMessages: [[String: Any]] = []
        for msg in messages {
            switch msg.role {
            case .system:
                apiMessages.append(["role": "system", "content": msg.content])
            case .user:
                apiMessages.append(["role": "user", "content": msg.content])
            case .assistant:
                var assistantMsg: [String: Any] = ["role": "assistant"]
                if !msg.content.isEmpty {
                    assistantMsg["content"] = msg.content
                }
                if let toolCalls = msg.toolCalls, !toolCalls.isEmpty {
                    assistantMsg["tool_calls"] = toolCalls.map {
                        [
                            "id": $0.id,
                            "type": "function",
                            "function": [
                                "name": $0.name,
                                "arguments": $0.arguments
                            ]
                        ]
                    }
                    if msg.content.isEmpty {
                        assistantMsg["content"] = NSNull()
                    }
                }
                apiMessages.append(assistantMsg)
            case .tool:
                apiMessages.append([
                    "role": "tool",
                    "tool_call_id": msg.toolCallId ?? "",
                    "content": msg.content
                ])
            }
        }

        var body: [String: Any] = [
            "model": model,
            "stream": stream,
            "messages": apiMessages,
            configuration.maxTokensField: maxTokens
        ]

        if configuration.includeTemperature {
            let temp = UserDefaults.standard.object(forKey: "ModelTemperature") as? Double ?? 0.0
            body["temperature"] = temp
        }

        body["tools"] = tools ?? ToolDefinitions.allTools
        body["tool_choice"] = "auto"
        if configuration.includeOpenRouterRouting {
            body["provider"] = [
                "sort": "price",
                "allow_fallbacks": true
            ]
        }

        return try JSONSerialization.data(withJSONObject: body, options: [])
    }

    // MARK: - Error parsing

    /// Shared with the native Anthropic/Google streams — both APIs use the
    /// same {"error": {"message": ...}} envelope on non-200 responses.
    static func parseAPIErrorMessage(_ data: Data) -> String? {
        struct ErrorPayload: Decodable {
            let error: ErrorDetail?
            struct ErrorDetail: Decodable {
                let message: String?
            }
        }
        guard let payload = try? JSONDecoder().decode(ErrorPayload.self, from: data),
              let message = payload.error?.message, !message.isEmpty else { return nil }
        return message
    }

    // MARK: - Errors

    enum ServiceError: Error, LocalizedError {
        case missingAPIKey
        case networkError
        case apiError(statusCode: Int, message: String? = nil)
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "Missing API key. Add your provider's API key in Settings."
            case .networkError:
                return "Network error. Please check your connection."
            case .apiError(let code, let message):
                if let message = message, !message.isEmpty {
                    return "AI provider error (HTTP \(code)): \(message)"
                }
                return "AI provider error (HTTP \(code)). Check your API key or model availability."
            case .invalidResponse:
                return "Received an invalid response from the AI provider."
            }
        }
    }
}

// MARK: - Dedicated Streaming URLSession (HTTP/2, connection pooling, keep-alive)

enum StreamingNetwork {
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 4
        config.timeoutIntervalForRequest = 180
        config.timeoutIntervalForResource = 300
        config.waitsForConnectivity = true
        config.httpShouldUsePipelining = true
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()
}

// MARK: - Shared SSE Line Parser

/// Reusable SSE parser that works with `bytes.lines` for all providers.
/// Replaces per-provider byte-by-byte parsing with efficient line-based parsing.
enum SSELineParser {

    /// Parse an OpenAI-compatible SSE stream (OpenAI, OpenRouter, Qwen, Ollama via /v1).
    /// Yields StreamEvents to the continuation. Returns when stream ends.
    static func parseOpenAICompatible(
        bytes: URLSession.AsyncBytes,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws {
        var sawEvent = false
        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            if payload == "[DONE]" { break }
            guard let jsonData = payload.data(using: .utf8) else { continue }
            guard let parsed = parseOpenAIChunk(jsonData) else { continue }

            if let toolCalls = parsed.toolCalls, !toolCalls.isEmpty {
                sawEvent = true
                continuation.yield(.toolCallDelta(toolCalls))
            }
            if let content = parsed.content, !content.isEmpty {
                sawEvent = true
                continuation.yield(.text(content))
            }
            if let reason = parsed.finishReason, !reason.isEmpty {
                sawEvent = true
                continuation.yield(.done(reason))
            }
        }
        if !sawEvent {
            throw OpenAICompatibleService.ServiceError.invalidResponse
        }
    }

    // MARK: - OpenAI chunk parser (JSONSerialization — faster than Codable)

    private static func parseOpenAIChunk(_ data: Data) -> ParsedChunk? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first else { return nil }
        let delta = first["delta"] as? [String: Any]
        let content = delta?["content"] as? String
        let finishReason = first["finish_reason"] as? String
        var toolCalls: [ToolCallDelta]?
        if let tcArr = delta?["tool_calls"] as? [[String: Any]], !tcArr.isEmpty {
            toolCalls = tcArr.compactMap { tcDict -> ToolCallDelta? in
                let fnDict = tcDict["function"] as? [String: Any]
                let fn: ToolCallFunctionDelta? = fnDict.flatMap { fd in
                    ToolCallFunctionDelta(name: fd["name"] as? String, arguments: fd["arguments"] as? String ?? "")
                }
                return ToolCallDelta(
                    index: tcDict["index"] as? Int,
                    id: tcDict["id"] as? String,
                    type: tcDict["type"] as? String,
                    function: fn
                )
            }
        }
        return ParsedChunk(content: content, toolCalls: toolCalls, finishReason: finishReason)
    }

    struct ParsedChunk {
        var content: String?
        var toolCalls: [ToolCallDelta]?
        var finishReason: String?
    }
}

// MARK: - Stream Event & Models

enum StreamEvent {
    case text(String)
    case toolCallDelta([ToolCallDelta])
    case done(String)
}

struct StreamChunk: Codable {
    let choices: [StreamChoice]?
}

struct StreamChoice: Codable {
    let delta: StreamDelta?
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case delta
        case finishReason = "finish_reason"
    }
}

struct StreamDelta: Codable {
    let role: String?
    let content: String?
    let toolCalls: [ToolCallDelta]?

    enum CodingKeys: String, CodingKey {
        case role, content
        case toolCalls = "tool_calls"
    }
}

struct ToolCallDelta: Codable {
    let index: Int?
    let id: String?
    let type: String?
    let function: ToolCallFunctionDelta?
}

struct ToolCallFunctionDelta: Codable {
    let name: String?
    let arguments: String?
}
