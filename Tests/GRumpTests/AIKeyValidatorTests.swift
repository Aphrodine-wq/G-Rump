import XCTest
@testable import GRump

final class AIKeyValidatorTests: XCTestCase {

    // MARK: - Status classification

    func testSuccessStatusesAreValid() {
        XCTAssertEqual(AIKeyValidator.classify(statusCode: 200, provider: .anthropic), .valid)
        XCTAssertEqual(AIKeyValidator.classify(statusCode: 204, provider: .openAI), .valid)
    }

    func testAuthFailuresAreInvalid() {
        XCTAssertEqual(AIKeyValidator.classify(statusCode: 401, provider: .anthropic), .invalid)
        XCTAssertEqual(AIKeyValidator.classify(statusCode: 403, provider: .google), .invalid)
    }

    func testOtherStatusesAreIndeterminate() {
        for code in [404, 429, 500, 529] {
            guard case .indeterminate(let reason) = AIKeyValidator.classify(statusCode: code, provider: .openRouter) else {
                return XCTFail("HTTP \(code) must be indeterminate — it says nothing about the key")
            }
            XCTAssertTrue(reason.contains("\(code)"), "reason should surface the status code")
        }
    }

    // MARK: - Request building

    func testAnthropicRequestUsesNativeHeaders() throws {
        let request = try XCTUnwrap(AIKeyValidator.validationRequest(for: .anthropic, apiKey: "sk-ant-test"))
        XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/models")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "sk-ant-test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    func testOpenAIRequestUsesBearerAuth() throws {
        let request = try XCTUnwrap(AIKeyValidator.validationRequest(for: .openAI, apiKey: "sk-test"))
        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/models")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
    }

    func testGoogleRequestKeepsKeyOutOfURL() throws {
        let request = try XCTUnwrap(AIKeyValidator.validationRequest(for: .google, apiKey: "AIza-test"))
        XCTAssertEqual(request.url?.absoluteString, "https://generativelanguage.googleapis.com/v1beta/models")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "AIza-test")
        XCTAssertFalse(request.url?.absoluteString.contains("AIza-test") ?? true,
                       "key must ride a header, never the URL")
    }

    func testOpenRouterProbesKeyEndpoint() throws {
        let request = try XCTUnwrap(AIKeyValidator.validationRequest(for: .openRouter, apiKey: "sk-or-test"))
        XCTAssertEqual(request.url?.absoluteString, "https://openrouter.ai/api/v1/key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-or-test")
    }

    func testOllamaProbesNativeTagsEndpointUnauthenticated() throws {
        let request = try XCTUnwrap(AIKeyValidator.validationRequest(for: .ollama, apiKey: ""))
        XCTAssertEqual(request.url?.absoluteString, "http://localhost:11434/api/tags",
                       "probe hits the native API root, not the /v1 OpenAI-compat path")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"), "Ollama is keyless")
    }

    func testCustomBaseURLIsRespected() throws {
        let request = try XCTUnwrap(AIKeyValidator.validationRequest(
            for: .anthropic, apiKey: "k", baseURL: "https://proxy.example.com/v1"))
        XCTAssertEqual(request.url?.absoluteString, "https://proxy.example.com/v1/models")
    }

    func testMalformedBaseURLProducesNoRequest() {
        XCTAssertNil(AIKeyValidator.validationRequest(for: .anthropic, apiKey: "k", baseURL: "not a url"))
    }

    func testRequestsCarryShortTimeout() throws {
        let request = try XCTUnwrap(AIKeyValidator.validationRequest(for: .openAI, apiKey: "k"))
        XCTAssertEqual(request.timeoutInterval, AIKeyValidator.timeout)
    }

    // MARK: - Error reasons

    func testTimeoutMapsToReadableReason() {
        XCTAssertEqual(AIKeyValidator.reason(for: URLError(.timedOut)), "The request timed out")
    }

    func testOfflineMapsToReadableReason() {
        XCTAssertEqual(AIKeyValidator.reason(for: URLError(.notConnectedToInternet)), "No connection to the provider")
        XCTAssertEqual(AIKeyValidator.reason(for: URLError(.cannotConnectToHost)), "No connection to the provider")
    }

    // MARK: - validate() guards (no network touched)

    func testEmptyKeyIsInvalidWithoutNetwork() async {
        let result = await AIKeyValidator.validate(provider: .anthropic, apiKey: "   ")
        XCTAssertEqual(result, .invalid)
    }

    func testMalformedBaseURLIsIndeterminateWithoutNetwork() async {
        let result = await AIKeyValidator.validate(provider: .openAI, apiKey: "k", baseURL: "not a url")
        guard case .indeterminate = result else {
            return XCTFail("malformed base URL must be indeterminate, got \(result)")
        }
    }
}
