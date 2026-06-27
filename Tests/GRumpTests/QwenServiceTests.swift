import XCTest
@testable import GRump

/// Unit tests for the Qwen transport (class still named `OpenRouterService`,
/// but it now targets Alibaba DashScope's OpenAI-compatible endpoint).
///
/// We exercise the reachable public/internal surface: `buildRequest(...)` is
/// internal, so `@testable import` lets us build a real `URLRequest` and inspect
/// its URL, headers, and JSON body without hitting the network.
final class QwenServiceTests: XCTestCase {

    private func sampleMessages() -> [Message] {
        [
            Message(role: .system, content: "You are a helpful assistant."),
            Message(role: .user, content: "Hello"),
        ]
    }

    private func decodedBody(_ request: URLRequest) throws -> [String: Any] {
        let data = try XCTUnwrap(request.httpBody, "Request should have an HTTP body")
        let obj = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(obj as? [String: Any], "Body should be a JSON object")
    }

    // MARK: - URL targets DashScope

    func testRequestTargetsDashScopeHost() throws {
        let service = OpenRouterService()
        let request = try service.buildRequest(
            messages: sampleMessages(),
            apiKey: "sk-test-key",
            model: AIModel.qwenCoderPlus.rawValue,
            stream: true,
            tools: nil
        )
        let host = try XCTUnwrap(request.url?.host)
        XCTAssertTrue(host.contains("dashscope"), "URL host should target DashScope, got \(host)")
        XCTAssertEqual(request.url?.path, "/compatible-mode/v1/chat/completions")
    }

    // MARK: - Authorization header

    func testRequestHasBearerAuthorizationHeader() throws {
        let service = OpenRouterService()
        let request = try service.buildRequest(
            messages: sampleMessages(),
            apiKey: "sk-test-key",
            model: AIModel.qwenCoderPlus.rawValue,
            stream: true,
            tools: nil
        )
        let auth = try XCTUnwrap(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(auth, "Bearer sk-test-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    // MARK: - Body shape: tool_choice + tools, no OpenRouter/Anthropic fields

    func testBodyHasToolChoiceAutoAndToolsArray() throws {
        let service = OpenRouterService()
        let tools: [[String: Any]] = [[
            "type": "function",
            "function": ["name": "read_file", "description": "read", "parameters": ["type": "object"]],
        ]]
        let request = try service.buildRequest(
            messages: sampleMessages(),
            apiKey: "sk-test-key",
            model: AIModel.qwenCoderPlus.rawValue,
            stream: true,
            tools: tools
        )
        let body = try decodedBody(request)

        XCTAssertEqual(body["tool_choice"] as? String, "auto")
        let bodyTools = try XCTUnwrap(body["tools"] as? [[String: Any]])
        XCTAssertFalse(bodyTools.isEmpty, "tools array should be present and non-empty")
        XCTAssertEqual(body["model"] as? String, AIModel.qwenCoderPlus.rawValue)
    }

    func testBodyDoesNotContainOpenRouterOrAnthropicFields() throws {
        let service = OpenRouterService()
        let request = try service.buildRequest(
            messages: sampleMessages(),
            apiKey: "sk-test-key",
            model: AIModel.qwenCoderPlus.rawValue,
            stream: true,
            tools: nil
        )
        let body = try decodedBody(request)

        // DashScope 400s on unknown routing fields — these must be absent.
        XCTAssertNil(body["provider"], "Body must not contain OpenRouter `provider` routing block")
        XCTAssertNil(body["HTTP-Referer"], "Body must not contain HTTP-Referer")
        XCTAssertNil(body["anthropic-version"], "Body must not contain anthropic-version")

        // Same for headers — no OpenRouter/Anthropic routing hints.
        XCTAssertNil(request.value(forHTTPHeaderField: "HTTP-Referer"))
        XCTAssertNil(request.value(forHTTPHeaderField: "anthropic-version"))
        XCTAssertNil(request.value(forHTTPHeaderField: "X-Title"))
    }

    // MARK: - Missing API key path

    func testBuildRequestThrowsOnEmptyAPIKey() {
        let service = OpenRouterService()
        XCTAssertThrowsError(
            try service.buildRequest(
                messages: sampleMessages(),
                apiKey: "",
                model: AIModel.qwenCoderPlus.rawValue,
                stream: true,
                tools: nil
            )
        ) { error in
            guard case OpenRouterService.ServiceError.missingAPIKey = error else {
                return XCTFail("Expected .missingAPIKey, got \(error)")
            }
        }
    }
}
