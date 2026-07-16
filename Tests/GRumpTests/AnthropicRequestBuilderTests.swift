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

    // MARK: - Prompt caching

    private func cachedBody(messages: [Message], tools: [[String: Any]]? = nil) -> [String: Any] {
        MultiProviderAIService.anthropicBody(
            messages: messages, model: "claude-opus-4-8",
            maxTokens: 64_000, stream: true, tools: tools, enableCaching: true)
    }

    func testCachingSystemBecomesBlockArrayWithCacheControl() {
        let result = cachedBody(messages: [
            Message(role: .system, content: "Be terse."),
            Message(role: .user, content: "hi")
        ])
        let system = result["system"] as? [[String: Any]]
        XCTAssertNotNil(system, "cached system must be a block array, not a string")
        XCTAssertEqual(system?.first?["text"] as? String, "Be terse.")
        XCTAssertEqual((system?.first?["cache_control"] as? [String: String])?["type"], "ephemeral")
    }

    func testCachingMarksOnlyLastTool() {
        let twoTools = sampleTools + [[
            "type": "function",
            "function": ["name": "write_file", "description": "w", "parameters": ["type": "object"]] as [String: Any]
        ]]
        let result = cachedBody(messages: [Message(role: .user, content: "hi")], tools: twoTools)
        let tools = result["tools"] as? [[String: Any]] ?? []
        XCTAssertEqual(tools.count, 2)
        XCTAssertNil(tools.first?["cache_control"], "only the LAST tool carries the breakpoint")
        XCTAssertEqual((tools.last?["cache_control"] as? [String: String])?["type"], "ephemeral")
    }

    func testCachingMarksSecondToLastMessage() {
        // The final slot can hold a volatile trailing note (plan snapshot);
        // the breakpoint sits one message earlier so transcript hits survive.
        let result = cachedBody(messages: [
            Message(role: .user, content: "first"),
            Message(role: .user, content: "second"),
            Message(role: .user, content: "volatile trailing note")
        ])
        let messages = result["messages"] as? [[String: Any]] ?? []
        XCTAssertEqual(messages.count, 3)
        let markedBlocks = messages[1]["content"] as? [[String: Any]] ?? []
        XCTAssertEqual((markedBlocks.last?["cache_control"] as? [String: String])?["type"], "ephemeral")
        let lastBlocks = messages.last?["content"] as? [[String: Any]] ?? []
        XCTAssertNil(lastBlocks.last?["cache_control"], "the volatile final message must carry no breakpoint")
        let firstBlocks = messages.first?["content"] as? [[String: Any]] ?? []
        XCTAssertNil(firstBlocks.last?["cache_control"])
    }

    func testCachingSingleMessageStillMarked() {
        let result = cachedBody(messages: [Message(role: .user, content: "only")])
        let messages = result["messages"] as? [[String: Any]] ?? []
        let blocks = messages.first?["content"] as? [[String: Any]] ?? []
        XCTAssertEqual((blocks.last?["cache_control"] as? [String: String])?["type"], "ephemeral")
    }

    func testCachingMarksToolResultBlocks() {
        let call = ToolCall(id: "toolu_9", name: "read_file", arguments: "{}")
        let result = cachedBody(messages: [
            Message(role: .user, content: "go"),
            Message(role: .assistant, content: "", toolCalls: [call]),
            Message(role: .tool, content: "file contents", toolCallId: "toolu_9")
        ])
        // tool results collapse into a trailing user message; the breakpoint
        // sits on the second-to-last (the assistant tool_use turn).
        let messages = result["messages"] as? [[String: Any]] ?? []
        XCTAssertEqual(messages.count, 3)
        let markedBlocks = messages[1]["content"] as? [[String: Any]] ?? []
        XCTAssertEqual((markedBlocks.last?["cache_control"] as? [String: String])?["type"], "ephemeral")
        let lastBlocks = messages.last?["content"] as? [[String: Any]] ?? []
        XCTAssertEqual(lastBlocks.last?["type"] as? String, "tool_result")
        XCTAssertNil(lastBlocks.last?["cache_control"])
    }

    func testCachingDisabledKeepsLegacyShape() {
        let result = body(messages: [
            Message(role: .system, content: "Be terse."),
            Message(role: .user, content: "hi")
        ], tools: sampleTools)
        XCTAssertEqual(result["system"] as? String, "Be terse.", "kill-switch must restore the plain-string system")
        let tools = result["tools"] as? [[String: Any]] ?? []
        XCTAssertNil(tools.last?["cache_control"])
        let messages = result["messages"] as? [[String: Any]] ?? []
        let blocks = messages.last?["content"] as? [[String: Any]] ?? []
        XCTAssertNil(blocks.last?["cache_control"])
    }

    // MARK: - Thinking block replay (Claude Fable 5)

    func testThinkingBlocksReplayFirstInAssistantTurn() {
        let call = ToolCall(id: "toolu_01", name: "read_file", arguments: "{\"path\": \"/tmp/a\"}")
        let thinking = ThinkingBlock(thinking: "I'll read the file first.", signature: "sig_abc")
        let result = body(messages: [
            Message(role: .user, content: "read it"),
            Message(role: .assistant, content: "Reading.", toolCalls: [call], thinkingBlocks: [thinking])
        ])
        let blocks = (result["messages"] as? [[String: Any]])?.last?["content"] as? [[String: Any]] ?? []
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks[0]["type"] as? String, "thinking",
                       "Thinking must precede text and tool_use — reordering rejects the continuation")
        XCTAssertEqual(blocks[0]["thinking"] as? String, "I'll read the file first.")
        XCTAssertEqual(blocks[0]["signature"] as? String, "sig_abc")
        XCTAssertEqual(blocks[1]["type"] as? String, "text")
        XCTAssertEqual(blocks[2]["type"] as? String, "tool_use")
    }

    func testRedactedThinkingReplaysAsDataBlock() {
        let redacted = ThinkingBlock(data: "opaque==")
        let result = body(messages: [
            Message(role: .user, content: "hi"),
            Message(role: .assistant, content: "Done.", thinkingBlocks: [redacted])
        ])
        let blocks = (result["messages"] as? [[String: Any]])?.last?["content"] as? [[String: Any]] ?? []
        XCTAssertEqual(blocks.first?["type"] as? String, "redacted_thinking")
        XCTAssertEqual(blocks.first?["data"] as? String, "opaque==")
        XCTAssertNil(blocks.first?["thinking"], "Redacted blocks carry only data")
    }

    func testUnsignedThinkingBlocksAreDropped() {
        // A regular thinking block without a signature can't be replayed —
        // the API validates signatures on every non-redacted block.
        let unsigned = ThinkingBlock(thinking: "partial", signature: "")
        let result = body(messages: [
            Message(role: .user, content: "hi"),
            Message(role: .assistant, content: "Done.", thinkingBlocks: [unsigned])
        ])
        let blocks = (result["messages"] as? [[String: Any]])?.last?["content"] as? [[String: Any]] ?? []
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks.first?["type"] as? String, "text")
    }

    // MARK: - Adaptive thinking parameter

    func testAdaptiveThinkingSentForSupportedModels() {
        for model in ["claude-opus-4-8", "claude-fable-5", "claude-sonnet-5"] {
            let result = MultiProviderAIService.anthropicBody(
                messages: [Message(role: .user, content: "hi")], model: model,
                maxTokens: 64_000, stream: true, tools: nil)
            let thinking = result["thinking"] as? [String: Any]
            XCTAssertEqual(thinking?["type"] as? String, "adaptive", "\(model) should request adaptive thinking")
            XCTAssertNil(thinking?["budget_tokens"], "budget_tokens 400s on current models")
        }
    }

    func testAdaptiveThinkingOmittedForUnsupportedModels() {
        for model in ["claude-haiku-4-5", "claude-sonnet-4-5", "claude-opus-4-5"] {
            let result = MultiProviderAIService.anthropicBody(
                messages: [Message(role: .user, content: "hi")], model: model,
                maxTokens: 64_000, stream: true, tools: nil)
            XCTAssertNil(result["thinking"], "\(model) rejects the adaptive thinking parameter")
        }
    }

    func testAdaptiveThinkingGateMatrix() {
        XCTAssertTrue(MultiProviderAIService.anthropicSupportsAdaptiveThinking("claude-fable-5"))
        XCTAssertTrue(MultiProviderAIService.anthropicSupportsAdaptiveThinking("claude-mythos-5"))
        XCTAssertTrue(MultiProviderAIService.anthropicSupportsAdaptiveThinking("claude-opus-4-8"))
        XCTAssertTrue(MultiProviderAIService.anthropicSupportsAdaptiveThinking("claude-opus-4-7"))
        XCTAssertTrue(MultiProviderAIService.anthropicSupportsAdaptiveThinking("claude-sonnet-4-6"))
        XCTAssertTrue(MultiProviderAIService.anthropicSupportsAdaptiveThinking("claude-sonnet-5"))
        XCTAssertFalse(MultiProviderAIService.anthropicSupportsAdaptiveThinking("claude-haiku-4-5"))
        XCTAssertFalse(MultiProviderAIService.anthropicSupportsAdaptiveThinking("claude-sonnet-4-5"))
        XCTAssertFalse(MultiProviderAIService.anthropicSupportsAdaptiveThinking("gpt-5.2"))
    }
}
