import Foundation

// MARK: - Messages and Conversations Extension
extension ChatViewModel {

    // MARK: - Conversation Management

    func createNewConversation() {
        let conversation = Conversation(title: "New Chat")
        conversations.insert(conversation, at: 0)
        currentConversation = conversation
        userInput = ""
        syncDirty = true
        flushSync()
        SpotlightIndexer.shared.indexConversation(conversation)
    }

    func deleteConversation(_ conversation: Conversation) {
        SpotlightIndexer.shared.deindexConversation(conversation.id)
        saveDraft("", forConversationId: conversation.id) // Clean up orphaned draft
        conversations.removeAll { $0.id == conversation.id }
        if currentConversation?.id == conversation.id {
            currentConversation = conversations.first
            userInput = currentConversation != nil ? loadDraft(forConversationId: currentConversation!.id) : ""
        }
        syncDirty = true
        flushSync()
    }

    func renameConversation(_ conversation: Conversation, to newTitle: String) {
        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[index].title = newTitle
            if currentConversation?.id == conversation.id {
                currentConversation?.title = newTitle
            }
            syncDirty = true
            flushSync()
            SpotlightIndexer.shared.indexConversation(conversations[index])
        }
    }

    func duplicateConversation(_ conversation: Conversation) {
        var copy = Conversation(title: "Copy of \(conversation.title)")
        copy.messages = conversation.messages.map { msg in
            var m = msg
            m.id = UUID()
            return m
        }
        conversations.insert(copy, at: 0)
        currentConversation = copy
        syncDirty = true
        flushSync()
    }

    func selectConversation(_ conversation: Conversation) {
        if let currentId = currentConversation?.id {
            saveDraft(userInput, forConversationId: currentId)
        }
        currentConversation = conversation
        userInput = loadDraft(forConversationId: conversation.id)
    }

    func syncConversation() {
        guard let current = currentConversation,
              let idx = conversations.firstIndex(where: { $0.id == current.id }) else { return }
        conversations[idx] = current
        syncDirty = true
        syncDebounceTask?.cancel()
        syncDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms debounce
            guard !Task.isCancelled else { return }
            self?.flushSync()
            // Update Spotlight index after debounced save
            if let conv = self?.currentConversation {
                SpotlightIndexer.shared.indexConversation(conv)
            }
        }
    }

    // MARK: - Message Operations

    func undoSend() {
        guard undoSendAvailable,
              let lastMessage = currentConversation?.messages.last,
              lastMessage.role == .user else { return }

        currentConversation?.messages.removeLast()
        currentConversation?.updateTitle()
        undoSendAvailable = false
        syncConversation()
    }

    func editUserMessage(_ messageId: UUID, newContent: String) {
        guard var conversation = currentConversation else { return }

        if let messageIndex = conversation.messages.firstIndex(where: { $0.id == messageId }),
           conversation.messages[messageIndex].role == .user {

            conversation.messages[messageIndex].content = newContent
            conversation.updateTitle()
            currentConversation = conversation
            syncConversation()
        }
    }

    // MARK: - Threading Support

    func createThread(from messageId: UUID, name: String? = nil) {
        guard var conversation = currentConversation else { return }
        if conversation.createThread(from: messageId, name: name) != nil {
            currentConversation = conversation
            syncConversation()
        }
    }

    func createBranch(from messageId: UUID, name: String) {
        guard var conversation = currentConversation else { return }
        if conversation.createBranch(from: messageId, name: name) != nil {
            currentConversation = conversation
            syncConversation()
        }
    }

    /// Set the conversation view mode
    func setConversationViewMode(_ mode: Conversation.ConversationViewMode) {
        currentConversation?.viewMode = mode
        syncConversation()
    }
}
