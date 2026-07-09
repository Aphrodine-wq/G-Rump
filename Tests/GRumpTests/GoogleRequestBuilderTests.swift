import XCTest
@testable import GRump

final class GoogleRequestBuilderTests: XCTestCase {

    private func body(messages: [Message], tools: [[String: Any]]? = nil) -> [String: Any] {
        MultiProviderAIService.googleBody(messages: messages, maxOutputTokens: 65_536, tools: tools)
    }

    // MARK: - Request

    func testRequestURLUsesSSEStreamingEndpoint() throws {
        let request = try MultiProviderAIService.buildGoogleRequest(
            messages: [Message(role: .user, content: "hi")],
            model: "gemini-3-pro",
            apiKey: "AIza-test",
            baseURL: "https://generativelanguage.googleapis.com/v1beta",
            maxOutputTokens: 65_536,
            tools: nil
        )
        let url = request.url?.absoluteString ?? ""
        XCTAssertTrue(url.contains("/models/gemini-3-pro:streamGenerateContent"))
        XCTAssertTrue(url.contains("alt=sse"))
        XCTAssertTrue(url.contains("key=AIza-test"))
    }

    // MARK: - Body shape

    func testSystemBecomesSystemInstruction() {
        let result = body(messages: [
            Message(role: .system, content: "Be terse."),
            Message(role: .user, content: "hi")
        ])
        let instruction = result["systemInstruction"] as? [String: Any]
        let parts = instruction?["parts"] as? [[String: Any]]
        XCTAssertEqual(parts?.first?["text"] as? String, "Be terse.")
        let contents = result["contents"] as? [[String: Any]] ?? []
        XCTAssertEqual(contents.count, 1, "System must not appear in contents")
    }

    func testNoTemperatureInGenerationConfig() {
        let result = body(messages: [Message(role: .user, content: "hi")])
        let config = result["generationConfig"] as? [String: Any]
        XCTAssertEqual(config?["maxOutputTokens"] as? Int, 65_536)
        XCTAssertNil(config?["temperature"])
    }

    func testAssistantToolCallsBecomeFunctionCallParts() {
        let call = ToolCall(id: "g1", name: "list_files", arguments: "{\"dir\": \"/tmp\"}")
        let result = body(messages: [
            Message(role: .user, content: "list"),
            Message(role: .assistant, content: "", toolCalls: [call])
        ])
        let contents = result["contents"] as? [[String: Any]] ?? []
        let model = contents.last
        XCTAssertEqual(model?["role"] as? String, "model")
        let parts = model?["parts"] as? [[String: Any]] ?? []
        let functionCall = parts.first?["functionCall"] as? [String: Any]
        XCTAssertEqual(functionCall?["name"] as? String, "list_files")
        XCTAssertEqual((functionCall?["args"] as? [String: Any])?["dir"] as? String, "/tmp",
                       "Args must be the parsed object — the old builder dropped model-turn calls entirely")
    }

    func testToolResultsBecomeFunctionResponsesWithResolvedNames() {
        // The fix: .tool messages were silently dropped by the old builder,
        // breaking every Gemini tool loop after the first turn. Names resolve
        // from the assistant turn that issued the call (Gemini has no ids).
        let calls = [
            ToolCall(id: "g1", name: "list_files", arguments: "{}"),
            ToolCall(id: "g2", name: "read_file", arguments: "{}")
        ]
        let result = body(messages: [
            Message(role: .user, content: "go"),
            Message(role: .assistant, content: "", toolCalls: calls),
            Message(role: .tool, content: "a.txt b.txt", toolCallId: "g1"),
            Message(role: .tool, content: "hello", toolCallId: "g2")
        ])
        let contents = result["contents"] as? [[String: Any]] ?? []
        XCTAssertEqual(contents.count, 3, "user + model + ONE merged functionResponse turn")
        let responseTurn = contents.last
        XCTAssertEqual(responseTurn?["role"] as? String, "user")
        let parts = responseTurn?["parts"] as? [[String: Any]] ?? []
        XCTAssertEqual(parts.count, 2)
        let first = parts.first?["functionResponse"] as? [String: Any]
        XCTAssertEqual(first?["name"] as? String, "list_files")
        XCTAssertEqual((first?["response"] as? [String: Any])?["result"] as? String, "a.txt b.txt")
        let second = parts.last?["functionResponse"] as? [String: Any]
        XCTAssertEqual(second?["name"] as? String, "read_file")
    }

    func testFunctionDeclarationsAreSanitized() {
        let tools: [[String: Any]] = [[
            "type": "function",
            "function": [
                "name": "write_file",
                "description": "Write a file",
                "parameters": [
                    "type": "object",
                    "additionalProperties": false,
                    "$schema": "http://json-schema.org/draft-07/schema#",
                    "properties": [
                        "path": ["type": "string", "format": "uri", "minLength": 1]
                    ],
                    "required": ["path"]
                ]
            ]
        ]]
        let result = body(messages: [Message(role: .user, content: "hi")], tools: tools)
        let toolsOut = result["tools"] as? [[String: Any]] ?? []
        let declarations = toolsOut.first?["functionDeclarations"] as? [[String: Any]] ?? []
        XCTAssertEqual(declarations.count, 1)
        let parameters = declarations.first?["parameters"] as? [String: Any]
        XCTAssertNil(parameters?["additionalProperties"], "Gemini rejects JSON-Schema keywords")
        XCTAssertNil(parameters?["$schema"])
        let path = (parameters?["properties"] as? [String: Any])?["path"] as? [String: Any]
        XCTAssertNil(path?["format"])
        XCTAssertNil(path?["minLength"])
        XCTAssertEqual(path?["type"] as? String, "string", "Supported keys survive sanitization")
        XCTAssertEqual(parameters?["required"] as? [String], ["path"])
    }
}
