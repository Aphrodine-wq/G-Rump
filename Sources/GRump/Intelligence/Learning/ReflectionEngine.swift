import Foundation

// MARK: - Reflection Ops

/// One operation the reflection model asked for. Lesson ops apply immediately
/// (transparent, reversible in the Learning panel); skill proposals are ALWAYS
/// approval-gated and only ever become drafts.
enum ReflectionOp: Equatable {
    case add(text: String, category: Lesson.Category, keywords: [String], scope: Lesson.Scope)
    case reinforce(id: String)
    case weaken(id: String)
    case revise(id: String, text: String)
    case proposeSkill(draft: SkillProposalDraft)
}

/// A skill the reflection model wants to author — never written directly;
/// stored as a pending proposal for the user to approve as a diff.
struct SkillProposalDraft: Codable, Equatable {
    let skillId: String
    let name: String
    let description: String
    let body: String
    let rationale: String
    let lessonIds: [String]
}

/// What a reflection pass did, for notices and the Learning panel.
struct ReflectionResult: Equatable {
    var added: Int = 0
    var reinforced: Int = 0
    var weakened: Int = 0
    var revised: Int = 0
    var skillProposals: [SkillProposalDraft] = []

    var isEmpty: Bool {
        added == 0 && reinforced == 0 && weakened == 0 && revised == 0 && skillProposals.isEmpty
    }

    var noticeText: String? {
        var parts: [String] = []
        if added > 0 { parts.append("saved \(added) lesson\(added == 1 ? "" : "s")") }
        if reinforced > 0 { parts.append("reinforced \(reinforced)") }
        if weakened > 0 { parts.append("weakened \(weakened)") }
        if revised > 0 { parts.append("revised \(revised)") }
        if !skillProposals.isEmpty { parts.append("proposed \(skillProposals.count) skill change\(skillProposals.count == 1 ? "" : "s") (pending your approval)") }
        guard !parts.isEmpty else { return nil }
        return "Learning: " + parts.joined(separator: ", ") + ". Review in the Learning panel."
    }
}

// MARK: - Reflection Engine

/// Post-run distillation: reads a run's outcome + transcript tail, reasons over
/// the existing lessons' track records, and emits lesson ops + gated skill
/// proposals. Mirrors AdversarialReviewEngine's shape. Max one pass at a time;
/// kill switch = BrainConfig.learningEnabled.
@MainActor
final class ReflectionEngine: ObservableObject {
    static let shared = ReflectionEngine()

    @Published private(set) var isReflecting = false
    @Published private(set) var lastReflectionAt: Date?
    @Published private(set) var lastResult: ReflectionResult?

    private let logger = GRumpLogger.general

    /// Reflect on failure/pivot/critical/correction runs, or every N runs even
    /// when things go well (quiet successes carry lessons too).
    nonisolated static func shouldReflect(outcome: RunOutcome, runsSinceReflection: Int, cadence: Int) -> Bool {
        outcome.isReflectionWorthy || runsSinceReflection >= max(1, cadence)
    }

    /// Runs one reflection pass and applies its lesson ops. Returns nil when
    /// learning is off, a pass is already running, or the model call fails.
    func reflect(
        outcome: RunOutcome,
        transcriptTail: String,
        injectedLessons: [Lesson],
        rejectedProposalNames: [String],
        primaryModel: EnhancedAIModel,
        trigger: String
    ) async -> ReflectionResult? {
        guard BrainConfigStore.shared.load().learningEnabled else { return nil }
        guard !isReflecting else { return nil }
        isReflecting = true
        defer { isReflecting = false }

        let model = ModelRouter.route(taskType: .reflection, fallback: primaryModel)
        let userContent = Self.buildReflectionInput(
            outcome: outcome,
            transcriptTail: transcriptTail,
            injectedLessons: injectedLessons,
            lessonDigest: LessonStore.shared.digest(),
            rejectedProposalNames: rejectedProposalNames,
            trigger: trigger
        )
        let messages: [Message] = [
            Message(role: .system, content: Self.systemPrompt),
            Message(role: .user, content: userContent)
        ]

        var fullResponse = ""
        do {
            let stream = MultiProviderAIService.stream(messages: messages, modelID: model.rawValue)
            for try await event in stream {
                if case .text(let chunk) = event { fullResponse += chunk }
            }
        } catch {
            logger.error("ReflectionEngine failed: \(error.localizedDescription)")
            return nil
        }

        let ops = Self.parseOps(from: fullResponse)
        let result = apply(ops: ops, provenance: [outcome.id.uuidString, "trigger:\(trigger)"])
        lastReflectionAt = Date()
        lastResult = result
        logger.info("Reflection (\(trigger)): +\(result.added) lessons, \(result.skillProposals.count) proposals")
        return result
    }

