import XCTest
@testable import GRump

/// Transport tests for `OpenAICompatibleService`. The default configuration is
/// Qwen (Alibaba DashScope); dedicated sections exercise the OpenRouter and
/// custom configurations that parameterize headers, the max-tokens field, and
/// temperature.
final class OpenAICompatibleServiceTransportTests: XCTestCase {

    func testBuildRequestContainsMessagesModelStreamAndTools() throws {
        let service = OpenAICompatibleService()
        let messages = [
            Message(role: .system, content: "You are helpful."),
            Message(role: .user, content: "Hi"),
        ]
        let request = try service.buildRequest(messages: messages, apiKey: "test-key", model: "test/model", maxTokens: 8192, stream: true)
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
        let service = OpenAICompatibleService()
        let messages = [Message(role: .user, content: "Hi")]
        XCTAssertThrowsError(try service.buildRequest(messages: messages, apiKey: "", model: "m", maxTokens: 8192, stream: true)) { error in
            XCTAssertTrue(error is OpenAICompatibleService.ServiceError)
        }
    }

    // MARK: - Request Headers

    func testBuildRequestHasContentTypeHeader() throws {
        let service = OpenAICompatibleService()
        let messages = [Message(role: .user, content: "Hi")]
        let request = try service.buildRequest(messages: messages, apiKey: "key", model: "m", maxTokens: 8192, stream: false)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    func testBuildRequestHasNoRefererHeader() throws {
        // DashScope build drops the OpenRouter HTTP-Referer routing hint.
        let service = OpenAICompatibleService()
        let messages = [Message(role: .user, content: "Hi")]
        let request = try service.buildRequest(messages: messages, apiKey: "key", model: "m", maxTokens: 8192, stream: false)
        XCTAssertNil(request.value(forHTTPHeaderField: "HTTP-Referer"))
    }

    func testBuildRequestHasNoPlatformHeader() throws {
        // DashScope build drops the OpenRouter X-Client-Platform routing hint.
        let service = OpenAICompatibleService()
        let messages = [Message(role: .user, content: "Hi")]
        let request = try service.buildRequest(messages: messages, apiKey: "key", model: "m", maxTokens: 8192, stream: false)
        XCTAssertNil(request.value(forHTTPHeaderField: "X-Client-Platform"))
    }

    // MARK: - Request Body

    func testBuildRequestStreamFalse() throws {
        let service = OpenAICompatibleService()
        let messages = [Message(role: .user, content: "Test")]
        let request = try service.buildRequest(messages: messages, apiKey: "key", model: "m", maxTokens: 8192, stream: false)
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["stream"] as? Bool, false)
    }

    func testBuildRequestContainsMaxTokens() throws {
        let service = OpenAICompatibleService()
        let messages = [Message(role: .user, content: "Test")]
        let request = try service.buildRequest(messages: messages, apiKey: "key", model: "test/model", maxTokens: 8192, stream: true)
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        // Default configuration is .openAI, whose cap field is max_completion_tokens.
        XCTAssertNotNil(json["max_completion_tokens"])
    }

