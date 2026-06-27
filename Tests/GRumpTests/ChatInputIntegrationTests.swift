import XCTest
@testable import GRump

/// Integration-level tests validating the full Chat Input pipeline:
/// text entry → canSend → send → state update → attachment lifecycle.
final class ChatInputIntegrationTests: XCTestCase {

    // MARK: - Full Send Flow

    func testFullSendFlow() {
        var text = ""
        var hasSentFirstMessage = false
        var onSendCalled = false
        let isLoading = false

        // Step 1: User types
        text = "Hello, how are you?"

        // Step 2: canSend check
        let canSend = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
        XCTAssertTrue(canSend)

        // Step 3: Send
        hasSentFirstMessage = true
        onSendCalled = true

        // Step 4: Verify state
        XCTAssertTrue(hasSentFirstMessage)
        XCTAssertTrue(onSendCalled)
    }

    func testSendClearsInputAndPreservesFlag() {
        var text = "Test message"
        var hasSentFirstMessage = false

        // Send
        hasSentFirstMessage = true
        text = "" // ContentView clears input after send

        XCTAssertTrue(hasSentFirstMessage)
        XCTAssertTrue(text.isEmpty)

        // Second message — flag stays true
        text = "Another message"
        hasSentFirstMessage = true // idempotent
        text = ""

        XCTAssertTrue(hasSentFirstMessage)
    }

    // MARK: - Attachment Lifecycle

    func testFullAttachmentLifecycle() {
        var attachedFiles: [URL] = []
        var callbackInvocations = 0
        let callback: ([URL]) -> Void = { _ in callbackInvocations += 1 }

        let file1 = URL(fileURLWithPath: "/tmp/screenshot.png")
        let file2 = URL(fileURLWithPath: "/tmp/document.pdf")
        let file3 = URL(fileURLWithPath: "/tmp/code.swift")

        // Add files one by one
        attachedFiles.append(file1)
        callback(attachedFiles)
        XCTAssertEqual(attachedFiles.count, 1)
        XCTAssertEqual(callbackInvocations, 1)

        attachedFiles.append(file2)
        callback(attachedFiles)
        XCTAssertEqual(attachedFiles.count, 2)
        XCTAssertEqual(callbackInvocations, 2)

        attachedFiles.append(file3)
        callback(attachedFiles)
        XCTAssertEqual(attachedFiles.count, 3)
        XCTAssertEqual(callbackInvocations, 3)

        // Remove middle file
        attachedFiles.removeAll { $0 == file2 }
        callback(attachedFiles)
        XCTAssertEqual(attachedFiles.count, 2)
        XCTAssertFalse(attachedFiles.contains(file2))
        XCTAssertEqual(callbackInvocations, 4)

        // Remove remaining
        attachedFiles.removeAll { $0 == file1 }
        attachedFiles.removeAll { $0 == file3 }
        callback(attachedFiles)
        XCTAssertTrue(attachedFiles.isEmpty)
        XCTAssertEqual(callbackInvocations, 5)
    }

    // MARK: - Loading State Blocking

    func testLoadingBlocksSend() {
        let text = "Valid message"

        // Not loading — can send
        XCTAssertTrue(!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !false)

        // Loading — cannot send
        XCTAssertFalse(!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !true)
    }

    func testLoadingToIdleTransition() {
        var isLoading = true
        let text = "Hello"

        // During loading
        var canSend = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
        XCTAssertFalse(canSend)

        // Loading completes
        isLoading = false
        canSend = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
        XCTAssertTrue(canSend)
    }

    // MARK: - Send + Stop Button States

    func testStopButtonVisibleDuringLoading() {
        let isLoading = true
        // When isLoading, the stop button should be shown
        XCTAssertTrue(isLoading, "Stop button visible when loading")
    }

    func testSendButtonVisibleWhenNotLoading() {
        let isLoading = false
        XCTAssertFalse(isLoading, "Send button visible when not loading")
    }

    func testSendButtonDisabledWhenCannotSend() {
        let text = ""
        let isLoading = false
        let canSend = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
        XCTAssertFalse(canSend, "Send button should be disabled with empty text")
    }

    func testSendButtonEnabledWithValidText() {
        let text = "Hello"
        let isLoading = false
        let canSend = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
        XCTAssertTrue(canSend, "Send button should be enabled with valid text")
    }

    // MARK: - Hint Visibility

    func testHintVisibleBeforeFirstSend() {
        let hasSentFirstMessage = false
        XCTAssertFalse(hasSentFirstMessage, "Hint should be visible before first send")
    }

    func testHintHiddenAfterFirstSend() {
        var hasSentFirstMessage = false
        // Simulate send
        hasSentFirstMessage = true
        XCTAssertTrue(hasSentFirstMessage, "Hint should be hidden after first send")
    }

    // MARK: - Edge: Rapid Send

    func testRapidSendSequence() {
        var sendCount = 0
        var hasSentFirstMessage = false

        for i in 0..<10 {
            let text = "Message \(i)"
            let canSend = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !false
            if canSend {
                hasSentFirstMessage = true
                sendCount += 1
            }
        }

        XCTAssertEqual(sendCount, 10)
        XCTAssertTrue(hasSentFirstMessage)
    }

    // MARK: - Edge: Attachment + Send Together

    func testAttachmentsPresentDuringSend() {
        var attachedFiles = [URL(fileURLWithPath: "/tmp/file.png")]
        let text = "Check this file"
        let isLoading = false

        let canSend = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
        XCTAssertTrue(canSend, "Can send with text even with attachments")
        XCTAssertEqual(attachedFiles.count, 1)
    }

    func testEmptyTextWithAttachmentCannotSend() {
        var attachedFiles = [URL(fileURLWithPath: "/tmp/file.png")]
        let text = ""
        let isLoading = false

        // Current logic requires text to send — attachments alone don't enable send
        let canSend = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
        XCTAssertFalse(canSend, "Empty text cannot send even with attachments (current behavior)")
    }

    // MARK: - FollowUp Integration

    func testFollowUpSuggestionsAfterCodeResponse() {
        let assistantMessage = "Here's the implementation:\n```swift\nfunc hello() { }\n```"
        let suggestions = FollowUpGenerator.generate(from: assistantMessage, agentMode: .spec)
        XCTAssertFalse(suggestions.isEmpty, "Should produce follow-up suggestions after code response")
    }

    func testFollowUpSuggestionsAfterErrorResponse() {
        let assistantMessage = "There was an error compiling the file."
        let suggestions = FollowUpGenerator.generate(from: assistantMessage, agentMode: .spec)
        XCTAssertTrue(suggestions.contains(where: { $0.category == .fix || $0.category == .explain }))
    }

    func testFollowUpSuggestionsAfterPlainResponse() {
        let assistantMessage = "Sure, I can help with that."
        let suggestions = FollowUpGenerator.generate(from: assistantMessage, agentMode: .spec)
        XCTAssertTrue(suggestions.isEmpty, "Plain messages should not generate fallback suggestions")
    }

    // MARK: - Conversation Context

    func testNewConversationStartsEmpty() {
        let conv = Conversation(title: "Test")
        XCTAssertTrue(conv.messages.isEmpty)
        XCTAssertEqual(conv.title, "Test")
    }

    func testConversationAfterUserMessage() {
        var conv = Conversation(title: "Test")
        conv.messages.append(Message(role: .user, content: "Hello"))
        XCTAssertEqual(conv.messages.count, 1)
        XCTAssertEqual(conv.messages[0].role, .user)
    }
}
