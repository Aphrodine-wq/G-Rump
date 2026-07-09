import Foundation

// MARK: - Run Outcome

/// One agent run's observable signals, persisted so reflection can learn from
/// them after the session objects have evaporated.
struct RunOutcome: Codable, Identifiable, Equatable {
    struct ToolStat: Codable, Equatable {
        let name: String
        var calls: Int
        var failures: Int
    }

    let id: UUID
    let timestamp: Date
    let conversationId: UUID?
    let taskType: String            // TaskType.rawValue via classify(from:)
    let iterations: Int
    let toolStats: [ToolStat]
    let buildFailures: Int
    let loopPivots: Int
    let regressionSummary: String?
    let adversarialCriticals: Int
    var injectedLessonIds: [String]
    var userCorrections: [String]
    /// Two-stage: provisional at post-run; flipped false when the user's next
    /// message is classified as a correction.
    var success: Bool
    var amended: Bool

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        conversationId: UUID?,
        taskType: String,
        iterations: Int,
        toolStats: [ToolStat],
        buildFailures: Int,
        loopPivots: Int,
        regressionSummary: String?,
        adversarialCriticals: Int,
        injectedLessonIds: [String] = [],
        userCorrections: [String] = [],
        success: Bool,
        amended: Bool = false
    ) {
        self.id = id
        self.timestamp = timestamp
        self.conversationId = conversationId
        self.taskType = taskType
        self.iterations = iterations
        self.toolStats = toolStats
        self.buildFailures = buildFailures
        self.loopPivots = loopPivots
        self.regressionSummary = regressionSummary
        self.adversarialCriticals = adversarialCriticals
        self.injectedLessonIds = injectedLessonIds
        self.userCorrections = userCorrections
        self.success = success
        self.amended = amended
    }

    /// True when this run should trigger a reflection pass on its own.
    var isReflectionWorthy: Bool {
        !success || buildFailures > 0 || loopPivots > 0 || adversarialCriticals > 0 || !userCorrections.isEmpty
    }
}

// MARK: - Task classification

extension TaskType {
    /// Cheap keyword classification of a user request into a task type —
    /// enough signal for outcome grouping and daemon goal scoring.
    static func classify(from message: String) -> TaskType {
        let lower = message.lowercased()
        let table: [(TaskType, [String])] = [
            (.debugging, ["fix", "bug", "crash", "broken", "error", "fails", "failing"]),
            (.testing, ["test", "coverage", "xctest", "spec"]),
            (.planning, ["plan", "design", "architecture", "roadmap", "spec out"]),
            (.research, ["research", "compare", "investigate", "look up", "find out"]),
            (.writing, ["write up", "document", "readme", "blog", "docs"]),
            (.search, ["search", "find", "grep", "locate", "where is"]),
            (.web, ["fetch", "http", "url", "website", "scrape"]),
            (.fileOps, ["rename", "move file", "delete file", "organize"]),
            (.codeGen, ["build", "implement", "add", "create", "refactor", "feature"])
        ]
        for (type, keywords) in table where keywords.contains(where: { lower.contains($0) }) {
            return type
        }
        return .general
    }
}

// MARK: - Outcome Ledger

/// Durable per-project run history at `<project>/.grump/outcomes.json`
/// (cap 500, oldest dropped). No project open → in-memory only.
actor OutcomeLedger {
    private(set) var outcomes: [RunOutcome] = []
    /// Runs recorded since the last reflection pass consumed the counter.
    private(set) var runsSinceReflection = 0

    private var fileURL: URL?
    private let cap = 500

    /// Points the ledger at a project (empty path → in-memory only) and
    /// hydrates any existing history.
    func setProjectDirectory(_ path: String) {
        guard !path.isEmpty else {
            fileURL = nil
            outcomes = []
            return
        }
        let url = URL(fileURLWithPath: path)
            .appendingPathComponent(".grump")
            .appendingPathComponent("outcomes.json")
        guard url != fileURL else { return }
        fileURL = url
        outcomes = Self.load(from: url)
    }

    func record(_ outcome: RunOutcome) {
        outcomes.append(outcome)
        if outcomes.count > cap {
            outcomes.removeFirst(outcomes.count - cap)
        }
        runsSinceReflection += 1
        save()
    }

    /// Two-stage success: the user's next message was a correction, so the
    /// previous run didn't actually succeed. Returns the amended run's
    /// injected lesson ids so their confidence can take the loss too.
    @discardableResult
    func amendLastOutcome(corrections: [String]) -> [String] {
        guard !corrections.isEmpty, var last = outcomes.last else { return [] }
        last.success = false
        last.amended = true
        last.userCorrections.append(contentsOf: corrections)
        outcomes[outcomes.count - 1] = last
        save()
        return last.injectedLessonIds
    }

    func consumeReflectionCounter() {
        runsSinceReflection = 0
    }

    func recent(_ limit: Int) -> [RunOutcome] {
        Array(outcomes.suffix(limit))
    }

    func outcomes(taskType: String) -> [RunOutcome] {
        outcomes.filter { $0.taskType == taskType }
    }

    /// Success rate for a task type — Laplace-smoothed so single runs don't
    /// read as certainty.
    func successRate(taskType: String) -> Double {
        let runs = outcomes(taskType: taskType)
        let wins = runs.filter(\.success).count
        return Double(wins + 1) / Double(runs.count + 2)
    }

    // MARK: - Persistence

    private func save() {
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(outcomes).write(to: fileURL)
        } catch {
            GRumpLogger.persistence.error("OutcomeLedger save failed: \(error.localizedDescription)")
        }
    }

    private static func load(from url: URL) -> [RunOutcome] {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([RunOutcome].self, from: data) else {
            return []
        }
        return decoded
    }
}
