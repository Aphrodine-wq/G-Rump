import XCTest
@testable import GRump

final class ModelsTests: XCTestCase {

    func testMessageCodableRoundTrip() throws {
        let msg = Message(role: .user, content: "Hello", timestamp: Date())
        let data = try JSONEncoder().encode(msg)
        let decoded = try JSONDecoder().decode(Message.self, from: data)
        XCTAssertEqual(decoded.role, msg.role)
        XCTAssertEqual(decoded.content, msg.content)
    }

    func testConversationCodableRoundTrip() throws {
        var conv = Conversation(title: "Test")
        conv.messages = [
            Message(role: .user, content: "Hi"),
            Message(role: .assistant, content: "Hello!"),
        ]
        let data = try JSONEncoder().encode(conv)
        let decoded = try JSONDecoder().decode(Conversation.self, from: data)
        XCTAssertEqual(decoded.title, conv.title)
        XCTAssertEqual(decoded.messages.count, 2)
        XCTAssertEqual(decoded.messages[0].content, "Hi")
        XCTAssertEqual(decoded.messages[1].content, "Hello!")
    }

    func testConversationUpdateTitle() {
        var conv = Conversation(title: "New Chat")
        conv.messages.append(Message(role: .user, content: "What is Swift?"))
        conv.updateTitle()
        XCTAssertEqual(conv.title, "What is Swift?")
    }

    func testConversationUpdateTitleTruncates() {
        var conv = Conversation(title: "New Chat")
        let long = String(repeating: "a", count: 50)
        conv.messages.append(Message(role: .user, content: long))
        conv.updateTitle()
        XCTAssertEqual(conv.title.count, 41)
        XCTAssertTrue(conv.title.hasSuffix("…"))
    }

    // MARK: - Message Expanded

    func testAllMessageRoles() {
        let roles: [Message.Role] = [.user, .assistant, .system, .tool]
        XCTAssertEqual(roles.count, 4)
        for role in roles {
            let msg = Message(role: role, content: "test")
            XCTAssertEqual(msg.role, role)
        }
    }

    func testMessageDefaultValues() {
        let msg = Message(role: .user, content: "hi")
        XCTAssertNotNil(msg.id)
        XCTAssertNotNil(msg.timestamp)
        XCTAssertNil(msg.toolCallId)
        XCTAssertNil(msg.toolCalls)
        XCTAssertNil(msg.parentMessageId)
        XCTAssertNil(msg.branchId)
        XCTAssertNil(msg.threadId)
        XCTAssertFalse(msg.isBranch)
        XCTAssertNil(msg.branchName)
        XCTAssertTrue(msg.children.isEmpty)
    }

    func testMessageWithToolCalls() throws {
        var msg = Message(role: .assistant, content: "Using tools")
        msg.toolCalls = [
            ToolCall(id: "tc1", name: "read_file", arguments: "{\"path\":\"/a.swift\"}")
        ]
        let data = try JSONEncoder().encode(msg)
        let decoded = try JSONDecoder().decode(Message.self, from: data)
        XCTAssertEqual(decoded.toolCalls?.count, 1)
        XCTAssertEqual(decoded.toolCalls?.first?.name, "read_file")
    }

    func testMessageEquatable() {
        let id = UUID()
        let ts = Date()
        let a = Message(id: id, role: .user, content: "hi", timestamp: ts)
        let b = Message(id: id, role: .user, content: "hi", timestamp: ts)
        XCTAssertEqual(a, b)
    }

    func testMessageEmptyContent() {
        let msg = Message(role: .user, content: "")
        XCTAssertTrue(msg.content.isEmpty)
    }

    func testMessageRoleCodable() throws {
        for role in [Message.Role.user, .assistant, .system, .tool] {
            let data = try JSONEncoder().encode(role)
            let decoded = try JSONDecoder().decode(Message.Role.self, from: data)
            XCTAssertEqual(decoded, role)
        }
    }

    // MARK: - ToolCall

    func testToolCallCreation() {
        let tc = ToolCall(id: "tc-1", name: "write_file", arguments: "{}")
        XCTAssertEqual(tc.id, "tc-1")
        XCTAssertEqual(tc.name, "write_file")
        XCTAssertEqual(tc.arguments, "{}")
    }

    func testToolCallCodable() throws {
        let tc = ToolCall(id: "tc-2", name: "run_command", arguments: "{\"cmd\":\"ls\"}")
        let data = try JSONEncoder().encode(tc)
        let decoded = try JSONDecoder().decode(ToolCall.self, from: data)
        XCTAssertEqual(decoded.id, tc.id)
        XCTAssertEqual(decoded.name, tc.name)
        XCTAssertEqual(decoded.arguments, tc.arguments)
    }

