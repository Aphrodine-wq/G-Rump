import Foundation

// MARK: - Learning Tool Execution
//
// record_lesson, remember — the agent's self-direction surface for the
// learning loop. Additive and user-visible; nothing here mutates code.

extension ChatViewModel {

    func executeRecordLesson(_ args: [String: Any]) async -> String {
        guard BrainConfigStore.shared.load().learningEnabled else {
            return "Learning is disabled in Settings → Brain."
        }
        guard let text = args["text"] as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Error: missing lesson text"
        }
        let category = (args["category"] as? String).flatMap(Lesson.Category.init(rawValue:)) ?? .process
        let keywords = (args["keywords"] as? [String]) ?? []
        let requestedScope = (args["scope"] as? String).flatMap(Lesson.Scope.init(rawValue:))
        // Project scope needs a project; fall back to global rather than dropping the lesson.
        let scope: Lesson.Scope
        if workingDirectory.isEmpty {
            scope = .global
        } else {
            scope = requestedScope ?? .project
        }

        let lesson = LessonStore.shared.add(
            text: text,
            category: category,
            triggerKeywords: keywords,
            scope: scope,
            provenance: ["tool:record_lesson"]
        )
        return "Lesson saved [\(lesson.id)] (\(scope.rawValue), \(category.rawValue)): \(lesson.text)"
    }

    func executeReflect(_ args: [String: Any]) async -> String {
        guard BrainConfigStore.shared.load().learningEnabled else {
            return "Learning is disabled in Settings → Brain."
        }
        guard let outcome = await outcomeLedger.outcomes.last else {
            return "No completed runs to reflect on yet."
        }
        let focus = (args["focus"] as? String) ?? ""
        let injected = LessonStore.shared.lessons.filter { outcome.injectedLessonIds.contains($0.id) }
        var tail = (currentConversation?.messages.suffix(6) ?? [])
            .map { "\($0.role == .user ? "user" : "assistant"): \(String($0.content.prefix(800)))" }
            .joined(separator: "\n---\n")
        if !focus.isEmpty {
            tail = "FOCUS: \(focus)\n\n" + tail
        }
        await outcomeLedger.consumeReflectionCounter()
        guard let result = await ReflectionEngine.shared.reflect(
            outcome: outcome,
            transcriptTail: tail,
            injectedLessons: injected,
            rejectedProposalNames: SkillProposalStore.shared.rejectedNames,
            primaryModel: effectiveModel,
            trigger: "manual"
        ) else {
            return "Reflection didn't run (already reflecting, or the pass failed)."
        }
        return result.noticeText ?? "Reflection ran — no changes were warranted."
    }

    func executeProposeSkill(_ args: [String: Any]) async -> String {
        guard BrainConfigStore.shared.load().learningEnabled else {
            return "Learning is disabled in Settings → Brain."
        }
        guard let skillId = args["skill_id"] as? String, !skillId.isEmpty,
              let name = args["name"] as? String, !name.isEmpty,
              let body = args["body"] as? String, !body.isEmpty else {
            return "Error: skill_id, name, and body are required"
        }
        let lessonIds = (args["lesson_ids"] as? [String]) ?? []
        guard lessonIds.count >= 3 else {
            return "Error: propose_skill requires at least 3 supporting lesson ids — record lessons first."
        }
        let draft = SkillProposalDraft(
            skillId: skillId,
            name: name,
            description: args["description"] as? String ?? "",
            body: body,
            rationale: args["rationale"] as? String ?? "",
            lessonIds: lessonIds
        )
        if let refusal = SkillProposalStore.shared.propose(
            draft: draft, source: "tool:propose_skill", workingDirectory: workingDirectory
        ) {
            return refusal
        }
        return "Skill proposal '\(name)' queued for user review in the Learning panel. Do not assume approval."
    }

    func executeAddGoal(_ args: [String: Any]) async -> String {
        guard let title = args["title"] as? String,
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Error: missing goal title"
        }
        let body = (args["body"] as? String) ?? ""
        let priority = (args["priority"] as? Int) ?? 1
        let store = GoalStore(workingDirectory: workingDirectory)
        let goal = await store.addGoal(title: title, body: body, priority: priority)
        let daemonOn = BrainConfigStore.shared.load().daemonEnabled
        return "Goal queued: \"\(goal.title)\" [\(goal.id)] priority \(priority)."
            + (daemonOn ? " The daemon will pick it up." : " The daemon is currently disabled (Settings → Brain).")
    }

    func executeRemember(_ args: [String: Any]) async -> String {
        guard let content = args["content"] as? String,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Error: missing content"
        }
        let tierString = (args["tier"] as? String) ?? "project"
        let tier: MemoryTier = tierString == "global" ? .global : .project
        if tier == .project && workingDirectory.isEmpty {
            return "Error: no project open — use tier 'global' or open a project first."
        }
        let tags = (args["tags"] as? [String]) ?? []
        await advancedMemory.addEntry(
            tier: tier,
            content: content,
            tags: tags,
            importance: .high,
            conversationId: currentConversation?.id.uuidString
        )
        return "Remembered (\(tier.rawValue) tier): \(String(content.prefix(120)))"
    }
}
