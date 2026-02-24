import XCTest
@testable import GRump

final class PersistenceTests: XCTestCase {

    func testSDConversationFromLegacy() {
        var conv = Conversation(title: "Test Chat")
        conv.messages = [
            Message(role: .user, content: "Hello"),
            Message(role: .assistant, content: "Hi there!"),
        ]
        let sd = SDConversation(from: conv)
        XCTAssertEqual(sd.title, "Test Chat")
        XCTAssertEqual(sd.conversationId, conv.id)
    }

    func testSDMessageFromLegacy() {
        let msg = Message(role: .assistant, content: "Swift is great", toolCalls: [ToolCall(id: "tc1", name: "read_file", arguments: "{}")])
        let sd = SDMessage(from: msg)
        XCTAssertEqual(sd.role, "assistant")
        XCTAssertEqual(sd.content, "Swift is great")
        XCTAssertNotNil(sd.toolCallsData)
    }

    func testSDConversationCodableRoundTrip() throws {
        let sd = SDConversation(from: Conversation(title: "Roundtrip"))
        let data = try JSONEncoder().encode(sd)
        let decoded = try JSONDecoder().decode(SDConversation.self, from: data)
        XCTAssertEqual(decoded.title, "Roundtrip")
        XCTAssertEqual(decoded.conversationId, sd.conversationId)
    }

    @MainActor func testGRumpPersistenceStoreShared() {
        let store = GRumpPersistenceStore.shared
        XCTAssertNotNil(store)
    }
}