    func testToolCallEquatable() {
        let a = ToolCall(id: "x", name: "y", arguments: "z")
        let b = ToolCall(id: "x", name: "y", arguments: "z")
        XCTAssertEqual(a, b)
    }

    // MARK: - ToolCallStatus

    func testToolCallStatusCreation() {
        let status = ToolCallStatus(
            id: "s1", name: "read_file", arguments: "{}",
            status: .running, result: nil
        )
        XCTAssertEqual(status.id, "s1")
        XCTAssertEqual(status.name, "read_file")
        XCTAssertEqual(status.status, .running)
        XCTAssertNil(status.result)
    }

    func testToolCallStatusAllStates() {
        let states: [ToolCallStatus.ToolRunStatus] = [.pending, .running, .completed, .failed, .cancelled]
        XCTAssertEqual(states.count, 5)
    }

    func testToolCallStatusCompleted() {
        let status = ToolCallStatus(
            id: "s2", name: "run_command", arguments: "{}",
            status: .completed, result: "Success"
        )
        XCTAssertEqual(status.status, .completed)
        XCTAssertEqual(status.result, "Success")
    }

    // MARK: - SystemRunHistoryEntry

    func testSystemRunHistoryEntryCreation() {
        let entry = SystemRunHistoryEntry(
            command: "swift build",
            resolvedPath: "/usr/bin/swift",
            allowed: true
        )
        XCTAssertEqual(entry.command, "swift build")
        XCTAssertEqual(entry.resolvedPath, "/usr/bin/swift")
        XCTAssertTrue(entry.allowed)
        XCTAssertNotNil(entry.id)
    }

    func testSystemRunHistoryEntryDenied() {
        let entry = SystemRunHistoryEntry(
            command: "rm -rf /",
            resolvedPath: "/bin/rm",
            allowed: false
        )
        XCTAssertFalse(entry.allowed)
    }

    // MARK: - Conversation Expanded

    func testConversationDefaults() {
        let conv = Conversation(title: "Test")
        XCTAssertNotNil(conv.id)
        XCTAssertEqual(conv.title, "Test")
        XCTAssertTrue(conv.messages.isEmpty)
        XCTAssertTrue(conv.threads.isEmpty)
        XCTAssertTrue(conv.branches.isEmpty)
        XCTAssertNil(conv.activeThreadId)
        XCTAssertEqual(conv.viewMode, .linear)
    }

    func testConversationViewModes() {
        let modes = Conversation.ConversationViewMode.allCases
        XCTAssertEqual(modes.count, 3)
        XCTAssertTrue(modes.contains(.linear))
        XCTAssertTrue(modes.contains(.threaded))
        XCTAssertTrue(modes.contains(.branched))
    }

    func testConversationViewModeCodable() throws {
        for mode in Conversation.ConversationViewMode.allCases {
            let data = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(Conversation.ConversationViewMode.self, from: data)
            XCTAssertEqual(decoded, mode)
        }
    }

    func testConversationUpdateTitleNoUserMessage() {
        var conv = Conversation(title: "Original")
        conv.messages.append(Message(role: .assistant, content: "Hello!"))
        conv.updateTitle()
        XCTAssertEqual(conv.title, "Original", "Title should not change without user messages")
    }

    func testConversationUpdateTitleShortMessage() {
        var conv = Conversation(title: "New Chat")
        conv.messages.append(Message(role: .user, content: "Hi"))
        conv.updateTitle()
        XCTAssertEqual(conv.title, "Hi")
    }

    func testConversationEquatable() {
        // A value copy must be equal. (Two separate inits differ by sub-second
        // createdAt/updatedAt timestamps, so don't construct b independently.)
        let a = Conversation(id: UUID(), title: "T")
        let b = a
        XCTAssertEqual(a, b)
    }

    func testConversationGetActiveThreadMessagesDefault() {
        var conv = Conversation(title: "T")
        conv.messages = [
            Message(role: .user, content: "a"),
            Message(role: .assistant, content: "b"),
        ]
        let active = conv.getActiveThreadMessages()
        XCTAssertEqual(active.count, 2, "With no active thread, all messages returned")
    }

    func testConversationCreateThread() {
        var conv = Conversation(title: "T")
        let msg = Message(role: .user, content: "Start thread")
        conv.messages.append(msg)
        let threadId = conv.createThread(from: msg.id, name: "Thread 1")
        XCTAssertNotNil(threadId)
        XCTAssertEqual(conv.threads.count, 1)
        XCTAssertEqual(conv.activeThreadId, threadId)
    }

    func testConversationCreateThreadInvalidMessage() {
        var conv = Conversation(title: "T")
        let threadId = conv.createThread(from: UUID())
        XCTAssertNil(threadId, "Should return nil for nonexistent message")
    }

