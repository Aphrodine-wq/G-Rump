import Foundation

// MARK: - Agent Verification (auto-verify + completion gate)
//
// Both hooks fire at the would-be completion point of the agent loop — the
// model has stopped calling tools. Order: auto-verify (did the edits build?)
// then the completion gate (is the request actually satisfied?). Either can
// send the loop back to work by injecting an agent note and returning true.

/// Run-local verification state, owned by runAgentLoop.
struct AgentVerifyState {
    var autoVerifyCycles = 0
    var verifiedChangeCount = 0
    var completionRetries = 0
    var capNoticeSent = false
    /// Set true when the model itself ran a green build/test after its last
    /// write — auto-verify then skips the redundant build.
    var buildSucceededSinceLastWrite = false
    var lastVerifyStatus = "not run"
}

extension ChatViewModel {

    static let maxAutoVerifyCycles = 3
    static let maxCompletionRetries = 2

    /// Deterministic build-failure classifier over tool output.
    /// runShellCommand appends "[exit code: N]" on non-zero exits, so this
    /// keys off that marker first, then ecosystem error markers.
    nonisolated static func buildFailed(_ output: String) -> Bool {
        if output.contains("[exit code:") { return true }
        if output.hasPrefix("Error") { return true }
        let markers = ["error:", "** BUILD FAILED **", "npm ERR!", "error[E", "FAILED (exit"]
        return markers.contains { output.contains($0) }
    }

    /// Returns true when the loop should continue (build failed, note injected).
    func runAutoVerifyIfNeeded(state: inout AgentVerifyState) async -> Bool {
        let defaultsEnabled = UserDefaults.standard.object(forKey: "AutoVerifyEnabled") as? Bool ?? true
        let enabled = projectConfig?.autoVerify ?? defaultsEnabled
        guard enabled else { return false }
        guard !currentRunCodeChanges.isEmpty else { return false }
        guard currentRunCodeChanges.count > state.verifiedChangeCount else { return false }

        if state.buildSucceededSinceLastWrite {
            // The model already proved the build green after its last write.
            state.verifiedChangeCount = currentRunCodeChanges.count
            state.lastVerifyStatus = "build passed (model-run)"
            return false
        }

        guard state.autoVerifyCycles < Self.maxAutoVerifyCycles else {
            if !state.capNoticeSent {
                state.capNoticeSent = true
                appendAgentNote("[Auto-verify] Gave up after \(Self.maxAutoVerifyCycles) failed build cycles. Summarize the remaining failures for the user instead of claiming success.")
            }
            return false
        }

        state.autoVerifyCycles += 1
        state.verifiedChangeCount = currentRunCodeChanges.count
        currentRunAutoVerifyCycles = state.autoVerifyCycles

        var buildArgs: [String: Any] = [:]
        if let cmd = projectConfig?.buildCommand, !cmd.isEmpty { buildArgs["command"] = cmd }
        let output = await executeRunBuild(buildArgs)

        if output.hasPrefix("No supported project") {
            // Nothing to build here — don't burn cycles retrying.
            state.lastVerifyStatus = "no build system detected"
            return false
        }

        if Self.buildFailed(output) {
            state.lastVerifyStatus = "build FAILED"
            if let analysis = await regressionTracker.analyze(
                errorOutput: output,
                failedCommand: "run_build",
                workingDirectory: workingDirectory
            ) {
                appendAgentNote(analysis.markdownSummary)
            }
            appendAgentNote("[Auto-verify] The build FAILED after your edits:\n\(truncateToolResult(output, maxChars: 6_000))\nFix the errors before finishing.")
            return true
        }

        state.lastVerifyStatus = "build passed"

        // Tests: strictly opt-in (per-project testCommand + global toggle) —
        // large suites are the user's call, never the harness default.
        let runTests = UserDefaults.standard.object(forKey: "AutoVerifyRunTests") as? Bool ?? false
        if runTests, let testCmd = projectConfig?.testCommand, !testCmd.isEmpty {
            let testOutput = await executeRunTests(["command": testCmd])
            if Self.buildFailed(testOutput) {
                state.lastVerifyStatus = "build passed, tests FAILED"
                appendAgentNote("[Auto-verify] Tests FAILED after your edits:\n\(truncateToolResult(testOutput, maxChars: 6_000))\nFix the failures before finishing.")
                return true
            }
            state.lastVerifyStatus = "build + tests passed"
        }
        return false
    }

    /// Returns true when the loop should continue (request judged incomplete).
    func runCompletionGateIfNeeded(
        state: inout AgentVerifyState,
        iterationCount: Int,
        maxIterations: Int
    ) async -> Bool {
        let gateEnabled = UserDefaults.standard.object(forKey: "CompletionGateEnabled") as? Bool ?? true
        let openSteps = currentPlan?.openSteps ?? []
        guard CompletionCheck.shouldRun(
            gateEnabled: gateEnabled,
            hasCodeChanges: !currentRunCodeChanges.isEmpty,
            openPlanSteps: openSteps.count,
            iterationCount: iterationCount,
            maxIterations: maxIterations,
            completionRetries: state.completionRetries
        ) else { return false }

        // Deterministic fast path: an open plan IS the verdict — no LLM call.
        if !openSteps.isEmpty {
            state.completionRetries += 1
            currentRunCompletionRetries = state.completionRetries
            let list = openSteps.prefix(10).map { "- \($0.title)" }.joined(separator: "\n")
            appendAgentNote("[Completion check] Your tracked plan still has open steps:\n\(list)\nFinish them, or mark them done with update_plan and state why they no longer apply.")
            return true
        }

        // LLM path: light-model judge over a distilled snapshot.
        let framing = currentConversation?.messages.first(where: { $0.role == .user })?.content ?? ""
        guard !framing.isEmpty else { return false }
        let lastAssistant = currentConversation?.messages.last(where: { $0.role == .assistant })?.content ?? ""
        let judgeModel = ModelRouter.route(taskType: .reflection, fallback: effectiveModel)

        let verdict = await CompletionCheck.judge(
            taskFraming: framing,
            changedFiles: currentRunCodeChanges.map(\.filePath),
            lastAssistantMessage: lastAssistant,
            verifyStatus: state.lastVerifyStatus,
            modelID: judgeModel.rawValue
        )
        // Fail-open: no verdict (or judged complete) ends the run normally.
        guard let verdict, !verdict.complete else { return false }

        state.completionRetries += 1
        currentRunCompletionRetries = state.completionRetries
        let unfinished = verdict.unfinished.isEmpty
            ? verdict.reason
            : verdict.unfinished.map { "- \($0)" }.joined(separator: "\n")
        appendAgentNote("[Completion check] The original request is not fully satisfied yet.\n\(unfinished)\nContinue working; when truly done, state briefly why each requested item is complete.")
        return true
    }
}
