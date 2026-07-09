import Foundation

// MARK: - Conscience gating
//
// Runs the deterministic, fail-closed Conscience gate before mutating/sensitive tools.
// Surface evidence comes from the latest Eyes observation when screen awareness is on;
// otherwise the gate still catches by argument semantics (protected branch, secret path).

extension ChatViewModel {

    /// Tool names considered mutating/sensitive (gated). Read-only tools stay ungated.
    static let mutatingToolNames: Set<String> = [
        "create_file", "write_file", "edit_file", "append_file", "delete_file",
        "create_directory", "find_and_replace", "git_add", "git_commit", "git_push",
        "write_env_file", "npm_install", "pip_install", "cargo_add", "docker_run", "docker_build",
        "propose_skill"
    ]

    /// Returns a refusal string if the Conscience gate blocks this tool, else nil.
    func conscienceRefusal(toolName: String, arguments: String) async -> String? {
        let config = BrainConfigStore.shared.load()
        guard config.conscienceEnabled else { return nil }

        // Surface from the latest screen observation, when Eyes is on.
        var surface: Surface = .neutral
        var evidence: [String] = []
        if config.eyesEnabled, let obs = await EyesEngine.shared.store.latest() {
            let classifier = SurfaceClassifier()
            surface = classifier.classify(obs.redactedText)
            evidence = classifier.evidence(in: obs.redactedText, for: surface)
        }

        let verdict = await ConscienceGate.shared.evaluate(
            toolName: toolName,
            arguments: arguments,
            surface: surface,
            surfaceEvidence: evidence,
            roster: ValuesRoster.load()
        )

        guard !verdict.approved else { return nil }

        GRumpLogger.brain.warning("Conscience refused \(toolName, privacy: .public): \(verdict.reason, privacy: .public)")
        var msg = "Refused by Conscience: \(verdict.reason)."
        if !verdict.evidence.isEmpty {
            msg += " On-screen evidence: \(verdict.evidence.joined(separator: ", "))."
        }
        return msg
    }
}
