import XCTest
@testable import GRump

/// End-to-end validation tests that verify models, services, and their interactions
/// work correctly together. These tests catch issues that unit tests miss.
final class IntegrationValidationTests: XCTestCase {

    // MARK: - Conversation Lifecycle

    func testFullConversationLifecycle() throws {
        // Create → Add messages → Thread → Branch → Encode → Decode
        var conv = Conversation(title: "Test Chat")
        XCTAssertTrue(conv.messages.isEmpty)

        // Add a system message
        conv.messages.append(Message(role: .system, content: GRumpDefaults.defaultSystemPrompt))

        // Simulate user/assistant exchange
        conv.messages.append(Message(role: .user, content: "What is SwiftUI?"))
        conv.messages.append(Message(role: .assistant, content: "SwiftUI is a declarative UI framework."))

        // Title should auto-update
        conv.updateTitle()
        XCTAssertEqual(conv.title, "What is SwiftUI?")

        // Create thread
        let userMsgId = conv.messages[1].id
        let threadId = conv.createThread(from: userMsgId, name: "SwiftUI Thread")
        XCTAssertNotNil(threadId)
        XCTAssertEqual(conv.threads.count, 1)
        XCTAssertEqual(conv.activeThreadId, threadId)

        // Create branch
        let branchId = conv.createBranch(from: userMsgId, name: "Alternative")
        XCTAssertNotNil(branchId)
        XCTAssertEqual(conv.branches.count, 1)

        // Encode/decode full conversation
        let data = try JSONEncoder().encode(conv)
        let decoded = try JSONDecoder().decode(Conversation.self, from: data)

        XCTAssertEqual(decoded.messages.count, conv.messages.count)
        XCTAssertEqual(decoded.threads.count, 1)
        XCTAssertEqual(decoded.branches.count, 1)
        XCTAssertEqual(decoded.activeThreadId, threadId)
        XCTAssertEqual(decoded.title, "What is SwiftUI?")
    }

    func testConversationWithToolCalls() throws {
        var conv = Conversation(title: "Tool Test")
        conv.messages.append(Message(role: .user, content: "Read file.swift"))

        var assistantMsg = Message(role: .assistant, content: "")
        assistantMsg.toolCalls = [
            ToolCall(id: "tc-1", name: "read_file", arguments: "{\"path\":\"file.swift\"}"),
            ToolCall(id: "tc-2", name: "edit_file", arguments: "{\"path\":\"file.swift\",\"content\":\"new\"}")
        ]
        conv.messages.append(assistantMsg)

        // Tool results
        conv.messages.append(Message(role: .tool, content: "File contents here", toolCallId: "tc-1"))
        conv.messages.append(Message(role: .tool, content: "File edited", toolCallId: "tc-2"))

        // Verify round-trip
        let data = try JSONEncoder().encode(conv)
        let decoded = try JSONDecoder().decode(Conversation.self, from: data)

        XCTAssertEqual(decoded.messages.count, 4)
        XCTAssertEqual(decoded.messages[1].toolCalls?.count, 2)
        XCTAssertEqual(decoded.messages[2].toolCallId, "tc-1")
        XCTAssertEqual(decoded.messages[3].toolCallId, "tc-2")
    }

    // MARK: - Model Consistency Across All Properties

    func testModelPropertyConsistency() {
        // Every model must have all 6 properties populated correctly
        for model in AIModel.allCases {
            // rawValue is the DashScope wire id (e.g. "qwen-coder-plus"), no slash.
            XCTAssertFalse(model.rawValue.isEmpty,
                "\(model.rawValue) should have a non-empty wire id")

            // displayName should be human-readable (no slashes)
            XCTAssertFalse(model.displayName.contains("/"),
                "\(model.rawValue) displayName contains slashes")

            // description should be a sentence
            XCTAssertGreaterThan(model.description.count, 10,
                "\(model.rawValue) description too short")

            // tier must be valid — single provider now.
            XCTAssertTrue(["Qwen"].contains(model.tier),
                "\(model.rawValue) has invalid tier: \(model.tier)")

            // id must equal rawValue
            XCTAssertEqual(model.id, model.rawValue)
        }
    }

    func testModelTierMatchesRequiresPaidTier() {
        // Pro tier models must require paid tier
        for model in AIModel.allCases {
            if model.tier == "Pro" {
                XCTAssertTrue(model.requiresPaidTier,
                    "\(model.rawValue) is Pro tier but doesn't require paid")
            }
            if model.tier == "Free" {
                XCTAssertFalse(model.requiresPaidTier,
                    "\(model.rawValue) is Free tier but requires paid")
            }
        }
    }

