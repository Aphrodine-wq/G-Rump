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
