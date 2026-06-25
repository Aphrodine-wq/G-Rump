import Foundation
#if canImport(SQLite3)
import SQLite3
#endif

/// Actor-isolated SQLite store for screen observations, kept in its own DB
/// (`~/.grump/observations.sqlite`) so the ~10s capture path never contends with the
/// chat memory DB. Mirrors the direct `sqlite3` C-API pattern used by `SQLiteMemoryDB`.
actor ObservationStore {
    private var db: OpaquePointer?
    private let path: String

    init(path: String? = nil) {
        let resolved = path ?? BrainPaths.grumpHome.appendingPathComponent("observations.sqlite").path
        self.path = resolved
    }

    /// Open (or create) the database. Call once before use.
    func open() {
        let dir = (path as NSString).deletingLastPathComponent
        if !FileManager.default.fileExists(atPath: dir) {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }
        if sqlite3_open(path, &db) != SQLITE_OK {
            GRumpLogger.capture.error("Failed to open observations DB at \(self.path, privacy: .public)")
            db = nil
            return
        }
        exec("PRAGMA journal_mode=WAL")
        exec("PRAGMA synchronous=NORMAL")
        exec("""
            CREATE TABLE IF NOT EXISTS observations (
                id TEXT PRIMARY KEY,
                ts REAL NOT NULL,
                app TEXT,
                window_title TEXT,
                phash TEXT,
                text TEXT,
                project TEXT,
                activity TEXT,
                entities TEXT
            )
        """)
        exec("CREATE INDEX IF NOT EXISTS idx_obs_ts ON observations(ts)")
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    func insert(_ obs: Observation) {
        guard let db else { return }
        let sql = """
            INSERT OR REPLACE INTO observations
            (id, ts, app, window_title, phash, text, project, activity, entities)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        let entitiesJSON = (try? JSONEncoder().encode(obs.entities)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        bindText(stmt, 1, obs.id.uuidString)
        sqlite3_bind_double(stmt, 2, obs.timestamp.timeIntervalSince1970)
        bindText(stmt, 3, obs.app)
        bindText(stmt, 4, obs.windowTitle)
        bindText(stmt, 5, String(obs.phash, radix: 16))
        bindText(stmt, 6, obs.redactedText)
        bindText(stmt, 7, obs.project)
        bindText(stmt, 8, obs.activity)
        bindText(stmt, 9, entitiesJSON)
        sqlite3_step(stmt)
    }

    /// Most recent observations, newest first.
    func recent(limit: Int = 20) -> [Observation] {
        guard let db else { return [] }
        let sql = "SELECT id, ts, app, window_title, phash, text, project, activity, entities FROM observations ORDER BY ts DESC LIMIT ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(limit))

        var out: [Observation] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let obs = readRow(stmt) { out.append(obs) }
        }
        return out
    }

    /// The single most recent observation (used by the Conscience surface classifier).
    func latest() -> Observation? {
        recent(limit: 1).first
    }

    func count() -> Int {
        guard let db else { return 0 }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM observations", -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int(stmt, 0)) : 0
    }

    // MARK: - Private

    private func readRow(_ stmt: OpaquePointer?) -> Observation? {
        func col(_ i: Int32) -> String {
            guard let c = sqlite3_column_text(stmt, i) else { return "" }
            return String(cString: c)
        }
        let id = UUID(uuidString: col(0)) ?? UUID()
        let ts = sqlite3_column_double(stmt, 1)
        let phash = UInt64(col(4), radix: 16) ?? 0
        let entities = (try? JSONDecoder().decode([String].self, from: Data(col(8).utf8))) ?? []
        return Observation(
            id: id,
            timestamp: Date(timeIntervalSince1970: ts),
            app: col(2),
            windowTitle: col(3),
            phash: phash,
            redactedText: col(5),
            project: col(6),
            activity: col(7),
            entities: entities
        )
    }

    private func bindText(_ stmt: OpaquePointer?, _ index: Int32, _ value: String) {
        sqlite3_bind_text(stmt, index, (value as NSString).utf8String, -1, nil)
    }

    private func exec(_ sql: String) {
        guard let db else { return }
        sqlite3_exec(db, sql, nil, nil, nil)
    }
}
