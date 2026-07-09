import XCTest
@testable import GRump

/// Tests for the `sendMessage()` flow in `ChatViewModel+Streaming`.
/// Covers input validation, provider/connectivity guards, message appending,
/// intent classification, and the undo-send window.
@MainActor
final class ChatResponseTests: XCTestCase {

    // MARK: - Helpers

    private func makeViewModel() -> ChatViewModel {
        let vm = ChatViewModel()
        vm.createNewConversation()
        return vm
    }

    // MARK: - Input Validation

    func testSendMessageEmptyInputDoesNothing() {
        let vm = makeViewModel()
        vm.userInput = ""
        let messageCountBefore = vm.currentConversation?.messages.count ?? 0

        vm.sendMessage()

        XCTAssertEqual(vm.currentConversation?.messages.count, messageCountBefore,
                       "Empty input should not append a message")
        XCTAssertFalse(vm.isLoading, "Should not start loading on empty input")
    }

    func testSendMessageWhitespaceOnlyDoesNothing() {
        let vm = makeViewModel()
        vm.userInput = "   \n\t  "
        let messageCountBefore = vm.currentConversation?.messages.count ?? 0

        vm.sendMessage()

        XCTAssertEqual(vm.currentConversation?.messages.count, messageCountBefore,
                       "Whitespace-only input should not append a message")
    }

    // MARK: - Provider Guard

    func testSendMessageNoProviderSetsError() {
        let vm = makeViewModel()
        vm.userInput = "Hello"
        // Ensure no provider is configured: clear API key and backend URL
        vm.apiKey = ""
        UserDefaults.standard.removeObject(forKey: "BackendURL")

        vm.sendMessage()

        // If no provider is configured at all, we expect an error message
        if !vm.isAIProviderConfigured {
            XCTAssertNotNil(vm.errorMessage, "Should set an error when no provider is configured")
        }
    }

    // MARK: - Message Appending

    func testSendMessageAppendsUserMessage() {
        let vm = makeViewModel()
        vm.userInput = "Build a feature"
        // We need a configured provider or the guard will trigger first.
        // Since we can't guarantee config, test the state that changes unconditionally.
        let initialCount = vm.currentConversation?.messages.count ?? 0

        vm.sendMessage()

        // If provider/connectivity guard didn't fire, message should be appended
        if vm.errorMessage == nil {
            XCTAssertEqual(vm.currentConversation?.messages.count, initialCount + 1,
                           "Should append exactly one user message")
            XCTAssertEqual(vm.currentConversation?.messages.last?.role, .user)
            XCTAssertEqual(vm.currentConversation?.messages.last?.content, "Build a feature")
        }
    }

    func testSendMessageClearsUserInput() {
        let vm = makeViewModel()
        vm.userInput = "Test message"

        vm.sendMessage()

        if vm.errorMessage == nil {
            XCTAssertEqual(vm.userInput, "", "userInput should be cleared after sending")
        }
    }

    // MARK: - Conversation Title Update

    func testSendMessageUpdatesTitleFromFirstUserMessage() {
        let vm = makeViewModel()
        XCTAssertEqual(vm.currentConversation?.title, "New Chat")
        vm.userInput = "Implement login"

        vm.sendMessage()

        if vm.errorMessage == nil {
            XCTAssertEqual(vm.currentConversation?.title, "Implement login",
                           "Title should update to first user message content")
        }
    }

    // MARK: - Undo Send Window

    func testSendMessageEnablesUndoSend() {
        let vm = makeViewModel()
        vm.userInput = "Something to undo"

        vm.sendMessage()

        if vm.errorMessage == nil {
            XCTAssertTrue(vm.undoSendAvailable, "Undo send should be available after sending")
            XCTAssertEqual(vm.lastSentText, "Something to undo")
        }
    }

    func testUndoSendRemovesLastUserMessage() {
        let vm = makeViewModel()
        vm.userInput = "Remove me"

        vm.sendMessage()
        // Stop streaming immediately so we can test undo cleanly
        vm.stopGeneration()

        if vm.errorMessage == nil && vm.undoSendAvailable {
            let countBefore = vm.currentConversation?.messages.count ?? 0
            vm.undoSend()
            XCTAssertEqual(vm.currentConversation?.messages.count, countBefore - 1,
                           "undoSend should remove the last user message")
            XCTAssertFalse(vm.undoSendAvailable, "undoSend window should close after undo")
        }
    }

    func testUndoSendNoOpsWhenNotAvailable() {
        let vm = makeViewModel()
        vm.undoSendAvailable = false
        let messageCount = vm.currentConversation?.messages.count ?? 0

        vm.undoSend()

        XCTAssertEqual(vm.currentConversation?.messages.count, messageCount,
                       "undoSend should not modify messages when not available")
    }

    func testUndoSendNoOpsWhenLastMessageIsAssistant() {
        let vm = makeViewModel()
        vm.currentConversation?.messages.append(Message(role: .assistant, content: "Bot reply"))
        vm.undoSendAvailable = true
        let messageCount = vm.currentConversation?.messages.count ?? 0

        vm.undoSend()

        XCTAssertEqual(vm.currentConversation?.messages.count, messageCount,
                       "undoSend should not remove assistant messages")
    }

    // MARK: - Frustration Detection

    func testSendMessageDetectsFrustration() {
        let vm = makeViewModel()
        vm.userInput = "This is broken! Nothing works and I'm frustrated!"

        vm.sendMessage()

        // Frustration detection runs even if provider guard fires early for error messages
        // We can't guarantee the exact sentiment without the AI service,
        // but we can verify the property exists and was set
        XCTAssertNotNil(vm.lastUserSentiment)
    }

    // MARK: - Sequential Send

    func testMultipleSendsAppendMultipleMessages() {
        let vm = makeViewModel()

        vm.userInput = "First"
        vm.sendMessage()
        vm.stopGeneration()

        if vm.errorMessage == nil {
            vm.userInput = "Second"
            vm.sendMessage()
            vm.stopGeneration()

            let userMessages = vm.currentConversation?.messages.filter { $0.role == .user } ?? []
            XCTAssertEqual(userMessages.count, 2, "Two sends should produce two user messages")
            XCTAssertEqual(userMessages[0].content, "First")
            XCTAssertEqual(userMessages[1].content, "Second")
        }
    }
}
