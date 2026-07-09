import Foundation

// MARK: - UI State Management Extension
extension ChatViewModel {

    // MARK: - UI State Properties

    /// Whether the user can send messages. Always enabled — provider errors are surfaced at send time.
    var canUseAI: Bool {
        return true
    }

    /// Ensures selectedModel still resolves in the registry (catalog updates
    /// can retire ids); falls back to the app default.
    func ensureSelectedModelValidForTier() {
        if aiService.modelRegistry.getModel(by: selectedModel.id) == nil {
            selectedModel = aiService.modelRegistry.defaultModel()
        }
    }

    // MARK: - Working Directory Management

    func setWorkingDirectory(_ path: String) {
        workingDirectory = path
        UserDefaults.standard.set(path, forKey: "WorkingDirectory")
        projectConfig = ProjectConfig.load(from: path)
        ProjectStore.shared.noteProjectOpened(path)
        Task { await outcomeLedger.setProjectDirectory(path) }
    }

    // MARK: - Preset Management

    func applyPreset(_ preset: WorkflowPreset) {
        if let model = preset.model {
            selectedModel = model
        }
        systemPrompt = preset.systemPrompt
        appliedPresetToolAllowlist = preset.toolAllowlist
        appliedPresetName = preset.name
        appliedPresetMaxAgentSteps = preset.maxAgentSteps
    }

    func clearAppliedPreset() {
        appliedPresetToolAllowlist = nil
        appliedPresetName = nil
        appliedPresetMaxAgentSteps = nil
    }

    // MARK: - Agent Mode State

    /// Get the current view mode for the conversation
    var conversationViewMode: Conversation.ConversationViewMode {
        currentConversation?.viewMode ?? .linear
    }

    /// Get the active thread
    var activeThread: MessageThread? {
        guard let conversation = currentConversation,
              let activeThreadId = conversation.activeThreadId else { return nil }

        return conversation.threads.first { $0.id == activeThreadId }
    }

    /// Set the active thread
    func setActiveThread(_ threadId: UUID?) {
        guard var conversation = currentConversation else { return }

        conversation.activeThreadId = threadId
        currentConversation = conversation
        syncConversation()
    }

    // MARK: - Message Filtering

    /// Get messages filtered by the current view mode and active thread
    var filteredMessages: [Message] {
        guard let conversation = currentConversation else { return [] }

        switch conversation.viewMode {
        case .linear:
            return conversation.messages.sorted { $0.timestamp < $1.timestamp }
        case .threaded:
            return conversation.getActiveThreadMessages()
        case .branched:
            return conversation.getActiveThreadMessages()
        }
    }
}
