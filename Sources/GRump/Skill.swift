import Foundation

/// A Cursor-style skill: SKILL.md with YAML frontmatter (name, description) + markdown body.
struct Skill: Identifiable, Equatable {
    static func == (lhs: Skill, rhs: Skill) -> Bool { lhs.id == rhs.id }
    let id: String
    let name: String
    let description: String
    let path: URL
    let scope: Scope
    let body: String

    /// Base ID (e.g. "code-review" from "global:code-review").
    var baseId: String {
        if let colon = id.firstIndex(of: ":") {
            return String(id[id.index(after: colon)...])
        }
        return id
    }

    /// True if this skill is one of the bundled built-in skills.
    var isBuiltIn: Bool {
        Skill.builtInBaseIds.contains(baseId)
    }

    /// Base IDs of bundled skills (used for Built-in badge and section).
    static let builtInBaseIds: Set<String> = [
        "code-review", "debugging", "documentation", "refactoring", "research", "testing", "writing",
        "plan", "full-stack", "spec", "argue",
        "security-audit", "performance", "api-design", "database-design",
        "devops", "code-migration", "accessibility", "test-generation",
        "swift-ios", "ci-cd", "monorepo", "docker-deploy", "code-review-pr", "rapid-prototype",
        // Apple ecosystem
        "swiftui-migration", "swiftdata", "async-await", "app-store-prep", "privacy-manifest",
        // AI/ML
        "coreml-conversion", "prompt-engineering", "mlx-training",
        // Business
        "pitch-deck", "technical-dd", "competitive-analysis",
        // Specialized
        "regex", "graphql", "terraform", "kubernetes",
        // Cross-platform stacks
        "react-nextjs", "python-fastapi", "rust-systems", "flutter-dart",
        "unity-gamedev", "data-science", "aws-serverless", "system-design"
    ]

    enum Scope: String {
        case global
        case project
        case builtIn
    }
}

/// Loads skills from ~/.grump/skills/ and project .grump/skills/.
enum SkillsStorage {
    private static let skillFileName = "SKILL.md"

    static var globalSkillsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".grump")
            .appendingPathComponent("skills")
    }

    static func projectSkillsDirectory(workingDirectory: String) -> URL {
        guard !workingDirectory.isEmpty else {
            return URL(fileURLWithPath: "/dev/null")
        }
        return URL(fileURLWithPath: (workingDirectory as NSString).standardizingPath)
            .appendingPathComponent(".grump")
            .appendingPathComponent("skills")
    }

    /// Load all skills (global + project). Project skills take precedence for same ID.
    static func loadSkills(workingDirectory: String = "") -> [Skill] {
        var byId: [String: Skill] = [:]
        for skill in loadSkills(from: globalSkillsDirectory, scope: .global) {
            byId[skill.id] = skill
        }
        if !workingDirectory.isEmpty {
            let projectDir = projectSkillsDirectory(workingDirectory: workingDirectory)
            for skill in loadSkills(from: projectDir, scope: .project) {
                byId[skill.id] = skill
            }
        }
        return Array(byId.values).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func loadSkills(from dir: URL, scope: Skill.Scope) -> [Skill] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: dir.path),
              let contents = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles) else {
            return []
        }
        var skills: [Skill] = []
        for item in contents {
            guard (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let skillFile = item.appendingPathComponent(skillFileName)
            guard fm.fileExists(atPath: skillFile.path),
                  let content = try? String(contentsOf: skillFile, encoding: .utf8) else {
                continue
            }
            if let skill = parseSkill(content, baseURL: item, scope: scope) {
                skills.append(skill)
            }
        }
        return skills
    }

    private static func parseSkill(_ content: String, baseURL: URL, scope: Skill.Scope) -> Skill? {
        let parts = content.components(separatedBy: "\n---\n")
        let frontmatter = parts.first ?? ""
        let body = parts.count > 1 ? parts.dropFirst().joined(separator: "\n---\n").trimmingCharacters(in: .whitespacesAndNewlines) : ""
        let name = extractFrontmatterValue(from: frontmatter, key: "name") ?? baseURL.lastPathComponent
        let description = extractFrontmatterValue(from: frontmatter, key: "description") ?? ""
        let id = "\(scope.rawValue):\(baseURL.lastPathComponent)"
        return Skill(id: id, name: name, description: description, path: baseURL, scope: scope, body: body)
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

    /// Seed bundled skills into ~/.grump/skills/. Idempotent: skips skills that already exist.
    static func seedBundledSkillsIfNeeded() {
        let fm = FileManager.default
        let destDir = globalSkillsDirectory

        try? fm.createDirectory(at: destDir, withIntermediateDirectories: true)

        guard let bundleSkillsURL = Bundle.main.resourceURL?.appendingPathComponent("Skills", isDirectory: true),
              fm.fileExists(atPath: bundleSkillsURL.path),
              let contents = try? fm.contentsOfDirectory(at: bundleSkillsURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else {
            return
        }

        for item in contents {
            let name = item.lastPathComponent
            guard name.hasPrefix("skill-"), name.hasSuffix(".md") else { continue }
            let skillId = String(name.dropFirst("skill-".count).dropLast(".md".count))
            guard !skillId.isEmpty else { continue }

            let destSkillDir = destDir.appendingPathComponent(skillId)
            if fm.fileExists(atPath: destSkillDir.path) { continue }

            try? fm.createDirectory(at: destSkillDir, withIntermediateDirectories: true)
            let destSkillFile = destSkillDir.appendingPathComponent(skillFileName)
            if let content = try? String(contentsOf: item, encoding: .utf8) {
                try? content.write(to: destSkillFile, atomically: true, encoding: .utf8)
            }
        }
    }

    /// Update an existing skill's SKILL.md file.
    static func updateSkill(_ skill: Skill, newName: String, newDescription: String, newBody: String) -> Bool {
        let skillFile = skill.path.appendingPathComponent(skillFileName)
        let content = "---\nname: \(newName)\ndescription: \(newDescription)\n---\n\n\(newBody)"
        do {
            try content.write(to: skillFile, atomically: true, encoding: .utf8)
            return true
        } catch {
            GRumpLogger.skills.error("Failed to update skill: \(error.localizedDescription)")
            return false
        }
    }

    /// Create a new skill directory and SKILL.md with template.
    static func createSkill(id: String, name: String, description: String = "", scope: Skill.Scope, workingDirectory: String = "") -> Skill? {
        let dir: URL
        switch scope {
        case .global, .builtIn:
            dir = globalSkillsDirectory.appendingPathComponent(id)
        case .project:
            guard !workingDirectory.isEmpty else { return nil }
            dir = projectSkillsDirectory(workingDirectory: workingDirectory).appendingPathComponent(id)
        }
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let skillFile = dir.appendingPathComponent(skillFileName)
        let desc = description.isEmpty ? "Instructions for \(name)." : description
        let template = "---\nname: \(name)\ndescription: \(desc)\n---\n\n# \(name)\n\nAdd your instructions here."
        guard (try? template.write(to: skillFile, atomically: true, encoding: .utf8)) != nil else { return nil }
        return Skill(id: "\(scope.rawValue):\(id)", name: name, description: desc, path: dir, scope: scope, body: "# \(name)\n\nAdd your instructions here.")
    }
}
