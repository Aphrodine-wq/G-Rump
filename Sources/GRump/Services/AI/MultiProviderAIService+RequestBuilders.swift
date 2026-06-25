import Foundation

// MARK: - Request Builders Extension
//
// Contains all provider-specific HTTP request builders and their
// associated Codable request/response models.
// Extracted from MultiProviderAIService.swift for maintainability.

extension MultiProviderAIService {

    // MARK: - OpenAI Request Builder

    nonisolated func buildOpenAIRequest(
        messages: [Message],
        model: String,
        apiKey: String,
        baseURL: String,
        tools: [[String: Any]]?,
        stream: Bool
    ) throws -> URLRequest {
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody = OpenAIRequest(
            model: model,
            messages: messages.map { openAIMessage(from: $0) },
            tools: tools,
            stream: stream,
            temperature: 0.7,
            maxTokens: nil
        )

        request.httpBody = try JSONEncoder().encode(requestBody)
        return request
    }

    // MARK: - Anthropic Request Builder

    nonisolated func buildAnthropicRequest(
        messages: [Message],
        model: String,
        apiKey: String,
        baseURL: String,
        tools: [[String: Any]]?,
        stream: Bool
    ) throws -> URLRequest {
        guard let url = URL(string: "\(baseURL)/messages") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("anthropic-dangerous-direct-browser-access", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody = AnthropicRequest(
            model: model,
            messages: messages.map { anthropicMessage(from: $0) },
            tools: tools?.map { anthropicTool(from: $0) },
            maxTokens: 4096,
            stream: stream
        )

        request.httpBody = try JSONEncoder().encode(requestBody)
        return request
    }

    // MARK: - Ollama Request Builder

    nonisolated func buildOllamaRequest(
        messages: [Message],
        model: String,
        baseURL: String,
        tools: [[String: Any]]?,
        stream: Bool
    ) throws -> URLRequest {
        // Native Ollama API uses /api/chat, not /v1/chat
        // Strip /v1 suffix if present since we're using native API
        let cleanBaseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .replacingOccurrences(of: "/v1", with: "")
        guard let url = URL(string: "\(cleanBaseURL)/api/chat") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody = OllamaRequest(
            model: model,
            messages: messages.map { ollamaMessage(from: $0) },
            stream: stream,
            options: OllamaOptions(temperature: 0.7, numPredict: 2048)
        )

        request.httpBody = try JSONEncoder().encode(requestBody)
        return request
    }

    // MARK: - Google Gemini Request Builder

    nonisolated func buildGoogleRequest(
        messages: [Message],
        model: String,
        apiKey: String,
        baseURL: String,
        tools: [[String: Any]]?,
        maxOutputTokens: Int
    ) throws -> URLRequest {
        let cleanBase = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(cleanBase)/models/\(model):streamGenerateContent?alt=sse&key=\(apiKey)") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Convert messages to Gemini contents format
        var contents: [[String: Any]] = []
        var systemInstruction: [String: Any]?

        for message in messages {
            if message.role == .system {
                systemInstruction = ["parts": [["text": message.content]]]
                continue
            }
            let role = message.role == .assistant ? "model" : "user"
            contents.append([
                "role": role,
                "parts": [["text": message.content]]
            ])
        }

        var body: [String: Any] = [
            "contents": contents,
            "generationConfig": [
                "temperature": 0.7,
                "maxOutputTokens": maxOutputTokens
            ]
        ]
        if let sys = systemInstruction {
            body["systemInstruction"] = sys
        }

        // Convert tools to Gemini function declarations
        if let tools = tools, !tools.isEmpty {
            var functionDeclarations: [[String: Any]] = []
            for tool in tools {
                if let function = tool["function"] as? [String: Any] {
                    functionDeclarations.append(function)
                }
            }
            if !functionDeclarations.isEmpty {
                body["tools"] = [["functionDeclarations": functionDeclarations]]
            }
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    // MARK: - Message Converters

    nonisolated func openAIMessage(from message: Message) -> OpenAIMessage {
        return OpenAIMessage(
            role: message.role.rawValue,
            content: message.content,
            toolCalls: message.toolCalls?.map { toolCall in
                OpenAIMessage.ToolCallDTO(
                    id: toolCall.id,
                    type: "function",
                    function: OpenAIMessage.ToolCallDTO.FunctionCall(
                        name: toolCall.name,
                        arguments: toolCall.arguments
                    )
                )
            }
        )
    }

    nonisolated func anthropicMessage(from message: Message) -> AnthropicMessage {
        if message.role == .tool {
            return AnthropicMessage(
                role: "user",
                content: [
                    AnthropicMessage.Content(
                        type: "tool_result",
                        text: nil,
                        toolUseId: message.toolCallId ?? "",
                        toolResult: message.content
                    )
                ]
            )
        } else {
            return AnthropicMessage(
                role: message.role.rawValue,
                content: [AnthropicMessage.Content(type: "text", text: message.content, toolUseId: nil, toolResult: nil)]
            )
        }
    }

    nonisolated func ollamaMessage(from message: Message) -> OllamaMessage {
        return OllamaMessage(
            role: message.role == .tool ? "user" : message.role.rawValue,
            content: message.content
        )
    }

    nonisolated func anthropicTool(from tool: [String: Any]) -> AnthropicTool {
        let fn = tool["function"] as? [String: Any] ?? [:]
        return AnthropicTool(
            name: fn["name"] as? String ?? "",
            description: fn["description"] as? String ?? "",
            inputSchema: fn["parameters"] as? [String: Any] ?? [:]
        )
    }
}

// MARK: - Request/Response Models

struct OpenAIRequest: Encodable {
    let model: String
    let messages: [OpenAIMessage]
    let tools: [[String: Any]]?
    let stream: Bool
    let temperature: Double
    let maxTokens: Int?

    enum CodingKeys: String, CodingKey {
        case model, messages, tools, stream, temperature
        case maxTokens = "max_tokens"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(messages, forKey: .messages)
        try container.encode(stream, forKey: .stream)
        try container.encode(temperature, forKey: .temperature)
        try container.encodeIfPresent(maxTokens, forKey: .maxTokens)
        if let tools = tools, let data = try? JSONSerialization.data(withJSONObject: tools),
           let jsonArray = try? JSONDecoder().decode([JSONValue].self, from: data) {
            try container.encode(jsonArray, forKey: .tools)
        }
    }
}

/// A generic JSON value for encoding arbitrary JSON structures.
enum JSONValue: Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) { self = .string(value) } else if let value = try? container.decode(Double.self) { self = .number(value) } else if let value = try? container.decode(Bool.self) { self = .bool(value) } else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) } else if let value = try? container.decode([JSONValue].self) { self = .array(value) } else if container.decodeNil() { self = .null } else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value") }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