    /// The transport must send exactly the caller-supplied max-tokens value — the
    /// param that severed the transport's dependency on the legacy `AIModel` enum.
    func testBuildRequestUsesSuppliedMaxTokens() throws {
        let service = OpenAICompatibleService()
        let messages = [Message(role: .user, content: "Test")]
        let request = try service.buildRequest(messages: messages, apiKey: "key", model: "m", maxTokens: 4096, stream: true)
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["max_completion_tokens"] as? Int, 4096)
    }

    func testBuildRequestContainsTemperature() throws {
        let service = OpenAICompatibleService()
        let messages = [Message(role: .user, content: "Test")]
        let request = try service.buildRequest(messages: messages, apiKey: "key", model: "test/model", maxTokens: 8192, stream: true)
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertNotNil(json["temperature"])
    }

    func testBuildRequestContainsToolChoice() throws {
        let service = OpenAICompatibleService()
        let messages = [Message(role: .user, content: "Test")]
        let request = try service.buildRequest(messages: messages, apiKey: "key", model: "m", maxTokens: 8192, stream: true)
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["tool_choice"] as? String, "auto")
    }

    // MARK: - Configuration: max-tokens field name

    /// OpenAI's newer models require `max_completion_tokens` instead of
    /// `max_tokens`. A configuration can rename the field.
    func testMaxCompletionTokensFieldUsedWhenConfigured() throws {
        let config = OpenAICompatibleService.Configuration(
            baseURL: "https://api.openai.com/v1",
            maxTokensField: "max_completion_tokens",
            providerLabel: "OpenAI"
        )
        let service = OpenAICompatibleService(configuration: config)
        let messages = [Message(role: .user, content: "Test")]
        let request = try service.buildRequest(messages: messages, apiKey: "key", model: "gpt-5.2", maxTokens: 4096, stream: true)
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["max_completion_tokens"] as? Int, 4096)
        XCTAssertNil(json["max_tokens"], "Only the configured field should be present")
    }

    /// The `.openAI` factory uses `max_completion_tokens`.
    func testOpenAIConfigUsesCompletionTokensField() throws {
        let service = OpenAICompatibleService(configuration: .openAI)
        let messages = [Message(role: .user, content: "Test")]
        let request = try service.buildRequest(messages: messages, apiKey: "key", model: "gpt-5.2", maxTokens: 2048, stream: true)
        XCTAssertEqual(request.url?.host, "api.openai.com")
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertNotNil(json["max_completion_tokens"])
    }

    // MARK: - Configuration: temperature omission

    /// A configuration can omit `temperature` entirely (Claude 4.7+/5 reject it).
    func testTemperatureOmittedWhenConfigured() throws {
        let config = OpenAICompatibleService.Configuration(
            baseURL: "https://api.openai.com/v1",
            includeTemperature: false,
            providerLabel: "OpenAI"
        )
        let service = OpenAICompatibleService(configuration: config)
        let messages = [Message(role: .user, content: "Test")]
        let request = try service.buildRequest(messages: messages, apiKey: "key", model: "m", maxTokens: 4096, stream: true)
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertNil(json["temperature"], "temperature must be absent when includeTemperature is false")
    }

    // MARK: - Configuration: OpenRouter routing

    /// The `.openRouter` configuration restores the routing headers and the
    /// `provider` body block that the DashScope-only build had to drop.
    func testOpenRouterConfigAddsRoutingHeaders() throws {
        let service = OpenAICompatibleService(configuration: .openRouter)
        let messages = [Message(role: .user, content: "Hi")]
        let request = try service.buildRequest(messages: messages, apiKey: "key", model: "anthropic/claude-sonnet-5", maxTokens: 8192, stream: true)
        XCTAssertEqual(request.value(forHTTPHeaderField: "HTTP-Referer"), "https://www.g-rump.com")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Title"), "G-Rump")
        #if os(macOS)
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Client-Platform"), "macos-native")
        #else
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Client-Platform"), "ios-native")
        #endif
    }

    func testOpenRouterConfigAddsProviderBlock() throws {
        let service = OpenAICompatibleService(configuration: .openRouter)
        let messages = [Message(role: .user, content: "Hi")]
        let request = try service.buildRequest(messages: messages, apiKey: "key", model: "anthropic/claude-sonnet-5", maxTokens: 8192, stream: true)
        XCTAssertEqual(request.url?.host, "openrouter.ai")
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let provider = try XCTUnwrap(json["provider"] as? [String: Any])
        XCTAssertEqual(provider["sort"] as? String, "price")
        XCTAssertEqual(provider["allow_fallbacks"] as? Bool, true)
    }

    // MARK: - Message Serialization

    func testAssistantMessageWithToolCallsSerialized() throws {
        let service = OpenAICompatibleService()
        var msg = Message(role: .assistant, content: "")
        msg.toolCalls = [ToolCall(id: "tc1", name: "read_file", arguments: "{\"path\":\"/test\"}")]
        let messages = [msg]
        let request = try service.buildRequest(messages: messages, apiKey: "key", model: "m", maxTokens: 8192, stream: false)
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let msgs = try XCTUnwrap(json["messages"] as? [[String: Any]])
        XCTAssertEqual(msgs.count, 1)
        XCTAssertNotNil(msgs[0]["tool_calls"])
    }

    func testToolMessageSerialized() throws {
        let service = OpenAICompatibleService()
        var msg = Message(role: .tool, content: "file contents here")
        msg.toolCallId = "tc1"
        let messages = [msg]
        let request = try service.buildRequest(messages: messages, apiKey: "key", model: "m", maxTokens: 8192, stream: false)
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let msgs = try XCTUnwrap(json["messages"] as? [[String: Any]])
        XCTAssertEqual(msgs[0]["role"] as? String, "tool")
        XCTAssertEqual(msgs[0]["tool_call_id"] as? String, "tc1")
    }

    // MARK: - Backend Request

    func testBuildBackendRequestURL() throws {
        let service = OpenAICompatibleService()
        let messages = [Message(role: .user, content: "Hi")]
        let request = try service.buildBackendRequest(
            messages: messages, model: "m", maxTokens: 8192, stream: true,
            backendBaseURL: "https://api.grump.app", appAPIKey: "tok123"
        )
        XCTAssertEqual(request.url?.host, "api.grump.app")
        XCTAssertTrue(request.url?.path.contains("chat/completions") ?? false)
    }

    func testBuildBackendRequestAuth() throws {
        let service = OpenAICompatibleService()
        let messages = [Message(role: .user, content: "Hi")]
        let request = try service.buildBackendRequest(
            messages: messages, model: "m", maxTokens: 8192, stream: true,
            backendBaseURL: "https://api.grump.app", appAPIKey: "tok123"
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok123")
    }

    func testBuildBackendRequestTrimsTrailingSlash() throws {
        let service = OpenAICompatibleService()
        let messages = [Message(role: .user, content: "Hi")]
        let request = try service.buildBackendRequest(
            messages: messages, model: "m", maxTokens: 8192, stream: true,
            backendBaseURL: "https://api.grump.app/", appAPIKey: "tok"
        )
        // The base's trailing slash must be trimmed so the path has no "host//path".
        XCTAssertFalse(request.url?.absoluteString.contains(".app//") ?? true)
    }

    // MARK: - ServiceError

    func testServiceErrorMissingAPIKey() {
        let error = OpenAICompatibleService.ServiceError.missingAPIKey
        XCTAssertNotNil(error.errorDescription)
    }

    func testServiceErrorNetwork() {
        let error = OpenAICompatibleService.ServiceError.networkError
        XCTAssertNotNil(error.errorDescription)
    }

    func testServiceErrorAPIError() {
        let error = OpenAICompatibleService.ServiceError.apiError(statusCode: 429, message: "Rate limited")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("429") ?? false)
    }

    func testServiceErrorInvalidResponse() {
        let error = OpenAICompatibleService.ServiceError.invalidResponse
        XCTAssertNotNil(error.errorDescription)
    }
}
