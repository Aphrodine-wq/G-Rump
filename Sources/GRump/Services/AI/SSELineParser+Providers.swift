import Foundation

// MARK: - Native Provider SSE Parsers (Anthropic, Google)
//
// Chunk handling lives in pure static functions over already-decoded JSON so
// tests can drive them without a network. The byte loops are thin wrappers.
//
// Both parsers normalize stop reasons to the agent loop's contract
// (ChatViewModel+AgentLoop): "tool_calls" keeps the loop driving tool
// execution; "stop" ends the turn. Anthropic's tool_use → "tool_calls" and
// end_turn → "stop"; Gemini reports STOP even on function-call turns, so the
// parser tracks whether the turn produced calls and reports accordingly.
// The Anthropic parser also accumulates tool ARGUMENTS from
// input_json_delta events — dropping those leaves every tool call empty.

extension SSELineParser {

    // MARK: - Anthropic

    /// Maps Anthropic content-block indexes (which count text blocks too) to
    /// the sequential tool ordinals the agent loop buffers by.
    struct AnthropicStreamState {
        var blockOrdinals: [Int: Int] = [:]
        var nextToolOrdinal = 0
    }

    /// Parse one Anthropic SSE event (already JSON-decoded). Pure — all
    /// stream state is passed explicitly.
    static func parseAnthropicEvent(
        _ json: [String: Any],
        state: inout AnthropicStreamState
    ) -> [StreamEvent] {
        switch json["type"] as? String ?? "" {
        case "content_block_start":
            guard let block = json["content_block"] as? [String: Any],
                  block["type"] as? String == "tool_use",
                  let blockIndex = json["index"] as? Int else { return [] }
            let ordinal = state.nextToolOrdinal
            state.nextToolOrdinal += 1
            state.blockOrdinals[blockIndex] = ordinal
            return [.toolCallDelta([ToolCallDelta(
                index: ordinal,
                id: block["id"] as? String,
                type: "function",
                function: ToolCallFunctionDelta(name: block["name"] as? String, arguments: "")
            )])]

        case "content_block_delta":
            guard let delta = json["delta"] as? [String: Any] else { return [] }
            switch delta["type"] as? String ?? "" {
            case "text_delta":
                guard let text = delta["text"] as? String, !text.isEmpty else { return [] }
                return [.text(text)]
            case "input_json_delta":
                // Tool ARGUMENTS stream here — the fix for the old parser
                // that only ever captured the tool name.
                guard let partial = delta["partial_json"] as? String, !partial.isEmpty,
                      let blockIndex = json["index"] as? Int,
                      let ordinal = state.blockOrdinals[blockIndex] else { return [] }
                return [.toolCallDelta([ToolCallDelta(
                    index: ordinal,
                    id: nil,
                    type: nil,
                    function: ToolCallFunctionDelta(name: nil, arguments: partial)
                )])]
            default:
                return []
            }

        case "message_delta":
            guard let delta = json["delta"] as? [String: Any],
                  let stopReason = delta["stop_reason"] as? String else { return [] }
            return [.done(normalizedAnthropicStopReason(stopReason))]

        default:
            return []
        }
    }

    static func normalizedAnthropicStopReason(_ reason: String) -> String {
        switch reason {
        case "tool_use": return "tool_calls"
        case "end_turn", "stop_sequence": return "stop"
        default: return reason.lowercased()
        }
    }

    /// Parse an Anthropic SSE stream (event:/data: format).
    static func parseAnthropic(
        bytes: URLSession.AsyncBytes,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws {
        var state = AnthropicStreamState()
        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            guard let jsonData = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else { continue }

            let eventType = json["type"] as? String ?? ""
            if eventType == "error" {
                let message = (json["error"] as? [String: Any])?["message"] as? String
                throw OpenAICompatibleService.ServiceError.apiError(statusCode: 500, message: message)
            }
            if eventType == "message_stop" { return }

            for event in parseAnthropicEvent(json, state: &state) {
                continuation.yield(event)
            }
        }
    }

    // MARK: - Google (Gemini)

    struct GoogleStreamState {
        var nextToolOrdinal = 0
        var sawFunctionCall = false
    }

    /// Parse one Gemini streamGenerateContent chunk (already JSON-decoded).
    static func parseGoogleChunk(
        _ json: [String: Any],
        state: inout GoogleStreamState
    ) -> [StreamEvent] {
        guard let candidate = (json["candidates"] as? [[String: Any]])?.first else { return [] }
        var events: [StreamEvent] = []

        let parts = (candidate["content"] as? [String: Any])?["parts"] as? [[String: Any]] ?? []
        for part in parts {
            if let text = part["text"] as? String, !text.isEmpty {
                events.append(.text(text))
            }
            if let functionCall = part["functionCall"] as? [String: Any],
               let name = functionCall["name"] as? String {
                let args = functionCall["args"] as? [String: Any] ?? [:]
                let argsJSON = (try? JSONSerialization.data(withJSONObject: args))
                    .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                let ordinal = state.nextToolOrdinal
                state.nextToolOrdinal += 1
                state.sawFunctionCall = true
                // Gemini has no call ids — synthesize stable ones so tool
                // results can round-trip through functionResponse.
                events.append(.toolCallDelta([ToolCallDelta(
                    index: ordinal,
                    id: "gemini_call_\(ordinal)_\(UUID().uuidString.prefix(8))",
                    type: "function",
                    function: ToolCallFunctionDelta(name: name, arguments: argsJSON)
                )]))
            }
        }

        if let finishReason = candidate["finishReason"] as? String, !finishReason.isEmpty {
            // Gemini says STOP even when the turn is a function call — the
            // agent loop would end the turn without running the tools.
            if finishReason == "STOP" {
                events.append(.done(state.sawFunctionCall ? "tool_calls" : "stop"))
            } else {
                events.append(.done(finishReason.lowercased()))
            }
        }
        return events
    }

    /// Parse a Gemini streamGenerateContent SSE stream.
    static func parseGoogle(
        bytes: URLSession.AsyncBytes,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws {
        var state = GoogleStreamState()
        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            guard let jsonData = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else { continue }

            if let error = json["error"] as? [String: Any] {
                let code = error["code"] as? Int ?? 500
                let message = error["message"] as? String
                throw OpenAICompatibleService.ServiceError.apiError(statusCode: code, message: message)
            }

            for event in parseGoogleChunk(json, state: &state) {
                continuation.yield(event)
            }
        }
    }
}
