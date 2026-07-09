import XCTest
@testable import GRump

final class AnthropicRequestBuilderTests: XCTestCase {

    private let sampleTools: [[String: Any]] = [[
        "type": "function",
        "function": [
            "name": "read_file",
            "description": "Read a file from disk",
            "parameters": [
                "type": "object",
                "properties": ["path": ["type": "string"]],
                "required": ["path"]
            ]
        ]
    ]]

    // MARK: - Request / headers

    func testRequestHeadersAndURL() throws {
        let request = try MultiProviderAIService.buildAnthropicRequest(
            messages: [Message(role: .user, content: "hi")],
            model: "claude-opus-4-8",
            apiKey: "sk-ant-test",
            baseURL: "https://api.anthropic.com/v1",
            maxTokens: 128_000,
            tools: nil
        )
        XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "sk-ant-test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01",
                       "Must be the literal API version — the old builder sent a beta flag here")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"),
                     "Anthropic auth is x-api-key, not a bearer token")
    }

    // MARK: - Body shape

    private func body(messages: [Message], tools: [[String: Any]]? = nil,
                      maxTokens: Int = 64_000) -> [String: Any] {
        MultiProviderAIService.anthropicBody(
            messages: messages, model: "claude-opus-4-8",
            maxTokens: maxTokens, stream: true, tools: tools)
    }

    func testSystemGoesTopLevelNotInMessages() {
        let result = body(messages: [
            Message(role: .system, content: "Be terse."),
            Message(role: .user, content: "hi")
        ])
        XCTAssertEqual(result["system"] as? String, "Be terse.")
        let messages = result["messages"] as? [[String: Any]] ?? []
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?["role"] as? String, "user")
    }

    func testMaxTokensComesFromParameterAndNoTemperature() {
        let result = body(messages: [Message(role: .user, content: "hi")], maxTokens: 128_000)
        XCTAssertEqual(result["max_tokens"] as? Int, 128_000, "Was hardcoded 4096 in the old builder")
        XCTAssertNil(result["temperature"], "Claude 4.7+/5 reject temperature")
        XCTAssertNil(result["top_p"])
    }

    func testAssistantToolCallsBecomeToolUseBlocks() {
        let call = ToolCall(id: "toolu_01", name: "read_file", arguments: "{\"path\": \"/tmp/a\"}")
        let result = body(messages: [
            Message(role: .user, content: "read it"),
            Message(role: .assistant, content: "Reading.", toolCalls: [call])
        ])
        let messages = result["messages"] as? [[String: Any]] ?? []
        let assistant = messages.last
        XCTAssertEqual(assistant?["role"] as? String, "assistant")
        let blocks = assistant?["content"] as? [[String: Any]] ?? []
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks.first?["type"] as? String, "text")
        let toolUse = blocks.last
        XCTAssertEqual(toolUse?["type"] as? String, "tool_use")
        XCTAssertEqual(toolUse?["id"] as? String, "toolu_01")
        XCTAssertEqual(toolUse?["name"] as? String, "read_file")
        let input = toolUse?["input"] as? [String: Any]
        XCTAssertEqual(input?["path"] as? String, "/tmp/a", "Arguments must be the parsed object, not a string")
    }

    func testConsecutiveToolResultsMergeIntoOneUserMessage() {
        let calls = [
            ToolCall(id: "t1", name: "read_file", arguments: "{}"),
            ToolCall(id: "t2", name: "read_file", arguments: "{}")
        ]
        let result = body(messages: [
            Message(role: .user, content: "read both"),
            Message(role: .assistant, content: "", toolCalls: calls),
            Message(role: .tool, content: "contents A", toolCallId: "t1"),
            Message(role: .tool, content: "contents B", toolCallId: "t2")
        ])
        let messages = result["messages"] as? [[String: Any]] ?? []
        XCTAssertEqual(messages.count, 3, "user + assistant + ONE merged tool-result user message")
        let toolResultMsg = messages.last
        XCTAssertEqual(toolResultMsg?["role"] as? String, "user")
        let blocks = toolResultMsg?["content"] as? [[String: Any]] ?? []
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks.first?["type"] as? String, "tool_result")
        XCTAssertEqual(blocks.first?["tool_use_id"] as? String, "t1")
        XCTAssertEqual(blocks.last?["tool_use_id"] as? String, "t2")
    }

    func testToolOnlyAssistantTurnStillEmitsToolUse() {
        // Assistant turns with no text but tool calls must still carry blocks —
        // dropping them 400s the follow-up (unmatched tool_result).
        let call = ToolCall(id: "t9", name: "run_build", arguments: "{}")
        let result = body(messages: [
            Message(role: .user, content: "build"),
            Message(role: .assistant, content: "", toolCalls: [call]),
            Message(role: .tool, content: "ok", toolCallId: "t9")
        ])
        let messages = result["messages"] as? [[String: Any]] ?? []
        let assistant = messages[1]
        let blocks = assistant["content"] as? [[String: Any]] ?? []
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks.first?["type"] as? String, "tool_use")
    }

    func testToolsMapToInputSchema() {
        let result = body(messages: [Message(role: .user, content: "hi")], tools: sampleTools)
        let tools = result["tools"] as? [[String: Any]] ?? []
        XCTAssertEqual(tools.count, 1)
        XCTAssertEqual(tools.first?["name"] as? String, "read_file")
        XCTAssertNotNil(tools.first?["input_schema"], "OpenAI 'parameters' becomes Anthropic 'input_schema'")
        XCTAssertNil(tools.first?["parameters"])
        XCTAssertEqual((result["tool_choice"] as? [String: Any])?["type"] as? String, "auto")
    }

    func testMalformedArgumentsDegradeToEmptyObject() {
        let call = ToolCall(id: "t1", name: "read_file", arguments: "not json")
        let result = body(messages: [Message(role: .assistant, content: "", toolCalls: [call])])
        let messages = result["messages"] as? [[String: Any]] ?? []
        let blocks = messages.first?["content"] as? [[String: Any]] ?? []
        let input = blocks.first?["input"] as? [String: Any]
        XCTAssertNotNil(input)
        XCTAssertTrue(input?.isEmpty ?? false)
    }
}
