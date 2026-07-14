import Foundation

// MARK: - Streaming Extension
extension ChatViewModel {

    // MARK: - Provider Stream Factory

    /// Creates a streaming connection via the multi-provider dispatcher.
    /// (The Qwen-era backend proxy branch is gone — the slim backend spoke
    /// DashScope only; re-adding a proxy is a separate follow-up.)
    func createProviderStream(
        messages: [Message],
        tools: [[String: Any]]
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        return aiService.streamMessage(
            messages: messages,
            tools: tools.isEmpty ? nil : tools
        )
    }

    /// Send a message and start streaming response
    func sendMessage() {
        let trimmed = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !isAIProviderConfigured && apiKey.trimmingCharacters(in: .whitespaces).isEmpty {
            errorMessage = "No provider configured. Open Settings (\u{2318},) to add an API key."
            return
        }

        // Check connectivity before attempting to stream. Local providers
        // (Ollama) stream over localhost, so being offline is fine.
        if !ConnectionMonitor.shared.canStream && !currentAIProvider.isLocal {
            errorMessage = "You appear to be offline. Check your internet connection and try again."
            return
        }

        let userMessage = Message(role: .user, content: trimmed)
        currentConversation?.messages.append(userMessage)
        currentConversation?.updateTitle()
        syncConversation()

        // Two-stage outcome: if this message corrects the previous run, flip
        // that run's recorded success before the new run begins.
        let rejectedBlocks = CodeApplyService.shared.blockStates.values.filter { $0 == .rejected }.count
        let corrections = UserCorrectionDetector.reasons(
            message: trimmed,
            rejectedCodeBlocks: rejectedBlocks,
            approvalDenials: approvalDenialsSinceLastRun
        )
        approvalDenialsSinceLastRun = 0
        if !corrections.isEmpty {
            Task { @MainActor in
                let amendedLessonIds = await outcomeLedger.amendLastOutcome(corrections: corrections)
                LessonStore.shared.recordOutcome(ids: amendedLessonIds, success: false)
            }
        }

        // Apple Intelligence: classify intent and detect frustration
        let intel = AppleIntelligenceService.shared
        let intent = intel.classifyUserIntent(trimmed)
        let frustrated = intel.isUserFrustrated(trimmed)
        if frustrated {
            // Inject empathetic context for the agent
            lastUserSentiment = .frustrated
        } else {
            lastUserSentiment = .neutral
        }
        lastUserIntent = intent

        // Enable undo send for 5 seconds
        lastSentText = trimmed
        undoSendAvailable = true
        undoSendTask?.cancel()
        undoSendTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            undoSendAvailable = false
            lastSentText = nil
        }

        userInput = ""
        if let id = currentConversation?.id {
            saveDraft("", forConversationId: id)
        }
        startStreaming(task: trimmed)
    }

    /// Start streaming with appropriate agent mode
    private func startStreaming(task: String) {
        isLoading = true
        isPaused = false
        errorMessage = nil
        streamingContent = ""
        thinkingContent = ""
        isThinking = false
        activeToolCalls = []
        currentRunCodeChanges = []
        currentRunAutoVerifyCycles = 0
        currentRunCompletionRetries = 0

        // Load temporal intelligence and intent continuity for this run
        Task {
            await TemporalCodeIntelligenceService.shared.analyze(workingDirectory: workingDirectory)
        }
        intentContinuity.load(workingDirectory: workingDirectory)

        streamTask?.cancel()
        streamTask = Task {
            await self.runAgentLoop()
            streamTask = nil
            isLoading = false
        }
    }

    /// Stop the current generation
    func stopGeneration() {
        streamTask?.cancel()
        isLoading = false
        isPaused = false
    }

    /// Pause the agent mid-run. Conversation state is preserved. Call resumeAgent() to continue.
    func pauseGeneration() {
        streamTask?.cancel()
        isLoading = false
        isPaused = true
    }

    /// Resume the agent after a pause. Continues from the current conversation state.
    func resumeAgent() {
        guard isPaused, currentConversation != nil else { return }
        isPaused = false
        isLoading = true
        errorMessage = nil
        streamingContent = ""
        activeToolCalls = []
        streamTask?.cancel()
        streamTask = Task {
            await runAgentLoop()
            streamTask = nil
            isLoading = false
        }
    }

    /// Restart streaming with current conversation state
    func restartStreaming() {
        streamTask?.cancel()
        streamTask = Task {
            await self.runAgentLoop()
            streamTask = nil
            isLoading = false
        }
    }
}
