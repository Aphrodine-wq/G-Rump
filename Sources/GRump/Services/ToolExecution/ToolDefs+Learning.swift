import Foundation

// MARK: - Learning Tool Definitions
//
// Self-direction tools for the learning loop. record_lesson and remember are
// ungated (visible, additive, reversible in the Learning panel); skill
// proposals and goals go through their own gates.

extension ToolDefinitions {

    nonisolated(unsafe) static let recordLesson: [String: Any] = [
        "type": "function",
        "function": [
            "name": "record_lesson",
            "description": "Save a durable lesson learned during this run (e.g. a pitfall to avoid, a project convention, a tool quirk). Lessons are injected into future runs when relevant, tracked for accuracy, and visible to the user in the Learning panel. Keep it to one imperative sentence.",
            "parameters": [
                "type": "object",
                "properties": [
                    "text": ["type": "string", "description": "The lesson, imperative, max 280 chars (e.g. 'Run make generate after editing project.yml in this repo')"],
                    "category": ["type": "string", "description": "'tool_use', 'code_style', 'project_fact', 'process', or 'user_preference' (default: process)"],
                    "keywords": ["type": "array", "items": ["type": "string"], "description": "Trigger keywords — the lesson surfaces when a request mentions them"],
                    "scope": ["type": "string", "description": "'project' (default when a project is open) or 'global'"]
                ],
                "required": ["text"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    nonisolated(unsafe) static let reflectTool: [String: Any] = [
        "type": "function",
        "function": [
            "name": "reflect",
            "description": "Run a reflection pass over the most recent completed run: distill durable lessons, adjust existing lesson confidence, and (rarely) propose a skill for user approval. Use when you notice a pattern worth keeping, or when the user asks you to learn from what just happened.",
            "parameters": [
                "type": "object",
                "properties": [
                    "focus": ["type": "string", "description": "Optional: what to pay attention to (e.g. 'the build failures')"]
                ],
                "required": []
            ] as [String: Any]
        ] as [String: Any]
    ]

    nonisolated(unsafe) static let proposeSkill: [String: Any] = [
        "type": "function",
        "function": [
            "name": "propose_skill",
            "description": "Propose a new or updated SKILL.md for the user to review. The proposal appears in the Learning panel as a diff and does NOTHING until the user approves it — never assume it was accepted. Requires at least 3 recorded lessons clustering around one workflow (cite their ids).",
            "parameters": [
                "type": "object",
                "properties": [
                    "skill_id": ["type": "string", "description": "kebab-case skill id (e.g. 'xcodegen-workflow')"],
                    "name": ["type": "string", "description": "Human-readable skill name"],
                    "description": ["type": "string", "description": "One-line description (when to use the skill)"],
                    "body": ["type": "string", "description": "Full SKILL.md markdown body"],
                    "rationale": ["type": "string", "description": "Why this skill should exist"],
                    "lesson_ids": ["type": "array", "items": ["type": "string"], "description": "≥3 lesson ids this skill is distilled from"]
                ],
                "required": ["skill_id", "name", "body", "lesson_ids"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    nonisolated(unsafe) static let rememberTool: [String: Any] = [
        "type": "function",
        "function": [
            "name": "remember",
            "description": "Store a fact in persistent memory (hybrid vector + keyword recall in future conversations). Use for durable facts about the project or user — not for lessons about your own behavior (use record_lesson for those).",
            "parameters": [
                "type": "object",
                "properties": [
                    "content": ["type": "string", "description": "The fact to remember"],
                    "tier": ["type": "string", "description": "'project' (default) or 'global'"],
                    "tags": ["type": "array", "items": ["type": "string"], "description": "Optional tags for retrieval"]
                ],
                "required": ["content"]
            ] as [String: Any]
        ] as [String: Any]
    ]
}