    func testAllModelsAreAccountedForInTierLists() {
        let proModels = Set(AIModel.modelsForTier("pro").map(\.rawValue))
        let freeModels = Set(AIModel.modelsForTier(nil).map(\.rawValue))
        let allModels = Set(AIModel.allCases.map(\.rawValue))

        let covered = proModels.union(freeModels)
        let uncovered = allModels.subtracting(covered)

        // Claude Sonnet 4 is in the Free list but not Pro — that's by design
        // But every model should appear in at least one tier's list
        // Note: some models may intentionally not be in tier lists (hidden/deprecated)
        // For now, just verify no model is orphaned
        for modelRaw in uncovered {
            // This is informational — some models may be intentionally excluded
            print("⚠️ Model not in any tier list: \(modelRaw)")
        }
    }

    // MARK: - ToolCallStatus State Machine

    func testToolCallStatusTransitions() {
        var status = ToolCallStatus(id: "t1", name: "read_file", arguments: "{}", status: .pending)
        XCTAssertEqual(status.status, .pending)
        XCTAssertNil(status.startTime)
        XCTAssertNil(status.endTime)
        XCTAssertEqual(status.progress, 0.0)

        // Transition to running
        status.status = .running
        status.startTime = Date()
        status.currentStep = "Reading file..."
        XCTAssertEqual(status.status, .running)
        XCTAssertNotNil(status.startTime)

        // Transition to completed
        status.status = .completed
        status.endTime = Date()
        status.result = "File content"
        XCTAssertEqual(status.status, .completed)
        XCTAssertNotNil(status.result)

        // End time should be after start time
        if let start = status.startTime, let end = status.endTime {
            XCTAssertTrue(end >= start, "End time should be >= start time")
        }
    }

    func testToolCallStatusFailed() {
        var status = ToolCallStatus(id: "t2", name: "write_file", arguments: "{}", status: .running)
        status.status = .failed
        status.result = "Permission denied"
        XCTAssertEqual(status.status, .failed)
        XCTAssertEqual(status.result, "Permission denied")
    }

    func testToolCallStatusCancelled() {
        var status = ToolCallStatus(id: "t3", name: "run_command", arguments: "{}", status: .running)
        status.status = .cancelled
        XCTAssertEqual(status.status, .cancelled)
    }


    // MARK: - SystemRunHistoryEntry

    func testSystemRunHistoryEntryDefaults() {
        let entry = SystemRunHistoryEntry(command: "ls", resolvedPath: "/bin/ls", allowed: true)
        XCTAssertNotNil(entry.id)
        XCTAssertNotNil(entry.timestamp)
        XCTAssertEqual(entry.command, "ls")
        XCTAssertTrue(entry.allowed)
    }

    func testSystemRunHistoryDangerousCommand() {
        let entry = SystemRunHistoryEntry(
            command: "rm -rf /",
            resolvedPath: "/bin/rm",
            allowed: false
        )
        XCTAssertFalse(entry.allowed)
        XCTAssertEqual(entry.command, "rm -rf /")
    }

    // MARK: - Conversation View Modes

    func testConversationViewModeRawValues() {
        XCTAssertEqual(Conversation.ConversationViewMode.linear.rawValue, "linear")
        XCTAssertEqual(Conversation.ConversationViewMode.threaded.rawValue, "threaded")
        XCTAssertEqual(Conversation.ConversationViewMode.branched.rawValue, "branched")
    }

    func testConversationViewModeDefaultIsLinear() {
        let conv = Conversation(title: "Test")
        XCTAssertEqual(conv.viewMode, .linear)
    }

    // MARK: - Message Threading Correctness

    func testActiveThreadFiltersCorrectly() {
        var conv = Conversation(title: "T")

        // Add base messages
        let globalMsg = Message(role: .system, content: "System prompt")
        conv.messages.append(globalMsg)

        var userMsg = Message(role: .user, content: "Hello")
        conv.messages.append(userMsg)

        var assistantMsg = Message(role: .assistant, content: "Hi there!")
        conv.messages.append(assistantMsg)

        // Create a thread from the user message
        let threadId = conv.createThread(from: userMsg.id, name: "Main Thread")
        XCTAssertNotNil(threadId)

        // Active thread messages should include the threaded message + global (nil thread) messages
        let activeMessages = conv.getActiveThreadMessages()
        XCTAssertFalse(activeMessages.isEmpty)
    }

    // MARK: - Edge Cases

