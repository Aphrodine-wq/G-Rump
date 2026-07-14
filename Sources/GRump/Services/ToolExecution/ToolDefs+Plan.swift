import Foundation

// MARK: - Plan Tool Definition
//
// The agent's tracked checklist. In-memory only (no Conscience gate — the
// plan mutates no files); the loop re-injects the current snapshot each turn
// and the completion gate refuses to finish while steps remain open.

extension ToolDefinitions {

    nonisolated(unsafe) static let updatePlan: [String: Any] = [
        "type": "function",
        "function": [
            "name": "update_plan",
            "description": "Create or update your tracked task plan. Send the FULL step list every time (full replacement, not a diff). Use for any task with 2 or more distinct steps: create the plan first, mark steps in_progress as you start them and done as you finish. The run is not considered complete while steps remain open — if a step turns out to be unnecessary, mark it done and say why in your reply.",
            "parameters": [
                "type": "object",
                "properties": [
                    "steps": [
                        "type": "array",
                        "description": "The complete plan, in order (max 25 steps)",
                        "items": [
                            "type": "object",
                            "properties": [
                                "title": ["type": "string", "description": "Short imperative step description"],
                                "status": ["type": "string", "enum": ["pending", "in_progress", "done"], "description": "Current step status"]
                            ],
                            "required": ["title", "status"]
                        ] as [String: Any]
                    ] as [String: Any]
                ],
                "required": ["steps"]
            ] as [String: Any]
        ] as [String: Any]
    ]
}
