import Foundation

// MARK: - Native Request Builders (Anthropic, Google)
//
// Body builders are pure static functions returning dictionaries so tests can
// assert the exact wire shape. Notable wire rules, each of which was broken in
// the pre-Qwen incarnation of this file:
//   - anthropic-version must be the literal API version "2023-06-01".
//   - Anthropic takes `system` top-level; a "system" role inside messages[]
//     is rejected.
//   - Anthropic assistant turns must carry tool_use blocks for every tool
//     call, and each tool result rides a tool_result block in a user message
//     (consecutive results merged into ONE user message).
//   - max_tokens comes from the selected model — never hardcoded.
//   - No temperature: Claude 4.7+/5 models reject it.
//   - Gemini tool results ride functionResponse parts (role "user"), with the
//     function NAME resolved from the assistant turn that issued the call.

extension MultiProviderAIService {

    // MARK: - Anthropic

    nonisolated static func buildAnthropicRequest(
        messages: [Message],
        model: String,
        apiKey: String,
        baseURL: String,
        maxTokens: Int,
        tools: [[String: Any]]?
    ) throws -> URLRequest {
        let base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + "/messages") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let cachingEnabled = UserDefaults.standard.object(forKey: "AnthropicPromptCachingEnabled") as? Bool ?? true
        let body = anthropicBody(messages: messages, model: model, maxTokens: maxTokens,
                                 stream: true, tools: tools, enableCaching: cachingEnabled)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    nonisolated static func anthropicBody(
        messages: [Message],
        model: String,
        maxTokens: Int,
        stream: Bool,
        tools: [[String: Any]]?,
        enableCaching: Bool = false
    ) -> [String: Any] {
        var apiMessages: [[String: Any]] = []
        var systemParts: [String] = []
        // Consecutive tool results collapse into one user message.
        var pendingToolResults: [[String: Any]] = []

        func flushToolResults() {
            guard !pendingToolResults.isEmpty else { return }
            apiMessages.append(["role": "user", "content": pendingToolResults])
            pendingToolResults = []
        }

        for message in messages {
            switch message.role {
            case .system:
                systemParts.append(message.content)

            case .user:
                flushToolResults()
                apiMessages.append([
                    "role": "user",
                    "content": [["type": "text", "text": message.content]]
                ])

            case .assistant:
                flushToolResults()
                var blocks: [[String: Any]] = []
                // Thinking blocks replay FIRST and unchanged — Claude Fable 5
                // signs every block, and stripping or reordering them can
                // reject the tool-use continuation.
                for thinking in message.thinkingBlocks ?? [] {
                    if let data = thinking.data {
                        blocks.append(["type": "redacted_thinking", "data": data])
                    } else if !thinking.signature.isEmpty {
                        blocks.append(["type": "thinking", "thinking": thinking.thinking, "signature": thinking.signature])
                    }
                }
                if !message.content.isEmpty {
                    blocks.append(["type": "text", "text": message.content])
                }
                for call in message.toolCalls ?? [] {
                    blocks.append([
                        "type": "tool_use",
                        "id": call.id,
                        "name": call.name,
                        "input": parsedJSONObject(call.arguments)
                    ])
                }
                // Anthropic rejects an empty content array.
                if !blocks.isEmpty {
                    apiMessages.append(["role": "assistant", "content": blocks])
                }

            case .tool:
                pendingToolResults.append([
                    "type": "tool_result",
                    "tool_use_id": message.toolCallId ?? "",
                    "content": message.content
                ])
            }
        }
        flushToolResults()

        // Prompt caching: three ephemeral breakpoints — system, last tool,
        // and an advancing message breakpoint, so long agentic runs get
        // incremental cache reads over the prior transcript. The breakpoint
        // goes on the SECOND-to-last message: the final position can hold a
        // volatile trailing note (e.g. the tracked-plan snapshot) that changes
        // between turns and would otherwise kill every transcript cache hit.
        if enableCaching, !apiMessages.isEmpty {
            let markIdx = apiMessages.count >= 2 ? apiMessages.count - 2 : apiMessages.count - 1
            if var content = apiMessages[markIdx]["content"] as? [[String: Any]], !content.isEmpty {
                content[content.count - 1]["cache_control"] = ["type": "ephemeral"]
                apiMessages[markIdx]["content"] = content
            }
        }

        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "stream": stream,
            "messages": apiMessages
        ]
        // Adaptive thinking is the recommended mode for coding/agentic work.
        // Opus 4.8 runs with thinking OFF when the param is omitted; Fable 5
        // accepts an explicit adaptive (thinking is always on there). Models
        // outside the gate (Haiku, older) reject the parameter.
        if anthropicSupportsAdaptiveThinking(model) {
            body["thinking"] = ["type": "adaptive"]
        }
        let system = systemParts.joined(separator: "\n\n")
        if !system.isEmpty {
            if enableCaching {
                body["system"] = [["type": "text", "text": system, "cache_control": ["type": "ephemeral"]]]
            } else {
                body["system"] = system
            }
        }
        if let tools = tools, !tools.isEmpty {
            var mapped = tools.compactMap { anthropicTool(from: $0) }
            if enableCaching, !mapped.isEmpty {
                mapped[mapped.count - 1]["cache_control"] = ["type": "ephemeral"]
            }
            body["tools"] = mapped
            body["tool_choice"] = ["type": "auto"]
        }
        return body
    }

    /// Models that accept `thinking: {type: "adaptive"}`. Explicit allowlist —
    /// unknown or older models (Haiku 4.5, Sonnet 4.5, Opus 4.5 and earlier)
    /// reject the parameter with a 400, so the default is to omit it.
    nonisolated static func anthropicSupportsAdaptiveThinking(_ model: String) -> Bool {
        let id = model.lowercased()
        if id.contains("fable") || id.contains("mythos") { return true }
        if id.contains("opus-4-6") || id.contains("opus-4-7") || id.contains("opus-4-8") { return true }
        if id.contains("sonnet-4-6") || id.contains("sonnet-5") { return true }
        return false
    }

    /// OpenAI-style {type: function, function: {name, description, parameters}}
    /// → Anthropic {name, description, input_schema}.
    nonisolated static func anthropicTool(from tool: [String: Any]) -> [String: Any]? {
        let function = tool["function"] as? [String: Any] ?? tool
        guard let name = function["name"] as? String, !name.isEmpty else { return nil }
        return [
            "name": name,
            "description": function["description"] as? String ?? "",
            "input_schema": function["parameters"] as? [String: Any] ?? ["type": "object"]
        ]
    }

    // MARK: - Google (Gemini)

    nonisolated static func buildGoogleRequest(
        messages: [Message],
        model: String,
        apiKey: String,
        baseURL: String,
        maxOutputTokens: Int,
        tools: [[String: Any]]?
    ) throws -> URLRequest {
        let base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/models/\(model):streamGenerateContent?alt=sse&key=\(apiKey)") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = googleBody(messages: messages, maxOutputTokens: maxOutputTokens, tools: tools)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    nonisolated static func googleBody(
        messages: [Message],
        maxOutputTokens: Int,
        tools: [[String: Any]]?
    ) -> [String: Any] {
        var contents: [[String: Any]] = []
        var systemParts: [String] = []
        var pendingFunctionResponses: [[String: Any]] = []
        // tool_call_id → function name, resolved from prior assistant turns.
        var callNames: [String: String] = [:]

        func flushFunctionResponses() {
            guard !pendingFunctionResponses.isEmpty else { return }
            contents.append(["role": "user", "parts": pendingFunctionResponses])
            pendingFunctionResponses = []
        }

        for message in messages {
            switch message.role {
            case .system:
                systemParts.append(message.content)

            case .user:
                flushFunctionResponses()
                contents.append(["role": "user", "parts": [["text": message.content]]])

            case .assistant:
                flushFunctionResponses()
                var parts: [[String: Any]] = []
                if !message.content.isEmpty {
                    parts.append(["text": message.content])
                }
                for call in message.toolCalls ?? [] {
                    callNames[call.id] = call.name
                    parts.append([
                        "functionCall": [
                            "name": call.name,
                            "args": parsedJSONObject(call.arguments)
                        ]
                    ])
                }
                if !parts.isEmpty {
                    contents.append(["role": "model", "parts": parts])
                }

            case .tool:
                let name = message.toolCallId.flatMap { callNames[$0] } ?? "unknown"
                pendingFunctionResponses.append([
                    "functionResponse": [
                        "name": name,
                        "response": ["result": message.content]
                    ]
                ])
            }
        }
        flushFunctionResponses()

        var body: [String: Any] = [
            "contents": contents,
            "generationConfig": ["maxOutputTokens": maxOutputTokens]
        ]
        let system = systemParts.joined(separator: "\n\n")
        if !system.isEmpty {
            body["systemInstruction"] = ["parts": [["text": system]]]
        }
        if let tools = tools, !tools.isEmpty {
            let declarations = tools.compactMap { googleFunctionDeclaration(from: $0) }
            if !declarations.isEmpty {
                body["tools"] = [["functionDeclarations": declarations]]
            }
        }
        return body
    }

    /// OpenAI-style function def → Gemini functionDeclaration, with the
    /// parameters schema stripped of JSON-Schema keywords Gemini rejects.
    nonisolated static func googleFunctionDeclaration(from tool: [String: Any]) -> [String: Any]? {
        let function = tool["function"] as? [String: Any] ?? tool
        guard let name = function["name"] as? String, !name.isEmpty else { return nil }
        var declaration: [String: Any] = [
            "name": name,
            "description": function["description"] as? String ?? ""
        ]
        if let parameters = function["parameters"] as? [String: Any] {
            declaration["parameters"] = sanitizeGoogleSchema(parameters)
        }
        return declaration
    }

    /// Gemini's OpenAPI-subset schema rejects several JSON-Schema keywords.
    /// Over-stripping is safe (the schema just gets more permissive);
    /// under-stripping 400s the whole request.
    nonisolated static func sanitizeGoogleSchema(_ schema: [String: Any]) -> [String: Any] {
        let rejected: Set<String> = [
            "$schema", "additionalProperties", "default", "examples", "pattern",
            "format", "minLength", "maxLength", "minimum", "maximum",
            "exclusiveMinimum", "exclusiveMaximum", "minItems", "maxItems"
        ]
        var cleaned: [String: Any] = [:]
        for (key, value) in schema where !rejected.contains(key) {
            if let nested = value as? [String: Any] {
                cleaned[key] = sanitizeGoogleSchema(nested)
            } else if let array = value as? [[String: Any]] {
                cleaned[key] = array.map { sanitizeGoogleSchema($0) }
            } else {
                cleaned[key] = value
            }
        }
        return cleaned
    }

    // MARK: - Helpers

    /// Tool-call arguments arrive as a JSON string; both native APIs want the
    /// parsed object. Malformed args degrade to an empty object.
    nonisolated static func parsedJSONObject(_ jsonString: String) -> [String: Any] {
        guard let data = jsonString.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return object
    }
}
