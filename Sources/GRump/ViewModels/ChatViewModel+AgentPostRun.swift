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
        var adversarialCriticals = 0
        if agentMode == .fullStack && !currentRunCodeChanges.isEmpty {
            let userMessage = currentConversation?.messages.last(where: { $0.role == .user })?.content ?? ""
            if let report = await adversarialReview.review(
                codeChanges: currentRunCodeChanges,
                conversationContext: userMessage,
                primaryModel: effectiveModel
            ) {
                adversarialCriticals = report.criticalCount
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

        // --- Outcome Ledger: persist this run's signals for the learning loop ---
        let userRequest = currentConversation?.messages.first(where: { $0.role == .user })?.content ?? ""
        let conversationId = currentConversation?.id
        let runEntries = activityStore.entries
            .prefix(60)
            .filter { $0.conversationId == conversationId }
        var toolStats: [String: RunOutcome.ToolStat] = [:]
        for entry in runEntries {
            var stat = toolStats[entry.toolName] ?? RunOutcome.ToolStat(name: entry.toolName, calls: 0, failures: 0)
            stat.calls += 1
            if !entry.success { stat.failures += 1 }
            toolStats[entry.toolName] = stat
        }
        let buildFailures = runEntries
            .filter { ["run_build", "xcodebuild", "run_tests", "swift_package"].contains($0.toolName) && !$0.success }
            .count
        let regressionSummary: String?
        if let analysis = regressionTracker.lastAnalysis, Date().timeIntervalSince(analysis.timestamp) < 600 {
            regressionSummary = analysis.suspectedCommit.map {
                "suspected \($0.shortHash): \($0.message)"
            } ?? "regression analyzed, no suspect commit"
        } else {
            regressionSummary = nil
        }
        let outcome = RunOutcome(
            conversationId: conversationId,
            taskType: TaskType.classify(from: userRequest).rawValue,
            iterations: iterationCount,
            toolStats: toolStats.values.sorted { $0.name < $1.name },
            buildFailures: buildFailures,
            loopPivots: loopPivots,
            regressionSummary: regressionSummary,
            adversarialCriticals: adversarialCriticals,
            injectedLessonIds: lastInjectedLessonIds,
            success: !hasErrors
        )
        LessonStore.shared.recordOutcome(ids: lastInjectedLessonIds, success: !hasErrors)
        lastInjectedLessonIds = []
        Task { await outcomeLedger.record(outcome) }

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
