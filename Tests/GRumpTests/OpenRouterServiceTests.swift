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
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Title"), "G-Rump")
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
        let provider = try XCTUnwrap(json["provider"] as? [String: Any])
        XCTAssertEqual(provider["sort"] as? String, "price")
    }

    func testBuildRequestThrowsWhenAPIKeyEmpty() {
        let service = OpenRouterService()
        let messages = [Message(role: .user, content: "Hi")]
        XCTAssertThrowsError(try service.buildRequest(messages: messages, apiKey: "", model: "m", stream: true)) { error in
            XCTAssertTrue(error is OpenRouterService.ServiceError)
        }
    }
}
