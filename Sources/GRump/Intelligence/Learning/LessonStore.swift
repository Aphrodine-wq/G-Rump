import Foundation

// MARK: - Lesson Store

/// Durable lessons at `~/.grump/lessons.json` (global scope) and
/// `<project>/.grump/lessons.json` (project scope). @MainActor for sync access
/// from prompt building plus @Published for the Learning panel. Cap 200 active
/// per scope — the weakest active lesson retires to make room.
@MainActor
final class LessonStore: ObservableObject {
    static let shared = LessonStore()

    @Published private(set) var lessons: [Lesson] = []

    private let globalFileURL: URL
    private var projectFileURL: URL?
    private let activeCapPerScope = 200

    static var defaultGlobalFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".grump")
            .appendingPathComponent("lessons.json")
    }

    init(globalFileURL: URL = LessonStore.defaultGlobalFileURL) {
        self.globalFileURL = globalFileURL
        lessons = Self.load(from: globalFileURL, scope: .global)
        runMaintenance()
    }

    /// Points the store at a project; project-scope lessons swap accordingly.
    func setProjectDirectory(_ path: String) {
        let newURL: URL?
        if path.isEmpty {
            newURL = nil
        } else {
            newURL = URL(fileURLWithPath: path)
                .appendingPathComponent(".grump")
                .appendingPathComponent("lessons.json")
        }
        guard newURL != projectFileURL else { return }
        projectFileURL = newURL
        var merged = lessons.filter { $0.scope == .global }
        if let newURL {
            merged += Self.load(from: newURL, scope: .project)
        }
        lessons = merged
        runMaintenance()
    }

    // MARK: - CRUD (reflection ops + tools + panel)

    /// Adds a lesson; near-duplicate text in the same scope reinforces the
    /// existing lesson instead of splitting its track record.
    @discardableResult
    func add(
        text: String,
        category: Lesson.Category,
        triggerKeywords: [String] = [],
        scope: Lesson.Scope,
        provenance: [String] = []
    ) -> Lesson {
        let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Lesson.textLimit))
        if let existingIndex = lessons.firstIndex(where: {
            $0.scope == scope && $0.status != .retired && Self.normalized($0.text) == Self.normalized(trimmed)
        }) {
            lessons[existingIndex].winCount += 1
            lessons[existingIndex].hitCount += 1
            lessons[existingIndex].provenance.append(contentsOf: provenance)
            save(scope: scope)
            return lessons[existingIndex]
        }

        let lesson = Lesson(
            text: trimmed,
            category: category,
            triggerKeywords: triggerKeywords,
            scope: scope,
            provenance: provenance
        )
        lessons.append(lesson)
        enforceCap(scope: scope)
        save(scope: scope)
        mirrorToVaultIfEnabled(lesson)
        return lesson
    }

    func reinforce(id: String) {
        mutate(id: id) { $0.winCount += 1; $0.hitCount += 1; $0.lastHitAt = Date() }
    }

    func weaken(id: String) {
        mutate(id: id) { $0.lossCount += 1; $0.hitCount += 1; $0.lastHitAt = Date() }
        runMaintenance()
    }

    func revise(id: String, newText: String) {
        mutate(id: id) { $0.text = String(newText.prefix(Lesson.textLimit)) }
    }

    func pin(id: String) { mutate(id: id) { $0.status = .pinned } }
    func unpin(id: String) { mutate(id: id) { if $0.status == .pinned { $0.status = .active } } }
    func retire(id: String) { mutate(id: id) { $0.status = .retired } }
    func reactivate(id: String) { mutate(id: id) { $0.status = .active } }

    // MARK: - Injection attribution

    /// A lesson was shown to the model this run.
    func recordInjection(ids: [String]) {
        guard !ids.isEmpty else { return }
        let now = Date()
        for id in ids {
            mutate(id: id, saveAfter: false) { $0.hitCount += 1; $0.lastHitAt = now }
        }
        saveAll()
    }

    /// The run those lessons rode along on succeeded or failed.
    func recordOutcome(ids: [String], success: Bool) {
        guard !ids.isEmpty else { return }
        for id in ids {
            mutate(id: id, saveAfter: false) {
                if success { $0.winCount += 1 } else { $0.lossCount += 1 }
            }
        }
        runMaintenance()
        saveAll()
    }

    // MARK: - Selection

    /// Top lessons for a prompt: pinned first, then relevance × effective
    /// confidence. Retired lessons never surface.
    func relevant(for promptText: String, limit: Int = 5, now: Date = Date()) -> [Lesson] {
        let candidates = lessons.filter { $0.status != .retired }
        let scored = candidates.map { lesson in
            (lesson: lesson, score: lesson.relevance(to: promptText) * lesson.effectiveConfidence(now: now))
        }
        let sorted = scored.sorted { lhs, rhs in
            let lhsPinned = lhs.lesson.status == .pinned
            let rhsPinned = rhs.lesson.status == .pinned
            if lhsPinned != rhsPinned { return lhsPinned }
            return lhs.score > rhs.score
        }
        return sorted.prefix(limit).map(\.lesson)
    }

    /// Compact digest for the reflection prompt (dedup against existing lessons).
    func digest(limit: Int = 30) -> String {
        lessons
            .filter { $0.status != .retired }
            .sorted { $0.effectiveConfidence() > $1.effectiveConfidence() }
            .prefix(limit)
            .map { "[\($0.id)] (\(String(format: "%.2f", $0.confidence)), \($0.scope.rawValue)) \($0.text)" }
            .joined(separator: "\n")
    }

    // MARK: - Maintenance

    /// Auto-retires proven-bad lessons (conf < 0.3 with ≥5 hits, never pinned).
    func runMaintenance(now: Date = Date()) {
        var changed = false
        for index in lessons.indices where lessons[index].status == .active {
            if lessons[index].shouldAutoRetire(now: now) {
                lessons[index].status = .retired
                changed = true
            }
        }
        if changed { saveAll() }
    }

    private func enforceCap(scope: Lesson.Scope) {
        let activeInScope = lessons.enumerated().filter {
            $0.element.scope == scope && $0.element.status == .active
        }
        guard activeInScope.count > activeCapPerScope else { return }
        // Retire the weakest active lesson to stay under the cap.
        if let weakest = activeInScope.min(by: {
            $0.element.effectiveConfidence() < $1.element.effectiveConfidence()
        }) {
            lessons[weakest.offset].status = .retired
        }
    }

    // MARK: - Internals

    private static func normalized(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func mutate(id: String, saveAfter: Bool = true, _ change: (inout Lesson) -> Void) {
        guard let index = lessons.firstIndex(where: { $0.id == id }) else { return }
        change(&lessons[index])
        if saveAfter { save(scope: lessons[index].scope) }
    }

    // MARK: - Persistence

    private func save(scope: Lesson.Scope) {
        let url: URL?
        switch scope {
        case .global: url = globalFileURL
        case .project: url = projectFileURL
        }
        guard let url else { return }
        let scoped = lessons.filter { $0.scope == scope }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(scoped).write(to: url)
        } catch {
            GRumpLogger.persistence.error("LessonStore save failed: \(error.localizedDescription)")
        }
    }

    private func saveAll() {
        save(scope: .global)
        save(scope: .project)
    }

    private static func load(from url: URL, scope: Lesson.Scope) -> [Lesson] {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([Lesson].self, from: data) else {
            return []
        }
        // Scope is implied by which file a lesson lives in; trust the file.
        return decoded.map { lesson in
            var fixed = lesson
            fixed.scope = scope
            return fixed
        }
    }

    /// Write-only vault mirror so lessons show up in the markdown brain.
    private func mirrorToVaultIfEnabled(_ lesson: Lesson) {
        guard BrainConfigStore.shared.load().vaultEnabled else { return }
        let folder = BrainPaths.vaultRoot().appendingPathComponent("Lessons")
        let file = folder.appendingPathComponent("\(lesson.id).md")
        let body = """
        # Lesson \(lesson.id)

        - Category: \(lesson.category.label)
        - Scope: \(lesson.scope.rawValue)
        - Created: \(ISO8601DateFormatter().string(from: lesson.createdAt))

        \(lesson.text)
        """
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(body.utf8).write(to: file)
        } catch {
            GRumpLogger.brain.error("Lesson vault mirror failed: \(error.localizedDescription)")
        }
    }
}