    func testConversationCreateBranch() {
        var conv = Conversation(title: "T")
        let msg = Message(role: .user, content: "Branch point")
        conv.messages.append(msg)
        let branchId = conv.createBranch(from: msg.id, name: "Alt Path")
        XCTAssertNotNil(branchId)
        XCTAssertEqual(conv.branches.count, 1)
        XCTAssertEqual(conv.branches.first?.name, "Alt Path")
    }

    func testConversationCreateBranchInvalidMessage() {
        var conv = Conversation(title: "T")
        let branchId = conv.createBranch(from: UUID(), name: "X")
        XCTAssertNil(branchId)
    }

    // MARK: - MessageThread

    func testMessageThreadCreation() {
        let rootId = UUID()
        let thread = MessageThread(name: "My Thread", rootMessageId: rootId)
        XCTAssertNotNil(thread.id)
        XCTAssertEqual(thread.name, "My Thread")
        XCTAssertEqual(thread.rootMessageId, rootId)
        XCTAssertTrue(thread.isActive)
    }

    func testMessageThreadCodable() throws {
        let thread = MessageThread(name: "T", rootMessageId: UUID())
        let data = try JSONEncoder().encode(thread)
        let decoded = try JSONDecoder().decode(MessageThread.self, from: data)
        XCTAssertEqual(decoded.id, thread.id)
        XCTAssertEqual(decoded.name, thread.name)
    }

    // MARK: - MessageBranch

    func testMessageBranchCreation() {
        let pid = UUID()
        let bpid = UUID()
        let branch = MessageBranch(name: "Alt", parentMessageId: pid, branchPointMessageId: bpid)
        XCTAssertNotNil(branch.id)
        XCTAssertEqual(branch.name, "Alt")
        XCTAssertEqual(branch.parentMessageId, pid)
        XCTAssertEqual(branch.branchPointMessageId, bpid)
        XCTAssertTrue(branch.isActive)
    }

    func testMessageBranchCodable() throws {
        let branch = MessageBranch(name: "B", parentMessageId: UUID(), branchPointMessageId: UUID())
        let data = try JSONEncoder().encode(branch)
        let decoded = try JSONDecoder().decode(MessageBranch.self, from: data)
        XCTAssertEqual(decoded.id, branch.id)
        XCTAssertEqual(decoded.name, branch.name)
    }

    // MARK: - AIModel Properties

    func testAllAIModelsHaveDisplayNames() {
        for model in AIModel.allCases {
            XCTAssertFalse(model.displayName.isEmpty, "\(model.rawValue) has empty displayName")
        }
    }

    func testAllAIModelsHaveDescriptions() {
        for model in AIModel.allCases {
            XCTAssertFalse(model.description.isEmpty, "\(model.rawValue) has empty description")
        }
    }

    func testAllAIModelsHaveContextWindows() {
        for model in AIModel.allCases {
            XCTAssertGreaterThan(model.contextWindow, 0, "\(model.rawValue) has 0 context window")
        }
    }

    func testAllAIModelsHaveMaxOutput() {
        for model in AIModel.allCases {
            XCTAssertGreaterThan(model.maxOutput, 0, "\(model.rawValue) has 0 max output")
        }
    }

    func testMaxOutputLessThanContextWindow() {
        for model in AIModel.allCases {
            XCTAssertLessThan(model.maxOutput, model.contextWindow,
                "\(model.rawValue) maxOutput should be less than contextWindow")
        }
    }

    func testAIModelTiers() {
        let tiers = Set(AIModel.allCases.map(\.tier))
        XCTAssertTrue(tiers.contains("Pro"))
        XCTAssertTrue(tiers.contains("Fast"))
        XCTAssertTrue(tiers.contains("Free"))
    }

    func testPaidModelsRequirePaidTier() {
        let paid: [AIModel] = [.claudeOpus46, .gemini31Pro, .claudeSonnet46, .codex53, .kimiK25]
        for model in paid {
            XCTAssertTrue(model.requiresPaidTier, "\(model.rawValue) should require paid tier")
        }
    }

    func testFreeModelsDoNotRequirePaidTier() {
        let free: [AIModel] = [.qwen3Coder, .deepseekR1, .gptOss120b, .trinityLarge, .step35Flash, .llama33, .glm45Air]
        for model in free {
            XCTAssertFalse(model.requiresPaidTier, "\(model.rawValue) should not require paid tier")
        }
    }

    func testModelsForPaidTier() {
        let proModels = AIModel.modelsForTier("pro")
        XCTAssertTrue(proModels.contains(.claudeOpus46))
        XCTAssertTrue(proModels.contains(.gemini31Pro))
    }

    func testModelsForTeamTier() {
        let teamModels = AIModel.modelsForTier("team")
        XCTAssertTrue(teamModels.contains(.claudeOpus46))
    }

    func testModelsForFreeTier() {
        let freeModels = AIModel.modelsForTier(nil)
        XCTAssertTrue(freeModels.contains(.qwen3Coder))
        XCTAssertFalse(freeModels.contains(.claudeOpus46))
    }

