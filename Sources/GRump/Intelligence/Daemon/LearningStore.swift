import Foundation

/// Persists per-key success rates + durations for daemon work, so the daemon can learn
/// which goal types it handles reliably. JSON at `~/.grump/daemon-learning.json`.
actor LearningStore {
    struct Record: Codable, Sendable {
        var attempts: Int = 0
        var successes: Int = 0
        var totalDuration: Double = 0
    }

    private var records: [String: Record] = [:]
    private var loaded = false
    private let path: URL

    init(path: URL? = nil) {
        self.path = path ?? BrainPaths.grumpHome.appendingPathComponent("daemon-learning.json")
    }

    func record(key: String, success: Bool, duration: Double) {
        loadIfNeeded()
        var r = records[key] ?? Record()
        r.attempts += 1
        if success { r.successes += 1 }
        r.totalDuration += duration
        records[key] = r
        save()
    }

    func successRate(for key: String) -> Double {
        loadIfNeeded()
        guard let r = records[key], r.attempts > 0 else { return 0 }
        return Double(r.successes) / Double(r.attempts)
    }

    func averageDuration(for key: String) -> Double {
        loadIfNeeded()
        guard let r = records[key], r.attempts > 0 else { return 0 }
        return r.totalDuration / Double(r.attempts)
    }

    func attempts(for key: String) -> Int {
        loadIfNeeded()
        return records[key]?.attempts ?? 0
    }

    // MARK: - Persistence

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: path),
              let decoded = try? JSONDecoder().decode([String: Record].self, from: data) else { return }
        records = decoded
    }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(records)
            try data.write(to: path, options: .atomic)
        } catch {
            GRumpLogger.brain.error("Learning store save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