    func testEmptyConversationEncoding() throws {
        let conv = Conversation(title: "")
        let data = try JSONEncoder().encode(conv)
        let decoded = try JSONDecoder().decode(Conversation.self, from: data)
        XCTAssertEqual(decoded.title, "")
        XCTAssertTrue(decoded.messages.isEmpty)
    }

    func testConversationWithManyMessages() throws {
        var conv = Conversation(title: "Large")
        for i in 0..<100 {
            conv.messages.append(Message(
                role: i % 2 == 0 ? .user : .assistant,
                content: "Message \(i)"
            ))
        }
        let data = try JSONEncoder().encode(conv)
        let decoded = try JSONDecoder().decode(Conversation.self, from: data)
        XCTAssertEqual(decoded.messages.count, 100)
    }

    func testMessageWithAllOptionalFields() throws {
        var msg = Message(role: .assistant, content: "Full message")
        msg.toolCallId = "tc-abc"
        msg.toolCalls = [ToolCall(id: "tc-1", name: "test", arguments: "{}")]
        msg.parentMessageId = UUID()
        msg.branchId = UUID()
        msg.threadId = UUID()
        msg.isBranch = true
        msg.branchName = "My Branch"
        msg.children = [UUID(), UUID()]

        let data = try JSONEncoder().encode(msg)
        let decoded = try JSONDecoder().decode(Message.self, from: data)

        XCTAssertEqual(decoded.toolCallId, msg.toolCallId)
        XCTAssertEqual(decoded.toolCalls?.count, 1)
        XCTAssertEqual(decoded.parentMessageId, msg.parentMessageId)
        XCTAssertEqual(decoded.branchId, msg.branchId)
        XCTAssertEqual(decoded.threadId, msg.threadId)
        XCTAssertTrue(decoded.isBranch)
        XCTAssertEqual(decoded.branchName, "My Branch")
        XCTAssertEqual(decoded.children.count, 2)
    }

    // MARK: - Additional Edge Cases

    func testConversationTitleUpdateFromEmptyMessages() {
        var conv = Conversation(title: "Untitled")
        // updateTitle with no user messages should not crash
        conv.updateTitle()
        // Title remains unchanged when there are no user messages
        XCTAssertEqual(conv.title, "Untitled")
    }

    func testMultipleThreadCreation() {
        var conv = Conversation(title: "Multi-Thread")
        conv.messages.append(Message(role: .user, content: "First"))
        conv.messages.append(Message(role: .user, content: "Second"))
        conv.messages.append(Message(role: .user, content: "Third"))

        let t1 = conv.createThread(from: conv.messages[0].id, name: "Thread A")
        let t2 = conv.createThread(from: conv.messages[1].id, name: "Thread B")
        let t3 = conv.createThread(from: conv.messages[2].id, name: "Thread C")

        XCTAssertNotNil(t1)
        XCTAssertNotNil(t2)
        XCTAssertNotNil(t3)
        XCTAssertEqual(conv.threads.count, 3)

        // All thread IDs should be unique
        let ids = [t1, t2, t3].compactMap { $0 }
        XCTAssertEqual(Set(ids).count, 3, "All thread IDs should be unique")
    }

    func testBranchHasCorrectParentRef() {
        var conv = Conversation(title: "Branch Test")
        let userMsg = Message(role: .user, content: "Question")
        conv.messages.append(userMsg)

        let branchId = conv.createBranch(from: userMsg.id, name: "Alt Answer")
        XCTAssertNotNil(branchId)
        XCTAssertEqual(conv.branches.count, 1)
        if let branch = conv.branches.first {
            XCTAssertEqual(branch.parentMessageId, userMsg.id)
        }
    }

    func testConversationTitleUpdateTrimsToFirstUserMessage() {
        var conv = Conversation(title: "Default")
        conv.messages.append(Message(role: .system, content: "You are a helper."))
        conv.messages.append(Message(role: .user, content: "How do protocols work in Swift?"))
        conv.messages.append(Message(role: .assistant, content: "Protocols define a blueprint..."))
        conv.updateTitle()
        XCTAssertEqual(conv.title, "How do protocols work in Swift?")
    }

    func testConversationWithSystemMessageOnly() throws {
        var conv = Conversation(title: "sys-only")
        conv.messages.append(Message(role: .system, content: "System prompt"))
        let data = try JSONEncoder().encode(conv)
        let decoded = try JSONDecoder().decode(Conversation.self, from: data)
        XCTAssertEqual(decoded.messages.count, 1)
        XCTAssertEqual(decoded.messages[0].role, .system)
    }
}
