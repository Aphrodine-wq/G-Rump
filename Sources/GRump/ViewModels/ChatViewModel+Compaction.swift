import Foundation

// MARK: - Rolling Context Compaction
//
// Long agentic runs used to hard-drop their oldest turns when the context
// filled, losing the plan and early findings. Compaction summarizes the
// would-be-dropped span (light model) into a running note instead:
// buildAPIMessages then emits [pinned first user message] + [summary note]
// + the live tail. The persisted conversation is never mutated; compaction
// state lives on the view model and resets with the conversation.

extension ChatViewModel {

    /// Fraction of the context limit that triggers compaction.
    static let compactionTriggerFraction = 0.75

    /// Pure cut-point selection, testable without a view model. Returns the
    /// index (exclusive end of the span to summarize, relative to `startIndex`
    /// onward) such that messages[startIndex..<cut] covers roughly
    /// `targetTokens`, and `cut` lands ON a user message — the surviving tail
    /// then starts with a user turn, so assistant tool_use / tool_result
    /// groups are never split (Anthropic rejects orphaned tool results).
    nonisolated static func compactionCutIndex(
        tokenCounts: [Int],
        isUserMessage: [Bool],
        startIndex: Int,
        targetTokens: Int
    ) -> Int? {
        guard tokenCounts.count == isUserMessage.count, startIndex >= 0 else { return nil }
        guard startIndex < tokenCounts.count else { return nil }
        var accumulated = 0
        var candidate: Int?
        for idx in startIndex..<tokenCounts.count {
            if accumulated >= targetTokens, isUserMessage[idx] {
                candidate = idx
                break
            }
            accumulated += tokenCounts[idx]
        }
        // Keep a real tail: never compact into the last two messages.
        guard let cut = candidate, cut > startIndex, cut < tokenCounts.count - 2 else { return nil }
        return cut
    }

    /// Called at the top of each agent-loop turn. Cheap no-op until the
    /// estimated context crosses the trigger threshold.
    func maybeCompactContext() async {
        guard !isCompacting, let conversation = currentConversation else { return }
        let msgs = conversation.messages
        guard msgs.count > 6 else { return }

        let contextLimit = selectedModel.contextWindow - selectedModel.maxOutput - 2000
        let liveMsgs = compactionCutoffIndex > 0 ? Array(msgs[compactionCutoffIndex...]) : msgs
        let estimated = liveMsgs.reduce(0) { $0 + estimateMessageTokens($1) }
        guard Double(estimated) > Double(contextLimit) * Self.compactionTriggerFraction else { return }

        let tokenCounts = msgs.map { estimateMessageTokens($0) }
        let userFlags = msgs.map { $0.role == .user }
        guard let cut = Self.compactionCutIndex(
            tokenCounts: tokenCounts,
            isUserMessage: userFlags,
            startIndex: compactionCutoffIndex,
            targetTokens: estimated / 2
        ) else { return }

        isCompacting = true
        defer { isCompacting = false }

        let span = Array(msgs[compactionCutoffIndex..<cut])
        guard let summary = await summarizeSpan(span) else {
            // Failure leaves state untouched — truncateMessages remains the
            // hard fallback, exactly as before compaction existed.
            return
        }

        if let existing = compactionSummary {
            // Re-cap a growing summary chain instead of concatenating forever.
            compactionSummary = String((existing + "\n" + summary).suffix(6_000))
        } else {
            compactionSummary = summary
        }
        compactionCutoffIndex = cut
        GRumpLogger.ai.info("Context compacted: \(span.count) messages summarized, cutoff now \(cut)")
    }

    private func summarizeSpan(_ span: [Message]) async -> String? {
        let transcript = span.map { msg -> String in
            let toolNames = (msg.toolCalls ?? []).map(\.name).joined(separator: ", ")
            let suffix = toolNames.isEmpty ? "" : " [tools: \(toolNames)]"
            return "\(msg.role.rawValue)\(suffix): \(String(msg.content.prefix(600)))"
        }.joined(separator: "\n")

        let systemPrompt = """
        Summarize this agent-run transcript span for the agent's own future \
        context. Capture, in at most 300 words: decisions made, files read or \
        changed (with paths), constraints and facts discovered, errors hit \
        and how they were resolved, and anything still unresolved. Plain \
        prose or terse bullets — no preamble.
        """
        let judgeModel = ModelRouter.route(taskType: .reflection, fallback: effectiveModel)
        let messages: [Message] = [
            Message(role: .system, content: systemPrompt),
            Message(role: .user, content: String(transcript.prefix(40_000)))
        ]
        var response = ""
        do {
            let stream = MultiProviderAIService.stream(messages: messages, modelID: judgeModel.rawValue)
            for try await event in stream {
                if case .text(let chunk) = event { response += chunk }
            }
        } catch {
            GRumpLogger.ai.error("Context compaction summarize failed: \(error.localizedDescription)")
            return nil
        }
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