    // MARK: - Applying ops

    private func apply(ops: [ReflectionOp], provenance: [String]) -> ReflectionResult {
        var result = ReflectionResult()
        let store = LessonStore.shared
        for op in ops {
            switch op {
            case .add(let text, let category, let keywords, let scope):
                store.add(text: text, category: category, triggerKeywords: keywords,
                          scope: scope, provenance: provenance)
                result.added += 1
            case .reinforce(let id):
                store.reinforce(id: id)
                result.reinforced += 1
            case .weaken(let id):
                store.weaken(id: id)
                result.weakened += 1
            case .revise(let id, let text):
                store.revise(id: id, newText: text)
                result.revised += 1
            case .proposeSkill(let draft):
                // Never applied here — the proposal store + Learning panel own the gate.
                if SkillProposalStore.shared.propose(draft: draft, source: "reflection") == nil {
                    result.skillProposals.append(draft)
                }
            }
        }
        return result
    }

    // MARK: - Prompt

    static let systemPrompt = """
    You are the reflection pass of a coding agent's learning loop. You read one \
    completed run and distill DURABLE lessons — rules that would change how the \
    agent behaves next time. You also manage the existing lesson list's accuracy.

    Respond with ONLY a JSON array of operations:
    [
      {"op": "add", "text": "One imperative sentence, max 280 chars", "category": "tool_use|code_style|project_fact|process|user_preference", "keywords": ["trigger", "words"], "scope": "project|global"},
      {"op": "reinforce", "id": "existing-lesson-id"},
      {"op": "weaken", "id": "existing-lesson-id"},
      {"op": "revise", "id": "existing-lesson-id", "text": "better wording"},
      {"op": "propose_skill", "skill_id": "kebab-case-id", "name": "Skill name", "description": "when to use", "body": "full SKILL.md markdown body", "rationale": "why", "lesson_ids": ["id1", "id2", "id3"]}
    ]

    Rules:
    - Lessons must be durable and behavioral ("Run xcodegen after editing project.yml"), \
    never run-specific narration ("The build failed today").
    - Do not add a lesson that duplicates one in the existing digest — reinforce or revise it instead.
    - If an injected lesson clearly misled this run, weaken it.
    - propose_skill ONLY when at least 3 existing lessons cluster around one workflow, and \
    cite them in lesson_ids. Skill proposals are reviewed by the user as diffs — never assume approval.
    - Never re-propose a skill matching a rejected proposal name.
    - Prefer zero ops over weak ops. An empty array [] is a good answer for an unremarkable run.
    """

