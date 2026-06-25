import Foundation

/// A persistent agent "mind": MIND.md with YAML frontmatter + markdown body, parallel to
/// SOUL.md. Holds identity (`# Self`), values (`# Conscience`), and what to surface
/// (`# Awareness`). Global at `~/.grump/MIND.md`; project `.grump/MIND.md` overrides.
struct Mind: Equatable {
    let name: String
    let body: String
    let path: URL
    let scope: Scope

    enum Scope: String {
        case global
        case project
    }
}

enum MindStorage {
    private static let fileName = "MIND.md"

    static var globalPath: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".grump")
            .appendingPathComponent(fileName)
    }

    static func projectPath(workingDirectory: String) -> URL? {
        guard !workingDirectory.isEmpty else { return nil }
        return URL(fileURLWithPath: (workingDirectory as NSString).standardizingPath)
            .appendingPathComponent(".grump")
            .appendingPathComponent(fileName)
    }

    /// Load the effective mind (project overrides global), reusing the shared `Frontmatter` parser.
    static func loadMind(workingDirectory: String = "") -> Mind? {
        if !workingDirectory.isEmpty,
           let p = projectPath(workingDirectory: workingDirectory),
           let m = load(from: p, scope: .project) {
            return m
        }
        return load(from: globalPath, scope: .global)
    }

    private static func load(from path: URL, scope: Mind.Scope) -> Mind? {
        guard FileManager.default.fileExists(atPath: path.path),
              let content = try? String(contentsOf: path, encoding: .utf8) else { return nil }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let (fm, body) = Frontmatter.parse(content)
        let name = fm.value("name") ?? "Mind"
        return Mind(name: name, body: body, path: path, scope: scope)
    }

    @discardableResult
    static func saveMind(content: String, scope: Mind.Scope, workingDirectory: String = "") -> Bool {
        let path: URL
        switch scope {
        case .global: path = globalPath
        case .project:
            guard let p = projectPath(workingDirectory: workingDirectory) else { return false }
            path = p
        }
        let dir = path.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        do {
            try content.write(to: path, atomically: true, encoding: .utf8)
            return true
        } catch {
            GRumpLogger.brain.error("Failed to save MIND.md: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    static func mindExists(scope: Mind.Scope, workingDirectory: String = "") -> Bool {
        switch scope {
        case .global: return FileManager.default.fileExists(atPath: globalPath.path)
        case .project:
            guard let p = projectPath(workingDirectory: workingDirectory) else { return false }
            return FileManager.default.fileExists(atPath: p.path)
        }
    }

    static func rawContent(scope: Mind.Scope, workingDirectory: String = "") -> String? {
        switch scope {
        case .global: return try? String(contentsOf: globalPath, encoding: .utf8)
        case .project:
            guard let p = projectPath(workingDirectory: workingDirectory) else { return nil }
            return try? String(contentsOf: p, encoding: .utf8)
        }
    }

    /// Seed a neutral, generic MIND.md if none exists. No personal values baked in.
    static func seedDefaultMindIfNeeded() {
        guard !mindExists(scope: .global) else { return }
        _ = saveMind(content: defaultMindContent, scope: .global)
    }

    static let defaultMindContent = """
    ---
    name: Mind
    version: 1
    ---

    # Self

    This is your agent's persistent identity — who it is across sessions. Edit it to shape
    your assistant's character, commitments, and what it cares about.

    # Conscience

    Values the agent holds when deciding whether to act. The Conscience gate refuses
    actions that conflict with these or that happen while a sensitive surface (a payment,
    login, or secret) is on screen.

    - Never act on or exfiltrate sensitive on-screen data (cards, passwords, secrets).
    - Never push to a protected branch (main/master) without explicit human approval.
    - Prefer the reversible action; when unsure, refuse and ask.

    # Awareness

    Metrics the agent surfaces about its own behavior (focus drift, confidence calibration).
    """
}
