import XCTest
@testable import GRump

/// Tests for the streaming lifecycle in `ChatViewModel+Streaming`.
/// Covers stop, pause, resume, restart, and state-reset behaviors.
@MainActor
final class ChatStreamingTests: XCTestCase {

    // MARK: - Helpers

    private func makeViewModel() -> ChatViewModel {
        let vm = ChatViewModel()
        vm.createNewConversation()
        return vm
    }

    // MARK: - Stop Generation

    func testStopGenerationClearsLoadingState() {
        let vm = makeViewModel()
        vm.isLoading = true
        vm.isPaused = false

        vm.stopGeneration()

        XCTAssertFalse(vm.isLoading, "stopGeneration should clear isLoading")
        XCTAssertFalse(vm.isPaused, "stopGeneration should clear isPaused")
    }

    func testStopGenerationWhenNotLoading() {
        let vm = makeViewModel()
        vm.isLoading = false

        vm.stopGeneration()

        XCTAssertFalse(vm.isLoading, "stopGeneration should be safe to call when not loading")
    }

    // MARK: - Pause Generation

    func testPauseGenerationSetsCorrectState() {
        let vm = makeViewModel()
        vm.isLoading = true

        vm.pauseGeneration()

        XCTAssertFalse(vm.isLoading, "pauseGeneration should clear isLoading")
        XCTAssertTrue(vm.isPaused, "pauseGeneration should set isPaused")
    }

    func testPauseWhenAlreadyPaused() {
        let vm = makeViewModel()
        vm.isPaused = true
        vm.isLoading = false

        vm.pauseGeneration()

        XCTAssertTrue(vm.isPaused, "Should remain paused")
        XCTAssertFalse(vm.isLoading)
    }

    // MARK: - Resume Agent

    func testResumeAgentRequiresPausedState() {
        let vm = makeViewModel()
        vm.isPaused = false

        vm.resumeAgent()

        XCTAssertFalse(vm.isLoading, "Resume should not start loading when not paused")
    }

    func testResumeAgentRequiresConversation() {
        let vm = makeViewModel()
        vm.isPaused = true
        vm.currentConversation = nil

        vm.resumeAgent()

        XCTAssertFalse(vm.isLoading, "Resume should not start loading without a conversation")
    }

    func testResumeAgentFromPausedState() {
        let vm = makeViewModel()
        vm.isPaused = true
        vm.currentConversation = Conversation(title: "Test")

        vm.resumeAgent()

        XCTAssertTrue(vm.isLoading, "Resume should set isLoading when properly paused")
        XCTAssertFalse(vm.isPaused, "Resume should clear isPaused")
        XCTAssertEqual(vm.streamingContent, "", "Resume should clear streamingContent")
        XCTAssertTrue(vm.activeToolCalls.isEmpty, "Resume should clear activeToolCalls")

        // Clean up
        vm.stopGeneration()
    }

    // MARK: - State Reset Consistency

    func testStopThenPauseSequence() {
        let vm = makeViewModel()
        vm.isLoading = true

        vm.stopGeneration()
        XCTAssertFalse(vm.isLoading)
        XCTAssertFalse(vm.isPaused)

        vm.pauseGeneration()
        // Should still be safe; isPaused becomes true
        XCTAssertTrue(vm.isPaused)
    }

    func testMultipleStopCallsAreSafe() {
        let vm = makeViewModel()
        vm.isLoading = true

        vm.stopGeneration()
        vm.stopGeneration()
        vm.stopGeneration()

        XCTAssertFalse(vm.isLoading, "Multiple stops should be idempotent")
    }

    // MARK: - Streaming Content State

    func testStreamingContentInitiallyEmpty() {
        let vm = makeViewModel()
        XCTAssertEqual(vm.streamingContent, "", "Streaming content should start empty")
    }

    func testActiveToolCallsInitiallyEmpty() {
        let vm = makeViewModel()
        XCTAssertTrue(vm.activeToolCalls.isEmpty, "Active tool calls should start empty")
    }

    func testErrorMessageInitiallyNil() {
        let vm = makeViewModel()
        XCTAssertNil(vm.errorMessage, "Error message should start nil")
    }

    // MARK: - Stream Metrics

    func testStreamMetricsExist() {
        let vm = makeViewModel()
        XCTAssertNotNil(vm.streamMetrics, "StreamMetrics should be initialized")
    }

    // MARK: - Agent Mode Routing

    func testIsSimpleConversationalMessageDetectsGreetings() {
        let vm = makeViewModel()

        XCTAssertTrue(vm.isSimpleConversationalMessage("hello"),
                      "Greetings should be detected as simple conversational messages")
        XCTAssertTrue(vm.isSimpleConversationalMessage("thanks!"),
                      "Thanks should be detected as simple")
        XCTAssertTrue(vm.isSimpleConversationalMessage("yes"),
                      "Short affirmatives should be simple")
    }

    func testIsSimpleConversationalMessageRejectsCodeRequests() {
        let vm = makeViewModel()

        XCTAssertFalse(vm.isSimpleConversationalMessage("Write a function that sorts an array"),
                       "Code requests should not be simple")
        XCTAssertFalse(vm.isSimpleConversationalMessage("Fix the bug in auth.swift and add tests"),
                       "Complex tasks should not be simple")
    }

    // MARK: - Code Changes Tracking

    func testCurrentRunCodeChangesInitiallyEmpty() {
        let vm = makeViewModel()
        XCTAssertTrue(vm.currentRunCodeChanges.isEmpty)
    }
}
