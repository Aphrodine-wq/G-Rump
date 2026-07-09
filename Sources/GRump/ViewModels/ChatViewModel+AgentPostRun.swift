import Foundation
import SwiftUI

// MARK: - Agent Post-Run Extension
//
// Contains all post-run cleanup logic that executes after the agent loop
// completes: metrics, adversarial review, confidence calibration,
// loop detection, intent continuity, follow-ups, persistence, and notifications.
// Extracted from ChatViewModel+AgentLoop.swift for maintainability.

extension ChatViewModel {

    // MARK: - Post-Run Cleanup

    /// Runs all post-agent-loop bookkeeping: tool timeline cleanup, metrics,
    /// adversarial review, confidence calibration, loop detection, intent
    /// continuity, follow-up generation, persistence, and notifications.
    ///
    /// - Parameters:
    ///   - iterationCount: Number of iterations the agent loop completed.
    ///   - maxIterations: Maximum allowed iterations (for limit warning).
    func runPostAgentCleanup(iterationCount: Int, maxIterations: Int) async {
        currentAgentStep = nil
        currentAgentStepMax = nil

        if iterationCount >= maxIterations {
            let warningMsg = Message(role: .assistant, content: "I've reached the maximum iteration limit (\(maxIterations) turns). The task may be partially complete. You can continue by sending another message.")
            currentConversation?.messages.append(warningMsg)
            syncConversation()
        }

        // Keep completed tool timeline visible for 2s before clearing
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation(.easeOut(duration: 0.3)) {
                activeToolCalls = []
            }
        }
        streamMetrics.endStream()

        // --- Adversarial Self-Review (Build mode only) ---
        if agentMode == .fullStack && !currentRunCodeChanges.isEmpty {
            let userMessage = currentConversation?.messages.last(where: { $0.role == .user })?.content ?? ""
            if let report = await adversarialReview.review(
                codeChanges: currentRunCodeChanges,
                conversationContext: userMessage,
                primaryModel: effectiveModel
            ) {
                let reviewMsg = Message(role: .assistant, content: report.markdownSummary)
                currentConversation?.messages.append(reviewMsg)
                syncConversation()
            }
        }
        currentRunCodeChanges = []

        // --- Confidence Calibration: record outcome ---
        let lastToolResults = activityStore.entries.suffix(10).map { (name: $0.toolName, success: $0.success) }
        let hasErrors = lastToolResults.contains { !$0.success }
        confidenceCalibration.recordOutcome(
            predictedLevel: confidenceCalibration.currentLevel,
            actualSuccess: !hasErrors
        )

        // --- Cognitive Loop Detector: record pivot outcome ---
        let loopPivots = await cognitiveLoopDetector.totalPivots
        if loopPivots > 0 {
            await cognitiveLoopDetector.recordPivotOutcome(success: !hasErrors)
        }
        await cognitiveLoopDetector.reset()

        // --- Intent Continuity: extract or update intent ---
        if let firstUserMsg = currentConversation?.messages.first(where: { $0.role == .user })?.content {
            if intentContinuity.activeIntent == nil {
                if let extracted = IntentContinuityService.extractIntent(from: firstUserMsg) {
                    intentContinuity.createIntent(goal: extracted.goal, milestones: extracted.milestones)
                }
            } else {
                intentContinuity.updateActiveIntent(conversationId: currentConversation?.id.uuidString)
            }
        }

        // --- Confidence Assessment for next run ---
        _ = confidenceCalibration.assess(
            recentToolResults: lastToolResults,
            lspDiagnostics: lspDiagnostics,
            targetFiles: currentRunCodeChanges.map(\.filePath),
            taskDescription: currentConversation?.messages.last(where: { $0.role == .user })?.content ?? "",
            memoryHits: 0,
            loopDetectorPivots: loopPivots
        )

        // Generate smart follow-up suggestions from the last assistant message
        if let lastAssistant = currentConversation?.messages.last(where: { $0.role == .assistant }) {
            followUpSuggestions = FollowUpGenerator.generate(from: lastAssistant.content, agentMode: agentMode)
        }

        flushSync() // Ensure final state is persisted immediately
        saveToProjectMemoryIfEnabled()
        // Notify user of task completion (only fires when app is backgrounded)
        if let conv = currentConversation {
            let lastAssistant = conv.messages.last(where: { $0.role == .assistant })?.content ?? "Task completed."
            GRumpNotificationService.shared.notifyTaskComplete(
                conversationId: conv.id,
                conversationTitle: conv.title,
                modelName: effectiveModel.displayName,
                resultSummary: String(lastAssistant.prefix(200))
            )
        }
    }
}
