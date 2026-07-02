import Foundation

// MARK: - OpenRouter Service
// Base URL: https://openrouter.ai/api/v1

class OpenRouterService {
    // Compile-time constant URL, guaranteed valid.
    private let openRouterURL = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    // MARK: - Streaming (OpenRouter or platform backend)

    /// Stream from OpenRouter using a client API key (legacy).
    func streamMessage(
        messages: [Message],
        apiKey: String,
        model: String,
        tools: [[String: Any]]? = nil
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        let request = try? buildRequest(messages: messages, apiKey: apiKey, model: model, stream: true, tools: tools)
        guard let req = request else {
            return AsyncThrowingStream { $0.finish(throwing: ServiceError.missingAPIKey) }
        }
        return streamWithRequest(req)
    }

    /// Stream via G-Rump platform backend (single backend OpenRouter key; credits deducted server-side).
    func streamMessageViaBackend(
        messages: [Message],
        model: String,
        backendBaseURL: String,
        authToken: String,
        tools: [[String: Any]]? = nil
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        guard let req = try? buildBackendRequest(messages: messages, model: model, stream: true, backendBaseURL: backendBaseURL, authToken: authToken, tools: tools) else {
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

    // MARK: - Request Builders (OpenRouter + backend proxy)

    func buildRequest(
        messages: [Message],
        apiKey: String,
        model: String,
        stream: Bool,
        tools: [[String: Any]]? = nil
    ) throws -> URLRequest {
        guard !apiKey.isEmpty else { throw ServiceError.missingAPIKey }

        var request = URLRequest(url: openRouterURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("https://www.g-rump.com", forHTTPHeaderField: "HTTP-Referer")
        request.addValue("G-Rump", forHTTPHeaderField: "X-Title")
        #if os(macOS)
        request.addValue("macos-native", forHTTPHeaderField: "X-Client-Platform")
        #else
        request.addValue("ios-native", forHTTPHeaderField: "X-Client-Platform")
        #endif
        request.httpBody = try buildBody(messages: messages, model: model, stream: stream, tools: tools)
        return request
    }

    func buildBackendRequest(
        messages: [Message],
        model: String,
        stream: Bool,
        backendBaseURL: String,
        authToken: String,
        tools: [[String: Any]]? = nil
    ) throws -> URLRequest {
        let base = backendBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + "/api/v1/chat/completions") else { throw ServiceError.networkError }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.addValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try buildBody(messages: messages, model: model, stream: stream, tools: tools)
        return request
    }

    private func buildBody(messages: [Message], model: String, stream: Bool, tools: [[String: Any]]? = nil) throws -> Data {
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

        let aiModel = AIModel(rawValue: model)
        let maxTokens = aiModel?.maxOutput ?? 16384

        let temp = UserDefaults.standard.object(forKey: "ModelTemperature") as? Double ?? 0.0
        var body: [String: Any] = [
            "model": model,
            "stream": stream,
            "messages": apiMessages,
            "max_tokens": maxTokens,
            "temperature": temp
        ]

        body["tools"] = tools ?? ToolDefinitions.allTools
        body["tool_choice"] = "auto"
        body["provider"] = [
            "sort": "price",
            "allow_fallbacks": true
        ]

        return try JSONSerialization.data(withJSONObject: body, options: [])
    }

    // MARK: - Minimal stream parse (now delegated to shared SSELineParser)

    // MARK: - Error parsing

    private static func parseAPIErrorMessage(_ data: Data) -> String? {
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
                return "Missing API key. Please set your OpenRouter API key in Settings."
            case .networkError:
                return "Network error. Please check your connection."
            case .apiError(let code, let message):
                if let message = message, !message.isEmpty {
                    return "OpenRouter API error (HTTP \(code)): \(message)"
                }
                return "OpenRouter API error (HTTP \(code)). Check your API key or model availability."
            case .invalidResponse:
                return "Received an invalid response from OpenRouter."
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

    /// Parse an OpenAI-compatible SSE stream (OpenAI, OpenRouter, Ollama via /v1).
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
            throw OpenRouterService.ServiceError.invalidResponse
        }
    }

    /// Parse an Anthropic SSE stream (event: / data: format).
    static func parseAnthropic(
        bytes: URLSession.AsyncBytes,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws {
        for try await line in bytes.lines {
            if line.hasPrefix("event: error") {
                throw AIServiceError.apiError(500)
            }
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            guard let jsonData = payload.data(using: .utf8) else { continue }
            guard let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else { continue }

            let eventType = json["type"] as? String ?? ""

            if eventType == "content_block_delta" {
                if let delta = json["delta"] as? [String: Any] {
                    if let text = delta["text"] as? String, !text.isEmpty {
                        continuation.yield(.text(text))
                    }
                }
            } else if eventType == "message_delta" {
                if let delta = json["delta"] as? [String: Any],
                   let stopReason = delta["stop_reason"] as? String {
                    continuation.yield(.done(stopReason))
                }
            } else if eventType == "content_block_start" {
                if let contentBlock = json["content_block"] as? [String: Any],
                   let blockType = contentBlock["type"] as? String, blockType == "tool_use" {
                    let toolDelta = ToolCallDelta(
                        index: json["index"] as? Int,
                        id: contentBlock["id"] as? String,
                        type: "function",
                        function: ToolCallFunctionDelta(
                            name: contentBlock["name"] as? String,
                            arguments: ""
                        )
                    )
                    continuation.yield(.toolCallDelta([toolDelta]))
                }
            } else if eventType == "message_stop" {
                return
            }
        }
    }

    /// Parse a native Ollama NDJSON stream (/api/chat).
    static func parseOllamaNDJSON(
        bytes: URLSession.AsyncBytes,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws {
        for try await line in bytes.lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard let data = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            if let message = json["message"] as? [String: Any],
               let content = message["content"] as? String, !content.isEmpty {
                continuation.yield(.text(content))
            } else if let response = json["response"] as? String, !response.isEmpty {
                continuation.yield(.text(response))
            }

            if let done = json["done"] as? Bool, done {
                continuation.yield(.done("stop"))
                return
            }
        }
    }

    /// Parse a Google Gemini SSE stream (streamGenerateContent).
    static func parseGoogleSSE(
        bytes: URLSession.AsyncBytes,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws {
        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            guard let jsonData = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else { continue }

            // Gemini wraps content in candidates[0].content.parts[]
            guard let candidates = json["candidates"] as? [[String: Any]],
                  let first = candidates.first,
                  let content = first["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]] else {
                // Check for finish reason at top level
                if let candidates = json["candidates"] as? [[String: Any]],
                   let first = candidates.first,
                   let finishReason = first["finishReason"] as? String {
                    continuation.yield(.done(finishReason.lowercased()))
                }
                continue
            }

            for part in parts {
                if let text = part["text"] as? String, !text.isEmpty {
                    continuation.yield(.text(text))
                }
                // Handle function calls from Gemini
                if let functionCall = part["functionCall"] as? [String: Any],
                   let name = functionCall["name"] as? String {
                    let argsDict = functionCall["args"] as? [String: Any] ?? [:]
                    let argsJSON = (try? JSONSerialization.data(withJSONObject: argsDict))
                        .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                    let toolDelta = ToolCallDelta(
                        index: 0,
                        id: UUID().uuidString,
                        type: "function",
                        function: ToolCallFunctionDelta(name: name, arguments: argsJSON)
                    )
                    continuation.yield(.toolCallDelta([toolDelta]))
                }
            }

            // Check finish reason
            if let finishReason = first["finishReason"] as? String,
               finishReason != "STOP" || finishReason == "STOP" {
                let reason = finishReason == "STOP" ? "stop" : finishReason.lowercased()
                continuation.yield(.done(reason))
            }
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
