import XCTest
@testable import GRump

/// Covers the context-keeper work: pinned task framing + orphan-tool guard
/// in truncateMessages, the pure compaction cut-point, and buildAPIMessages'
/// consumption of compaction state.
@MainActor
final class ContextKeeperTests: XCTestCase {

    private func longText(_ label: String, chars: Int = 2_000) -> String {
        String(repeating: "\(label) ", count: max(1, chars / (label.count + 1)))
    }

    // MARK: - truncateMessages: pinning

    func testFirstUserMessagePinnedWhenTruncationWouldDropIt() {
        let vm = ChatViewModel()
        var msgs: [Message] = [Message(role: .user, content: "ORIGINAL TASK: build the widget")]
        for i in 0..<40 {
            msgs.append(Message(role: .assistant, content: longText("assistant-\(i)")))
            msgs.append(Message(role: .user, content: longText("user-\(i)")))
        }
        let result = vm.truncateMessages(msgs, targetTokens: 3_000)
        XCTAssertTrue(result.contains { $0.content.contains("ORIGINAL TASK") },
                      "the task framing must survive truncation")
        XCTAssertTrue(result.contains { $0.content.contains("[Agent notice]") && $0.content.contains("omitted") },
                      "a drop note should be present")
        let notes = result.filter { $0.content.contains("omitted") }
        XCTAssertEqual(notes.first?.role, .user, "drop note must be user-role (system would bust the prompt cache)")
    }

    func testPinnedMessageNotDuplicatedWhenItSurvives() {
        let vm = ChatViewModel()
        let msgs: [Message] = [
            Message(role: .user, content: "short task"),
            Message(role: .assistant, content: "short answer"),
        ]
        let result = vm.truncateMessages(msgs, targetTokens: 100_000)
        XCTAssertEqual(result.filter { $0.content == "short task" }.count, 1)
    }

    // MARK: - truncateMessages: orphan-tool guard

    func testLeadingOrphanToolResultsAreDropped() {
        let vm = ChatViewModel()
        var msgs: [Message] = [Message(role: .user, content: longText("task", chars: 4_000))]
        // A big assistant tool_use turn whose results follow.
        msgs.append(Message(role: .assistant, content: longText("thinking", chars: 30_000),
                            toolCalls: [ToolCall(id: "t1", name: "read_file", arguments: "{}")]))
        msgs.append(Message(role: .tool, content: "tool output", toolCallId: "t1"))
        msgs.append(Message(role: .user, content: "follow-up"))
        msgs.append(Message(role: .assistant, content: "done"))

        // Budget sized so the backwards walk keeps the tool result but not
        // its huge assistant parent.
        let result = vm.truncateMessages(msgs, targetTokens: 1_500)
        if let firstNonNote = result.first(where: { !$0.content.contains("[Agent notice]") && $0.role != .system }) {
            XCTAssertNotEqual(firstNonNote.role, .tool,
                              "window must never start with an orphaned tool_result")
        }
        for (idx, msg) in result.enumerated() where msg.role == .tool {
            let prior = result[..<idx]
            XCTAssertTrue(prior.contains { ($0.toolCalls ?? []).contains { $0.id == msg.toolCallId } },
                          "every tool_result needs its tool_use parent in the window")
        }
    }

    // MARK: - Compaction cut point (pure)

    func testCompactionCutLandsOnUserMessage() {
        // roles: U A T U A T U A  (tokens 100 each)
        let tokens = Array(repeating: 100, count: 8)
        let users = [true, false, false, true, false, false, true, false]
        let cut = ChatViewModel.compactionCutIndex(
            tokenCounts: tokens, isUserMessage: users, startIndex: 0, targetTokens: 250)
        XCTAssertEqual(cut, 3, "first user-message index after covering the target")
    }

    func testCompactionCutRespectsTail() {
        // Would want to cut at index 6, but that's within the last two.
        let tokens = Array(repeating: 100, count: 7)
        let users = [true, false, false, false, false, false, true]
        XCTAssertNil(ChatViewModel.compactionCutIndex(
            tokenCounts: tokens, isUserMessage: users, startIndex: 0, targetTokens: 550),
            "never compact into the final two messages")
    }

    func testCompactionCutHonorsStartIndex() {
        let tokens = Array(repeating: 100, count: 10)
        let users = (0..<10).map { $0 % 2 == 0 }
        let cut = ChatViewModel.compactionCutIndex(
            tokenCounts: tokens, isUserMessage: users, startIndex: 4, targetTokens: 150)
        XCTAssertNotNil(cut)
        XCTAssertGreaterThan(cut ?? -1, 4)
    }

    func testCompactionCutNilOnMismatchedInput() {
        XCTAssertNil(ChatViewModel.compactionCutIndex(
            tokenCounts: [1, 2], isUserMessage: [true], startIndex: 0, targetTokens: 1))
        XCTAssertNil(ChatViewModel.compactionCutIndex(
            tokenCounts: [], isUserMessage: [], startIndex: 0, targetTokens: 1))
    }

    // MARK: - buildAPIMessages consumes compaction state

    func testBuildAPIMessagesEmitsSummaryAndTail() {
        let vm = ChatViewModel()
        vm.createNewConversation()
        vm.currentConversation?.messages = [
            Message(role: .user, content: "the original ask"),
            Message(role: .assistant, content: "old work 1"),
            Message(role: .user, content: "old steer"),
            Message(role: .assistant, content: "old work 2"),
            Message(role: .user, content: "recent question"),
            Message(role: .assistant, content: "recent answer"),
        ]
        vm.compactionSummary = "Did X, changed a.swift, constraint Y discovered."
        vm.compactionCutoffIndex = 4

        let api = vm.buildAPIMessages(cachedPrompt: "sys")
        let contents = api.map(\.content)
        XCTAssertTrue(contents.contains { $0.contains("the original ask") }, "pinned framing emitted")
        XCTAssertTrue(contents.contains { $0.contains("Summary of earlier progress") }, "summary note emitted")
        XCTAssertTrue(contents.contains { $0.contains("recent question") }, "live tail preserved")
        XCTAssertFalse(contents.contains { $0.contains("old work 1") }, "compacted turns replaced by summary")
    }

    func testResetCompactionStateOnNewConversation() {
        let vm = ChatViewModel()
        vm.compactionSummary = "stale"
        vm.compactionCutoffIndex = 9
        vm.createNewConversation()
        XCTAssertNil(vm.compactionSummary)
        XCTAssertEqual(vm.compactionCutoffIndex, 0)
    }
}