    func testDefaultForTierPaid() {
        let model = AIModel.defaultForTier("pro")
        XCTAssertNotNil(model)
        XCTAssertTrue(model.requiresPaidTier)
    }

    func testDefaultForTierFree() {
        let model = AIModel.defaultForTier(nil)
        XCTAssertFalse(model.requiresPaidTier)
    }

    // MARK: - Legacy Migration

    func testMigrateLegacyGeminiPro() {
        let result = AIModel.migrateLegacyID("google/gemini-2.5-pro-preview")
        XCTAssertEqual(result, .gemini31Pro)
    }

    func testMigrateLegacyGeminiFlash() {
        let result = AIModel.migrateLegacyID("google/gemini-2.5-flash-preview")
        XCTAssertEqual(result, .gemini31Flash)
    }

    func testMigrateLegacyValidCurrent() {
        let result = AIModel.migrateLegacyID(AIModel.claudeSonnet4.rawValue)
        XCTAssertEqual(result, .claudeSonnet4)
    }

    func testMigrateLegacyUnknown() {
        let result = AIModel.migrateLegacyID("unknown/model-xyz")
        XCTAssertNil(result)
    }

    // MARK: - AIModel Identifiable

    func testAIModelIdentifiable() {
        for model in AIModel.allCases {
            XCTAssertEqual(model.id, model.rawValue)
        }
    }

    // MARK: - ParallelAgentState

    func testParallelAgentStateCreation() {
        let state = ParallelAgentState(
            id: "agent-1",
            agentIndex: 1,
            taskDescription: "Read files",
            taskType: .fileOps,
            modelName: "Qwen3 Coder"
        )
        XCTAssertEqual(state.id, "agent-1")
        XCTAssertEqual(state.agentIndex, 1)
        XCTAssertEqual(state.taskType, .fileOps)
        XCTAssertEqual(state.status, .pending)
        XCTAssertTrue(state.streamingText.isEmpty)
        XCTAssertNil(state.result)
    }

    // MARK: - ToolCallStatus Progress

    func testToolCallStatusProgress() {
        var status = ToolCallStatus(
            id: "s1", name: "read_file", arguments: "{}",
            status: .running
        )
        XCTAssertEqual(status.progress, 0.0)
        status.progress = 0.5
        XCTAssertEqual(status.progress, 0.5)
    }

    func testToolCallStatusSteps() {
        var status = ToolCallStatus(
            id: "s1", name: "multi_step", arguments: "{}",
            status: .running
        )
        XCTAssertEqual(status.totalSteps, 1)
        XCTAssertEqual(status.currentStepNumber, 0)
        status.totalSteps = 5
        status.currentStepNumber = 3
        status.currentStep = "Processing"
        XCTAssertEqual(status.currentStep, "Processing")
    }

    func testToolCallStatusTiming() {
        var status = ToolCallStatus(
            id: "s1", name: "t", arguments: "{}",
            status: .running
        )
        XCTAssertNil(status.startTime)
        status.startTime = Date()
        XCTAssertNotNil(status.startTime)
    }

    // MARK: - GRumpDefaults

    func testDefaultSystemPromptNotEmpty() {
        XCTAssertFalse(GRumpDefaults.defaultSystemPrompt.isEmpty)
    }

    func testDefaultSystemPromptContainsCoreIdentity() {
        XCTAssertTrue(GRumpDefaults.defaultSystemPrompt.contains("G-Rump"))
    }

    func testDefaultSystemPromptContainsToolGuidance() {
        XCTAssertTrue(GRumpDefaults.defaultSystemPrompt.contains("Tool Usage"))
    }

    // MARK: - Conversation Multiple Threads

    func testConversationMultipleThreads() {
        var conv = Conversation(title: "T")
        let msg1 = Message(role: .user, content: "First")
        let msg2 = Message(role: .user, content: "Second")
        conv.messages = [msg1, msg2]

        let t1 = conv.createThread(from: msg1.id, name: "Thread A")
        let t2 = conv.createThread(from: msg2.id, name: "Thread B")
        XCTAssertNotNil(t1)
        XCTAssertNotNil(t2)
        XCTAssertEqual(conv.threads.count, 2)
        // Active thread should be the last one created
        XCTAssertEqual(conv.activeThreadId, t2)
    }

    func testConversationMultipleBranches() {
        var conv = Conversation(title: "T")
        let msg = Message(role: .user, content: "Branch point")
        conv.messages = [msg]

        let b1 = conv.createBranch(from: msg.id, name: "Branch A")
        let b2 = conv.createBranch(from: msg.id, name: "Branch B")
        XCTAssertNotNil(b1)
        XCTAssertNotNil(b2)
        XCTAssertEqual(conv.branches.count, 2)
    }
}
