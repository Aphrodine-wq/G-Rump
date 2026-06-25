import Foundation

/// A goal the daemon can work on, persisted as a markdown note in the vault `Goals/` folder.
struct Goal: Sendable, Identifiable, Equatable {
    let id: String          // filename (slug)
    let title: String
    let body: String
    var status: String      // pending | in-progress | done | failed
    let priority: Int       // higher first
    let path: URL
}

/// Actor over markdown goal notes (`<vault>/Goals/<slug>.md`). Frontmatter carries
/// `status` and `priority`. Generic — no preloaded goals.
actor GoalStore {
    private let dir: URL
    private let fm = FileManager.default

    init(workingDirectory: String = "") {
        self.dir = BrainPaths.folder(.goals, workingDirectory: workingDirectory)
    }

    private func ensureDir() {
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    /// Pending goals, highest priority first.
    func pendingGoals() -> [Goal] {
        allGoals().filter { $0.status == "pending" }.sorted { $0.priority > $1.priority }
    }

    func allGoals() -> [Goal] {
        ensureDir()
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
        return files.filter { $0.pathExtension == "md" }.compactMap { read($0) }
    }

    @discardableResult
    func addGoal(title: String, body: String, priority: Int = 1) -> Goal {
        ensureDir()
        let slug = VaultNote.slug(title)
        let url = dir.appendingPathComponent("\(slug).md")
        let goal = Goal(id: slug, title: title, body: body, status: "pending", priority: priority, path: url)
        write(goal)
        return goal
    }

    func markStatus(_ goal: Goal, _ status: String) {
        let updated = Goal(id: goal.id, title: goal.title, body: goal.body, status: status, priority: goal.priority, path: goal.path)
        write(updated)
    }

    // MARK: - Private

    private func read(_ url: URL) -> Goal? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let (fmeta, body) = Frontmatter.parse(content)
        return Goal(
            id: url.deletingPathExtension().lastPathComponent,
            title: fmeta.value("title") ?? url.deletingPathExtension().lastPathComponent,
            body: body,
            status: fmeta.value("status") ?? "pending",
            priority: Int(fmeta.value("priority") ?? "1") ?? 1,
            path: url
        )
    }

    private func write(_ goal: Goal) {
        var meta = Frontmatter()
        meta.set("title", goal.title)
        meta.set("type", "goal")
        meta.set("status", goal.status)
        meta.set("priority", String(goal.priority))
        meta.set("created", VaultNote.today())
        let content = meta.serialized() + "\n\n" + goal.body + "\n"
        do {
            try content.write(to: goal.path, atomically: true, encoding: .utf8)
        } catch {
            GRumpLogger.brain.error("Goal write failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
