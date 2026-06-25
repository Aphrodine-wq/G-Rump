import Foundation

/// A persistent agent identity file: SOUL.md with YAML frontmatter (name, version) + markdown body.
/// Global soul lives at ~/.grump/SOUL.md. Project soul lives at .grump/SOUL.md (overrides global).
struct Soul: Equatable {
    let name: String
    let version: Int
    let body: String
    let path: URL
    let scope: Scope

    enum Scope: String {
        case global
        case project
    }
}

// MARK: - SoulStorage

enum SoulStorage {
    private static let soulFileName = "SOUL.md"

    static var globalSoulPath: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".grump")
            .appendingPathComponent(soulFileName)
    }

    static func projectSoulPath(workingDirectory: String) -> URL? {
        guard !workingDirectory.isEmpty else { return nil }
        return URL(fileURLWithPath: (workingDirectory as NSString).standardizingPath)
            .appendingPathComponent(".grump")
            .appendingPathComponent(soulFileName)
    }

    /// Load the effective soul. Project soul overrides global if present.
    static func loadSoul(workingDirectory: String = "") -> Soul? {
        // Project soul takes precedence
        if !workingDirectory.isEmpty,
           let projectPath = projectSoulPath(workingDirectory: workingDirectory),
           let soul = loadSoul(from: projectPath, scope: .project) {
            return soul
        }
        // Fall back to global
        return loadSoul(from: globalSoulPath, scope: .global)
    }

    /// Load soul from a specific path.
    private static func loadSoul(from path: URL, scope: Soul.Scope) -> Soul? {
        guard FileManager.default.fileExists(atPath: path.path),
              let content = try? String(contentsOf: path, encoding: .utf8) else {
            return nil
        }
        return parseSoul(content, path: path, scope: scope)
    }

    /// Parse SOUL.md content with YAML frontmatter.
    private static func parseSoul(_ content: String, path: URL, scope: Soul.Scope) -> Soul? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var name = "Rump"
        var version = 1
        var body = trimmed

        // Parse frontmatter if present
        if trimmed.hasPrefix("---") {
            let parts = trimmed.components(separatedBy: "\n---\n")
            if parts.count >= 2 {
                let frontmatter = parts[0]
                body = parts.dropFirst().joined(separator: "\n---\n").trimmingCharacters(in: .whitespacesAndNewlines)

                if let n = extractFrontmatterValue(from: frontmatter, key: "name") {
                    name = n
                }
                if let v = extractFrontmatterValue(from: frontmatter, key: "version"),
                   let vInt = Int(v) {
                    version = vInt
                }
            }
        }

        return Soul(name: name, version: version, body: body, path: path, scope: scope)
    }

    private static func extractFrontmatterValue(from frontmatter: String, key: String) -> String? {
        let lines = frontmatter.components(separatedBy: .newlines)
        let prefix = "\(key):"
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(prefix) {
                let value = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }

    /// Save soul content to the appropriate path.
    static func saveSoul(content: String, scope: Soul.Scope, workingDirectory: String = "") -> Bool {
        let path: URL
        switch scope {
        case .global:
            path = globalSoulPath
        case .project:
            guard let p = projectSoulPath(workingDirectory: workingDirectory) else { return false }
            path = p
        }

        let dir = path.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        do {
            try content.write(to: path, atomically: true, encoding: .utf8)
            return true
        } catch {
            GRumpLogger.general.error("Failed to save SOUL.md: \(error)")
            return false
        }
    }

    /// Delete soul file.
    static func deleteSoul(scope: Soul.Scope, workingDirectory: String = "") -> Bool {
        let path: URL
        switch scope {
        case .global:
            path = globalSoulPath
        case .project:
            guard let p = projectSoulPath(workingDirectory: workingDirectory) else { return false }
            path = p
        }

        do {
            try FileManager.default.removeItem(at: path)
            return true
        } catch {
            return false
        }
    }

    /// Check if a soul file exists for the given scope.
    static func soulExists(scope: Soul.Scope, workingDirectory: String = "") -> Bool {
        let path: URL
        switch scope {
        case .global:
            path = globalSoulPath
        case .project:
            guard let p = projectSoulPath(workingDirectory: workingDirectory) else { return false }
            path = p
        }
        return FileManager.default.fileExists(atPath: path.path)
    }

    /// Raw content of the soul file for editing.
    static func rawContent(scope: Soul.Scope, workingDirectory: String = "") -> String? {
        let path: URL
        switch scope {
        case .global:
            path = globalSoulPath
        case .project:
            guard let p = projectSoulPath(workingDirectory: workingDirectory) else { return nil }
            path = p
        }
        return try? String(contentsOf: path, encoding: .utf8)
    }

    /// Seed a neutral global SOUL.md if none exists.
    /// Ships generic and user-definable — no opinionated persona baked into the product.
    /// Users can switch to the "Standard" template (the original opinionated persona) or
    /// any other in Settings → Soul.
    static func seedDefaultSoulIfNeeded() {
        guard !soulExists(scope: .global) else { return }
        _ = saveSoul(content: neutralSoulContent, scope: .global)
    }

    /// Neutral, generic seed persona. The product default.
    static let neutralSoulContent = """
    ---
    name: Assistant
    version: 1
    ---

    # Identity

    You are a capable AI coding agent. Define your own voice, values, and rules here —
    this file is yours to shape. Edit it in Settings → Soul, or pick a template to start.

    # Rules

    - Be clear and direct. Get to the point.
    - Write tests for non-trivial logic.
    - Never hardcode secrets; use environment variables or the Keychain.
    - Match the conventions of the surrounding code.
    """

    // MARK: - Default Soul

    static let defaultSoulContent = """
---
name: Rump
version: 1
---

# Identity

You are Rump, an elite AI coding agent built into G-Rump — a native macOS app forged on Apple Silicon. You are opinionated, direct, and relentlessly competent. You don't hedge. You ship.

# Expertise

- Swift, SwiftUI, and the entire Apple platform stack (Core ML, Vision, Speech, EventKit, Security)
- Full-stack web: TypeScript, React, Next.js, Node.js, Python, Go, Rust
- Infrastructure: Docker, Kubernetes, Terraform, CI/CD pipelines
- Databases: PostgreSQL, SQLite, Redis, MongoDB
- AI/ML: model fine-tuning, prompt engineering, RAG architectures

# Rules

- Never apologize for being direct. Get to the point.
- Always prefer Apple-native solutions over cross-platform alternatives when building for Apple platforms.
- Write tests. No exceptions.
- Security first: never hardcode secrets, always use environment variables or Keychain.
- Prefer small, focused files over monoliths. If a file exceeds 500 lines, suggest splitting.
- Use modern Swift concurrency (async/await) over Combine where possible.
- Accessibility is not optional. Add VoiceOver labels and respect Dynamic Type.

# Tone

Direct, confident, occasionally witty. Like a senior engineer who respects your time. No corporate speak. No filler. If something is wrong, say so. If something is great, say that too — briefly.

# Context

You run inside G-Rump, a native macOS/iOS AI coding agent. You have access to 100+ tools including file operations, shell commands, git, Docker, browser automation, and Apple-native framework integrations. You can run models on-device via Core ML with zero network dependency. You support MCP servers for extensibility.
"""
}
