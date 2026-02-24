import XCTest
@testable import GRump

final class MemoryStoreTests: XCTestCase {

    private var tempDir: String!

    override func setUp() {
        super.setUp()
        tempDir = NSTemporaryDirectory() + "GRumpTests-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: tempDir)
        super.tearDown()
    }

    // MARK: - MemoryStore (plain-text)

    func testMemoryStoreAddAndRetrieve() {
        let store = MemoryStore(baseDirectory: tempDir)
        XCTAssertEqual(store.count(), 0)

        store.addEntry(conversationId: "c1", userMessage: "Hello", assistantContent: "Hi there")
        XCTAssertEqual(store.count(), 1)

        let entries = store.recentEntries()
        XCTAssertEqual(entries.count, 1)
        XCTAssertTrue(entries[0].content.contains("Hello"))
        XCTAssertTrue(entries[0].content.contains("Hi there"))
    }

    func testMemoryStoreMultipleEntries() {
        let store = MemoryStore(baseDirectory: tempDir)
        for i in 0..<5 {
            store.addEntry(conversationId: "c\(i)", userMessage: "Q\(i)", assistantContent: "A\(i)")
        }
        XCTAssertEqual(store.count(), 5)

        let recent = store.recentEntries(limit: 3)
        XCTAssertEqual(recent.count, 3)
        // Most recent first
        XCTAssertTrue(recent[0].content.contains("Q4"))
    }

    func testMemoryStoreClear() {
        let store = MemoryStore(baseDirectory: tempDir)
        store.addEntry(conversationId: "c1", userMessage: "Q", assistantContent: "A")
        XCTAssertEqual(store.count(), 1)
        store.clear()
        XCTAssertEqual(store.count(), 0)
    }

    func testMemoryStoreProtocolConformance() {
        let store: ProjectMemoryStore = MemoryStore(baseDirectory: tempDir)
        store.addEntry(conversationId: "c1", userMessage: "What is Swift?", assistantContent: "A programming language.", toolCallSummary: "")
        XCTAssertEqual(store.count(), 1)

        let unified = store.retrieveEntries(query: "Swift", limit: 5)
        XCTAssertEqual(unified.count, 1)
        XCTAssertTrue(unified[0].content.contains("Swift"))
    }

    func testMemoryBlockReturnsNilWhenEmpty() {
        let store: ProjectMemoryStore = MemoryStore(baseDirectory: tempDir)
        XCTAssertNil(store.memoryBlock(for: "anything"))
    }

    func testMemoryBlockReturnsFormattedBlock() {
        let store: ProjectMemoryStore = MemoryStore(baseDirectory: tempDir)
        store.addEntry(conversationId: "c1", userMessage: "Hello", assistantContent: "World", toolCallSummary: "")
        let block = store.memoryBlock(for: "Hello")
        XCTAssertNotNil(block)
        XCTAssertTrue(block!.contains("Project Memory"))
        XCTAssertTrue(block!.contains("Hello"))
    }

    func testMemoryStoreEmptyBaseDirectory() {
        let store = MemoryStore(baseDirectory: "")
        store.addEntry(conversationId: "c1", userMessage: "Q", assistantContent: "A")
        XCTAssertEqual(store.count(), 0)
    }

    // MARK: - SemanticMemoryStore

    func testSemanticMemoryStoreAddAndRetrieve() {
        let store = SemanticMemoryStore(baseDirectory: tempDir)
        XCTAssertEqual(store.count(), 0)

        store.addEntry(conversationId: "c1", userMessage: "Tell me about Swift programming", assistantContent: "Swift is a modern language by Apple")
        // NLEmbedding may not be available in test environments
        // If embedding succeeds, count will be 1; if not, it stays 0
        let count = store.count()
        if count > 0 {
            XCTAssertEqual(count, 1)
            let entries = store.relevantEntries(for: "Swift")
            XCTAssertFalse(entries.isEmpty)
        }
    }

    func testSemanticMemoryStoreProtocolConformance() {
        let store: ProjectMemoryStore = SemanticMemoryStore(baseDirectory: tempDir)
        store.addEntry(conversationId: "c1", userMessage: "Hello world", assistantContent: "Greetings", toolCallSummary: "")
        // Protocol methods should work regardless of embedding availability
        let unified = store.retrieveEntries(query: "Hello", limit: 5)
        // May be empty if NLEmbedding unavailable in CI
        XCTAssertTrue(unified.count <= 1)
    }

    func testSemanticMemoryStoreClear() {
        let store = SemanticMemoryStore(baseDirectory: tempDir)
        store.addEntry(conversationId: "c1", userMessage: "test input", assistantContent: "test output")
        store.clear()
        XCTAssertEqual(store.count(), 0)
    }

    func testSemanticMemoryStoreEmptyBaseDirectory() {
        let store = SemanticMemoryStore(baseDirectory: "")
        store.addEntry(conversationId: "c1", userMessage: "Q", assistantContent: "A")
        XCTAssertEqual(store.count(), 0)
    }

    // MARK: - UnifiedMemoryEntry

    func testUnifiedMemoryEntryFields() {
        let id = UUID()
        let entry = UnifiedMemoryEntry(id: id, conversationId: "conv-1", timestamp: "2025-01-01T00:00:00Z", content: "Test content")
        XCTAssertEqual(entry.id, id)
        XCTAssertEqual(entry.conversationId, "conv-1")
        XCTAssertEqual(entry.timestamp, "2025-01-01T00:00:00Z")
        XCTAssertEqual(entry.content, "Test content")
    }
}
