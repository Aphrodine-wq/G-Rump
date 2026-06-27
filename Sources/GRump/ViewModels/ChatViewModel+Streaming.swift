import Foundation

// MARK: - Streaming Extension
extension ChatViewModel {

    // MARK: - Provider Stream Factory

    /// Creates a streaming connection using the appropriate provider.
    /// Uses the platform backend when authenticated, otherwise falls back
    /// to the configured AI provider. This eliminates duplicated if/else
    /// blocks across `runAgentLoop()` and `handleOpenClawMessage()`.
    func createProviderStream(
        messages: [Message],
        tools: [[String: Any]]
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        if let token = PlatformService.authToken, !token.isEmpty {
            return openRouterService.streamMessageViaBackend(
                messages: messages,
                model: effectiveModel.rawValue,
                backendBaseURL: PlatformService.baseURL,
                authToken: token,
                tools: tools.isEmpty ? nil : tools
            )
        } else {
            return aiService.streamMessage(
                messages: messages,
                tools: tools.isEmpty ? nil : tools
            )
        }
    }

    /// Send a message and start streaming response
    func sendMessage() {
        let trimmed = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !isAIProviderConfigured && apiKey.trimmingCharacters(in: .whitespaces).isEmpty && platformUser == nil && !localOllamaReady {
            errorMessage = "No provider configured. Open Settings (\u{2318},) to add an API key, or start Ollama locally."
            return
        }

        // Check connectivity before attempting to stream
        if !ConnectionMonitor.shared.canStream {
            errorMessage = "You appear to be offline. Check your internet connection and try again."
            return
        }

        let userMessage = Message(role: .user, content: trimmed)
        currentConversation?.messages.append(userMessage)
        currentConversation?.updateTitle()
        syncConversation()

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

    // MARK: - OpenClaw Message Handling

    /// Process an incoming message from the OpenClaw gateway.
    /// Routes it through the normal agent loop and streams the response back.
    func handleOpenClawMessage(sessionId: String, content: String, model: String?) async {
        // Don't interrupt an active generation
        guard !isLoading else {
            await OpenClawService.shared.sendResponse(
                sessionId: sessionId,
                content: "G-Rump is busy with another task. Please wait.",
                done: true
            )
            return
        }

        activeOpenClawSessionId = sessionId

        // Inject the message into the conversation
        let userMessage = Message(role: .user, content: content)
        if currentConversation == nil { createNewConversation() }
        currentConversation?.messages.append(userMessage)
        currentConversation?.updateTitle()
        syncConversation()

        // If the caller requested a specific model, try to select it
        if let modelId = model, let aiModel = AIModel(rawValue: modelId) {
            selectedModel = aiModel
        }

        // Run the agent loop (reuses the same streaming pipeline as normal chat)
        isLoading = true
        isPaused = false
        errorMessage = nil
        streamingContent = ""
        activeToolCalls = []
        currentRunCodeChanges = []

        streamTask?.cancel()
        streamTask = Task {
            await self.runAgentLoop()
            streamTask = nil
            isLoading = false

            // Send the final assistant response back to OpenClaw
            let responseContent: String
            if let lastAssistant = self.currentConversation?.messages.last(where: { $0.role == .assistant }) {
                responseContent = lastAssistant.content
            } else if let err = self.errorMessage {
                responseContent = "Error: \(err)"
            } else {
                responseContent = "No response generated."
            }

            await OpenClawService.shared.sendResponse(
                sessionId: sessionId,
                content: responseContent,
                done: true
            )
            self.activeOpenClawSessionId = nil
        }
    }
}