    /// Assembles the ~6k-token reflection input.
    nonisolated static func buildReflectionInput(
        outcome: RunOutcome,
        transcriptTail: String,
        injectedLessons: [Lesson],
        lessonDigest: String,
        rejectedProposalNames: [String],
        trigger: String
    ) -> String {
        var sections: [String] = []
        sections.append("Trigger: \(trigger)")

        let toolLines = outcome.toolStats
            .map { "\($0.name): \($0.calls) calls, \($0.failures) failures" }
            .joined(separator: "; ")
        sections.append("""
        ## Run outcome
        id: \(outcome.id.uuidString)
        task type: \(outcome.taskType) · iterations: \(outcome.iterations) · success: \(outcome.success)\(outcome.amended ? " (amended by user correction)" : "")
        tools: \(toolLines.isEmpty ? "none" : toolLines)
        build failures: \(outcome.buildFailures) · loop pivots: \(outcome.loopPivots) · adversarial criticals: \(outcome.adversarialCriticals)
        \(outcome.regressionSummary.map { "regression: \($0)" } ?? "")
        \(outcome.userCorrections.isEmpty ? "" : "user corrections: \(outcome.userCorrections.joined(separator: " | "))")
        """)

        if !injectedLessons.isEmpty {
            let lines = injectedLessons.map {
                "[\($0.id)] (conf \(String(format: "%.2f", $0.confidence)), \($0.hitCount) hits) \($0.text)"
            }.joined(separator: "\n")
            sections.append("## Lessons injected into this run\n\(lines)")
        }

        if !lessonDigest.isEmpty {
            sections.append("## Existing lesson digest (do not duplicate)\n\(lessonDigest)")
        }

        if !rejectedProposalNames.isEmpty {
            sections.append("## Rejected skill proposals (never re-propose)\n" + rejectedProposalNames.joined(separator: "\n"))
        }

        sections.append("## Transcript tail\n\(String(transcriptTail.suffix(12_000)))")
        return sections.joined(separator: "\n\n")
    }

    // MARK: - Parsing

    /// Parses the ops array; tolerant of markdown fences and prose padding.
    nonisolated static func parseOps(from response: String) -> [ReflectionOp] {
        var cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            let lines = cleaned.components(separatedBy: "\n")
            cleaned = lines.dropFirst().dropLast().joined(separator: "\n")
        }
        var array = decodeArray(cleaned)
        if array == nil,
           let start = cleaned.firstIndex(of: "["),
           let end = cleaned.lastIndex(of: "]") {
            array = decodeArray(String(cleaned[start...end]))
        }
        return (array ?? []).compactMap(parseSingleOp)
    }

    nonisolated private static func decodeArray(_ text: String) -> [[String: Any]]? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
    }

    nonisolated private static func parseSingleOp(_ dict: [String: Any]) -> ReflectionOp? {
        guard let op = dict["op"] as? String else { return nil }
        switch op {
        case "add":
            guard let text = dict["text"] as? String, !text.isEmpty else { return nil }
            let category = (dict["category"] as? String).flatMap(Lesson.Category.init(rawValue:)) ?? .process
            let keywords = (dict["keywords"] as? [String]) ?? []
            let scope = (dict["scope"] as? String).flatMap(Lesson.Scope.init(rawValue:)) ?? .project
            return .add(text: text, category: category, keywords: keywords, scope: scope)
        case "reinforce":
            guard let id = dict["id"] as? String else { return nil }
            return .reinforce(id: id)
        case "weaken":
            guard let id = dict["id"] as? String else { return nil }
            return .weaken(id: id)
        case "revise":
            guard let id = dict["id"] as? String, let text = dict["text"] as? String else { return nil }
            return .revise(id: id, text: text)
        case "propose_skill":
            guard let skillId = dict["skill_id"] as? String,
                  let name = dict["name"] as? String,
                  let body = dict["body"] as? String else { return nil }
            let lessonIds = (dict["lesson_ids"] as? [String]) ?? []
            // The ≥3-cluster rule is enforced here, not just prompted.
            guard lessonIds.count >= 3 else { return nil }
            return .proposeSkill(draft: SkillProposalDraft(
                skillId: skillId,
                name: name,
                description: dict["description"] as? String ?? "",
                body: body,
                rationale: dict["rationale"] as? String ?? "",
                lessonIds: lessonIds
            ))
        default:
            return nil
        }
    }
}
