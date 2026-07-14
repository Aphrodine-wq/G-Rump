import Foundation

// MARK: - Plan Tool Execution

extension ChatViewModel {

    func executeUpdatePlan(_ args: [String: Any]) -> String {
        guard let rawSteps = args["steps"] as? [[String: Any]] else {
            return "Error: missing steps array"
        }
        if rawSteps.isEmpty {
            currentPlan = nil
            return "Plan cleared."
        }
        var steps: [AgentPlan.Step] = []
        for raw in rawSteps.prefix(AgentPlan.maxSteps) {
            guard let title = raw["title"] as? String, !title.trimmingCharacters(in: .whitespaces).isEmpty else {
                return "Error: every step needs a non-empty title"
            }
            let status = AgentPlan.Step.Status(rawValue: raw["status"] as? String ?? "pending") ?? .pending
            steps.append(AgentPlan.Step(title: title, status: status))
        }
        let plan = AgentPlan(steps: steps)
        currentPlan = plan
        let open = plan.openSteps.count
        let dropped = rawSteps.count > AgentPlan.maxSteps ? " (truncated to \(AgentPlan.maxSteps) steps)" : ""
        return "Plan updated — \(plan.steps.count) steps, \(open) open\(dropped):\n\(plan.markdownSnapshot())"
    }
}