struct OpenAIMessage: Codable {
    let role: String
    let content: String
    let toolCalls: [ToolCallDTO]?

    struct ToolCallDTO: Codable {
        let id: String
        let type: String
        let function: FunctionCall

        struct FunctionCall: Codable {
            let name: String
            let arguments: String
        }
    }
}

struct OpenAIStreamResponse: Codable {
    let choices: [Choice]

    struct Choice: Codable {
        let delta: Delta
        let finishReason: String?

        struct Delta: Codable {
            let content: String?
            let toolCalls: [StreamToolCall]?

            enum CodingKeys: String, CodingKey {
                case content
                case toolCalls = "tool_calls"
            }
        }
    }

    struct StreamToolCall: Codable {
        let id: String?
        let type: String?
        let function: StreamFunction?

        struct StreamFunction: Codable {
            let name: String?
            let arguments: String?
        }
    }
}

struct AnthropicRequest: Encodable {
    let model: String
    let messages: [AnthropicMessage]
    let tools: [AnthropicTool]?
    let maxTokens: Int
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model, messages, tools, stream
        case maxTokens = "max_tokens"
    }
}

struct AnthropicMessage: Codable {
    let role: String
    let content: [Content]

    struct Content: Codable {
        let type: String
        let text: String?
        let toolUseId: String?
        let toolResult: String?

        enum CodingKeys: String, CodingKey {
            case type, text
            case toolUseId = "tool_use_id"
            case toolResult = "content"
        }
    }
}

struct AnthropicTool: Encodable {
    let name: String
    let description: String
    let inputSchema: [String: Any]

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        if let data = try? JSONSerialization.data(withJSONObject: inputSchema),
           let jsonObj = try? JSONDecoder().decode([String: JSONValue].self, from: data) {
            try container.encode(jsonObj, forKey: .inputSchema)
        }
    }

    enum CodingKeys: String, CodingKey {
        case name, description, inputSchema = "input_schema"
    }
}

struct AnthropicStreamResponse: Codable {
    let type: String
    let delta: Delta?

    struct Delta: Codable {
        let text: String?
        let toolUse: [ToolUse]?
    }

    struct ToolUse: Codable {
        let id: String?
        let name: String?
        let input: ToolInput?
    }

    struct ToolInput: Codable {
        func jsonString() -> String {
            if let data = try? JSONEncoder().encode(self),
               let string = String(data: data, encoding: .utf8) {
                return string
            }
            return "{}"
        }
    }
}

struct OllamaRequest: Codable {
    let model: String
    let messages: [OllamaMessage]
    let stream: Bool
    let options: OllamaOptions
}

struct OllamaMessage: Codable {
    let role: String
    let content: String
}

struct OllamaOptions: Codable {
    let temperature: Double
    let numPredict: Int

    enum CodingKeys: String, CodingKey {
        case temperature
        case numPredict = "num_predict"
    }
}

struct OllamaStreamResponse: Codable {
    let response: String
    let done: Bool
}
