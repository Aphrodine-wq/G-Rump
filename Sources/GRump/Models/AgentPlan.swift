import Foundation

/// The agent's tracked task plan for the current conversation.
///
/// Written by the `update_plan` tool (full-replacement semantics — the model
/// resends the whole step list each time). The loop re-injects a snapshot as
/// a trailing agent note every turn, and the completion gate treats open
/// steps as "not done". In-memory only; never persisted, never gated.
struct AgentPlan: Codable, Sendable, Equatable {
    struct Step: Codable, Sendable, Equatable {
        enum Status: String, Codable, Sendable {
            case pending
            case inProgress = "in_progress"
            case done
        }

        var title: String
        var status: Status
    }

    static let maxSteps = 25

    var steps: [Step]

    var openSteps: [Step] {
        steps.filter { $0.status != .done }
    }

    /// Compact markdown for prompt injection / tool results (~1,500-char cap).
    func markdownSnapshot(cap: Int = 1_500) -> String {
        var lines: [String] = []
        for step in steps.prefix(Self.maxSteps) {
            let marker: String
            switch step.status {
            case .pending: marker = "[ ]"
            case .inProgress: marker = "[~]"
            case .done: marker = "[x]"
            }
            lines.append("- \(marker) \(step.title)")
        }
        var snapshot = lines.joined(separator: "\n")
        if snapshot.count > cap {
            snapshot = String(snapshot.prefix(cap)) + "\n- … (plan truncated)"
        }
        return snapshot
    }
}
