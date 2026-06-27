import XCTest
@testable import GRump

final class OpenRouterServiceTests: XCTestCase {

    func testBuildRequestContainsMessagesModelStreamAndTools() throws {
        let service = OpenRouterService()
        let messages = [
            Message(role: .system, content: "You are helpful."),
            Message(role: .user, content: "Hi"),
        ]
        let request = try service.buildRequest(messages: messages, apiKey: "test-key", model: "test/model", stream: true)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.timeoutInterval, 180)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        // DashScope build: no OpenRouter X-Title routing hint.
        XCTAssertNil(request.value(forHTTPHeaderField: "X-Title"))
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "test/model")
        XCTAssertEqual(json["stream"] as? Bool, true)
        XCTAssertNotNil(json["messages"])
        let msgs = try XCTUnwrap(json["messages"] as? [[String: Any]])
        XCTAssertEqual(msgs.count, 2)
        XCTAssertEqual(msgs[0]["role"] as? String, "system")
        XCTAssertEqual(msgs[0]["content"] as? String, "You are helpful.")
        XCTAssertEqual(msgs[1]["role"] as? String, "user")
        XCTAssertEqual(msgs[1]["content"] as? String, "Hi")
        XCTAssertNotNil(json["tools"])
        // DashScope rejects unknown fields — no OpenRouter `provider` routing block.
        XCTAssertNil(json["provider"])
    }

    func testBuildRequestThrowsWhenAPIKeyEmpty() {
        let service = OpenRouterService()
        let messages = [Message(role: .user, content: "Hi")]
        XCTAssertThrowsError(try service.buildRequest(messages: messages, apiKey: "", model: "m", stream: true)) { error in
            XCTAssertTrue(error is OpenRouterService.ServiceError)
        }
    }

    // MARK: - Request Headers

    func testBuildRequestHasContentTypeHeader() throws {
        let service = OpenRouterService()
        let messages = [Message(role: .user, content: "Hi")]
        let request = try service.buildRequest(messages: messages, apiKey: "key", model: "m", stream: false)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    func testBuildRequestHasNoRefererHeader() throws {
        // DashScope build drops the OpenRouter HTTP-Referer routing hint.
        let service = OpenRouterService()
        let messages = [Message(role: .user, content: "Hi")]
        let request = try service.buildRequest(messages: messages, apiKey: "key", model: "m", stream: false)
        XCTAssertNil(request.value(forHTTPHeaderField: "HTTP-Referer"))
    }

    func testBuildRequestHasNoPlatformHeader() throws {
        // DashScope build drops the OpenRouter X-Client-Platform routing hint.
        let service = OpenRouterService()
        let messages = [Message(role: .user, content: "Hi")]
        let request = try service.buildRequest(messages: messages, apiKey: "key", model: "m", stream: false)
        XCTAssertNil(request.value(forHTTPHeaderField: "X-Client-Platform"))
    }

    // MARK: - Request Body

    func testBuildRequestStreamFalse() throws {
        let service = OpenRouterService()
        let messages = [Message(role: .user, content: "Test")]
        let request = try service.buildRequest(messages: messages, apiKey: "key", model: "m", stream: false)
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["stream"] as? Bool, false)
    }

    func testBuildRequestContainsMaxTokens() throws {
        let service = OpenRouterService()
        let messages = [Message(role: .user, content: "Test")]
        let request = try service.buildRequest(messages: messages, apiKey: "key", model: "test/model", stream: true)
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertNotNil(json["max_tokens"])
    }

    func testBuildRequestContainsTemperature() throws {
        let service = OpenRouterService()
        let messages = [Message(role: .user, content: "Test")]
        let request = try service.buildRequest(messages: messages, apiKey: "key", model: "test/model", stream: true)
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertNotNil(json["temperature"])
    }

    func testBuildRequestContainsToolChoice() throws {
        let service = OpenRouterService()
        let messages = [Message(role: .user, content: "Test")]
        let request = try service.buildRequest(messages: messages, apiKey: "key", model: "m", stream: true)
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["tool_choice"] as? String, "auto")
    }

    // MARK: - Message Serialization

    func testAssistantMessageWithToolCallsSerialized() throws {
        let service = OpenRouterService()
        var msg = Message(role: .assistant, content: "")
        msg.toolCalls = [ToolCall(id: "tc1", name: "read_file", arguments: "{\"path\":\"/test\"}")]
        let messages = [msg]
        let request = try service.buildRequest(messages: messages, apiKey: "key", model: "m", stream: false)
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let msgs = try XCTUnwrap(json["messages"] as? [[String: Any]])
        XCTAssertEqual(msgs.count, 1)
        XCTAssertNotNil(msgs[0]["tool_calls"])
    }

    func testToolMessageSerialized() throws {
        let service = OpenRouterService()
        var msg = Message(role: .tool, content: "file contents here")
        msg.toolCallId = "tc1"
        let messages = [msg]
        let request = try service.buildRequest(messages: messages, apiKey: "key", model: "m", stream: false)
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let msgs = try XCTUnwrap(json["messages"] as? [[String: Any]])
        XCTAssertEqual(msgs[0]["role"] as? String, "tool")
        XCTAssertEqual(msgs[0]["tool_call_id"] as? String, "tc1")
    }

    // MARK: - Backend Request

    func testBuildBackendRequestURL() throws {
        let service = OpenRouterService()
        let messages = [Message(role: .user, content: "Hi")]
        let request = try service.buildBackendRequest(
            messages: messages, model: "m", stream: true,
            backendBaseURL: "https://api.grump.app", authToken: "tok123"
        )
        XCTAssertEqual(request.url?.host, "api.grump.app")
        XCTAssertTrue(request.url?.path.contains("chat/completions") ?? false)
    }

    func testBuildBackendRequestAuth() throws {
        let service = OpenRouterService()
        let messages = [Message(role: .user, content: "Hi")]
        let request = try service.buildBackendRequest(
            messages: messages, model: "m", stream: true,
            backendBaseURL: "https://api.grump.app", authToken: "tok123"
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok123")
    }

    func testBuildBackendRequestTrimsTrailingSlash() throws {
        let service = OpenRouterService()
        let messages = [Message(role: .user, content: "Hi")]
        let request = try service.buildBackendRequest(
            messages: messages, model: "m", stream: true,
            backendBaseURL: "https://api.grump.app/", authToken: "tok"
        )
        // The base's trailing slash must be trimmed so the path has no "host//path".
        XCTAssertFalse(request.url?.absoluteString.contains(".app//") ?? true)
    }

    // MARK: - ServiceError

    func testServiceErrorMissingAPIKey() {
        let error = OpenRouterService.ServiceError.missingAPIKey
        XCTAssertNotNil(error.errorDescription)
    }

    func testServiceErrorNetwork() {
        let error = OpenRouterService.ServiceError.networkError
        XCTAssertNotNil(error.errorDescription)
    }

    func testServiceErrorAPIError() {
        let error = OpenRouterService.ServiceError.apiError(statusCode: 429, message: "Rate limited")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("429") ?? false)
    }

    func testServiceErrorInvalidResponse() {
        let error = OpenRouterService.ServiceError.invalidResponse
        XCTAssertNotNil(error.errorDescription)
    }
}
