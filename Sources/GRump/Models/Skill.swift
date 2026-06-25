// ╔══════════════════════════════════════════════════════════════╗
// ║  Skill.swift                                                ║
// ║  SKILL.md parser, skill packs, storage, and relevance       ║
// ╚══════════════════════════════════════════════════════════════╝

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
        "fine-tuning", "rag-pipeline", "llm-observability", "mcp-server", "ai-agent-design",
        // Business
        "pitch-deck", "technical-dd", "competitive-analysis",
        "competitive-intel", "product-strategy", "pricing-monetization", "growth-analytics", "cost-optimization",
        // Security
        "pentesting", "exploit-analysis", "incident-response", "network-forensics", "reverse-engineering",
        // Writing & Research
        "technical-writing",
        // DevOps & Infrastructure
        "platform-engineering", "observability", "edge-computing",
        // Specialized
        "regex", "graphql", "terraform", "kubernetes",
        // Cross-platform stacks
        "react-nextjs", "python-fastapi", "rust-systems", "flutter-dart",
        "unity-gamedev", "data-science", "aws-serverless", "system-design",
        // Combo skills
        "combo-architect", "combo-deep-dive", "combo-red-team", "combo-ship-it", "combo-teacher", "combo-war-room"
    ]

    enum Scope: String {
        case global
        case project
        case builtIn
    }

    // MARK: - Context-Aware Relevance

    /// Calculate relevance score for a given context (user message + file types in working directory).
    func relevanceScore(for query: String, fileExtensions: Set<String> = []) -> Double {
        let lower = query.lowercased()
        var score = 0.0

        // Keyword matching against skill name and description
        let nameWords = name.lowercased().components(separatedBy: .whitespaces)
        let descWords = description.lowercased().components(separatedBy: .whitespaces)
        let queryWords = Set(lower.components(separatedBy: .whitespaces))

        let nameOverlap = Set(nameWords).intersection(queryWords).count
        score += Double(nameOverlap) * 0.3

        let descOverlap = Set(descWords).intersection(queryWords).count
        score += Double(descOverlap) * 0.15

        // File extension matching
        let extensionKeywords = Skill.extensionToKeywords
        for ext in fileExtensions {
            if let keywords = extensionKeywords[ext] {
                for keyword in keywords {
                    if name.lowercased().contains(keyword) || description.lowercased().contains(keyword) {
                        score += 0.25
                    }
                }
            }
        }

        // Body keyword matches (lighter weight)
        let bodyLower = body.lowercased()
        for word in queryWords where word.count > 3 {
            if bodyLower.contains(word) { score += 0.05 }
        }

        return min(1.0, score)
    }

    /// Map file extensions to relevant skill keywords.
    private static let extensionToKeywords: [String: [String]] = [
        ".swift": ["swift", "ios", "swiftui", "swiftdata", "xcode"],
        ".ts": ["typescript", "react", "next", "node"],
        ".tsx": ["react", "typescript", "next"],
        ".js": ["javascript", "react", "node", "next"],
        ".jsx": ["react", "javascript"],
        ".py": ["python", "fastapi", "django", "data"],
        ".rs": ["rust", "systems"],
        ".go": ["go", "golang"],
        ".dart": ["flutter", "dart"],
        ".tf": ["terraform", "infrastructure"],
        ".yml": ["ci-cd", "docker", "kubernetes"],
        ".yaml": ["ci-cd", "docker", "kubernetes"],
        ".dockerfile": ["docker", "devops"],
        ".graphql": ["graphql", "api"],
        ".sql": ["database", "sql"],
        ".cs": ["unity", "csharp"]
    ]
}

// MARK: - Skill Pack

struct SkillPack: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let description: String
    let skillBaseIds: [String]
    let icon: String

    /// Enable all skills in this pack.
    func enable(allSkills: [Skill]) {
        var allowlist = SkillsSettingsStorage.loadAllowlist()
        for skill in allSkills where skillBaseIds.contains(skill.baseId) {
            allowlist.insert(skill.id)
        }
        SkillsSettingsStorage.saveAllowlist(allowlist)
    }

    /// Disable all skills in this pack.
    func disable(allSkills: [Skill]) {
        var allowlist = SkillsSettingsStorage.loadAllowlist()
        for skill in allSkills where skillBaseIds.contains(skill.baseId) {
            allowlist.remove(skill.id)
        }
        SkillsSettingsStorage.saveAllowlist(allowlist)
    }

    /// Built-in skill packs.
    static let builtInPacks: [SkillPack] = [
        SkillPack(
            id: "ios-dev",
            name: "iOS Development",
            description: "Swift, SwiftUI, SwiftData, App Store prep, accessibility",
            skillBaseIds: ["swift-ios", "swiftui-migration", "swiftdata", "app-store-prep", "accessibility", "async-await", "privacy-manifest"],
            icon: "apple.logo"
        ),
        SkillPack(
            id: "full-stack-web",
            name: "Full Stack Web",
            description: "React/Next.js, TypeScript, API design, databases",
            skillBaseIds: ["react-nextjs", "api-design", "database-design", "graphql"],
            icon: "globe"
        ),
        SkillPack(
            id: "devops",
            name: "DevOps & Infrastructure",
            description: "Docker, CI/CD, Terraform, Kubernetes, monitoring",
            skillBaseIds: ["devops", "docker-deploy", "ci-cd", "terraform", "kubernetes", "aws-serverless", "platform-engineering", "observability"],
            icon: "server.rack"
        ),
        SkillPack(
            id: "code-quality",
            name: "Code Quality",
            description: "Testing, code review, refactoring, documentation",
            skillBaseIds: ["testing", "code-review", "refactoring", "documentation", "security-audit", "performance"],
            icon: "checkmark.shield"
        ),
        SkillPack(
            id: "ai-ml",
            name: "AI & Machine Learning",
            description: "CoreML, prompt engineering, MLX, RAG pipelines, fine-tuning",
            skillBaseIds: ["coreml-conversion", "prompt-engineering", "mlx-training", "fine-tuning", "rag-pipeline", "llm-observability", "ai-agent-design"],
            icon: "brain"
        ),
        SkillPack(
            id: "data-engineering",
            name: "Data Engineering",
            description: "Data science, databases, RAG pipelines, analytics",
            skillBaseIds: ["data-science", "database-design", "rag-pipeline", "growth-analytics"],
            icon: "cylinder.split.1x2"
        ),
        SkillPack(
            id: "mobile-cross-platform",
            name: "Mobile Cross-Platform",
            description: "Flutter/Dart, React Native, Swift iOS — build for every screen",
            skillBaseIds: ["flutter-dart", "react-nextjs", "swift-ios", "swiftui-migration"],
            icon: "iphone.and.arrow.forward"
        ),
        SkillPack(
            id: "game-dev",
            name: "Game Development",
            description: "Unity, system design, performance optimization",
            skillBaseIds: ["unity-gamedev", "system-design", "performance"],
            icon: "gamecontroller"
        ),
        SkillPack(
            id: "security-compliance",
            name: "Security & Compliance",
            description: "Pentesting, exploit analysis, incident response, privacy",
            skillBaseIds: ["security-audit", "privacy-manifest", "pentesting", "exploit-analysis", "incident-response", "network-forensics", "reverse-engineering"],
            icon: "lock.shield"
        ),
        SkillPack(
            id: "research-writing",
            name: "Research & Writing",
            description: "Technical writing, documentation, research, competitive intel",
            skillBaseIds: ["research", "writing", "documentation", "technical-writing", "competitive-intel"],
            icon: "text.book.closed"
        ),
        SkillPack(
            id: "startup-business",
            name: "Startup & Business",
            description: "Pitch decks, due diligence, competitive analysis, pricing, growth",
            skillBaseIds: ["pitch-deck", "technical-dd", "competitive-analysis", "product-strategy", "pricing-monetization", "growth-analytics", "cost-optimization"],
            icon: "chart.line.uptrend.xyaxis"
        ),
        SkillPack(
            id: "backend-apis",
            name: "Backend & APIs",
            description: "API design, Python/FastAPI, GraphQL, database architecture",
            skillBaseIds: ["api-design", "python-fastapi", "graphql", "database-design"],
            icon: "arrow.left.arrow.right"
        ),
        SkillPack(
            id: "cloud-serverless",
            name: "Cloud & Serverless",
            description: "AWS Lambda, Terraform, edge computing, containerized deploys",
            skillBaseIds: ["aws-serverless", "terraform", "edge-computing", "docker-deploy"],
            icon: "cloud"
        ),
        SkillPack(
            id: "rust-systems",
            name: "Rust & Systems",
            description: "Rust, systems programming, architecture, performance tuning",
            skillBaseIds: ["rust-systems", "system-design", "performance"],
            icon: "cpu"
        ),
        SkillPack(
            id: "debugging-troubleshooting",
            name: "Debugging & Troubleshooting",
            description: "Debugging, testing, observability, incident response",
            skillBaseIds: ["debugging", "testing", "observability", "incident-response"],
            icon: "ant"
        ),
        SkillPack(
            id: "code-modernization",
            name: "Code Migration & Modernization",
            description: "Legacy migration, refactoring, SwiftUI migration, monorepo strategy",
            skillBaseIds: ["code-migration", "refactoring", "swiftui-migration", "monorepo"],
            icon: "arrow.triangle.2.circlepath"
        ),
        SkillPack(
            id: "rapid-prototyping",
            name: "Rapid Prototyping",
            description: "Ship fast — full-stack scaffolding, React, Flutter, quick iteration",
            skillBaseIds: ["rapid-prototype", "full-stack", "react-nextjs", "flutter-dart"],
            icon: "bolt.fill"
        ),
        SkillPack(
            id: "mcp-agents",
            name: "MCP & Agent Building",
            description: "Build MCP servers, design AI agents, prompt craft, LLM monitoring",
            skillBaseIds: ["mcp-server", "ai-agent-design", "prompt-engineering", "llm-observability"],
            icon: "puzzlepiece.extension"
        ),
        SkillPack(
            id: "red-team",
            name: "Red Team & Offensive",
            description: "Pentesting, exploit analysis, reverse engineering, network forensics",
            skillBaseIds: ["pentesting", "exploit-analysis", "reverse-engineering", "network-forensics"],
            icon: "shield.lefthalf.filled.slash"
        ),
        SkillPack(
            id: "combo-workflows",
            name: "Combo Workflows",
            description: "Pre-built multi-skill combos: architect, deep-dive, red-team, ship-it, teacher, war-room",
            skillBaseIds: ["combo-architect", "combo-deep-dive", "combo-red-team", "combo-ship-it", "combo-teacher", "combo-war-room"],
            icon: "square.stack.3d.up"
        ),
        SkillPack(
            id: "strategic-intel",
            name: "Strategic Intelligence",
            description: "Competitive intel, market analysis, product strategy, cost optimization",
            skillBaseIds: ["competitive-intel", "competitive-analysis", "product-strategy", "cost-optimization", "technical-dd"],
            icon: "binoculars"
        )
    ]
}

/// Loads skills from ~/.grump/skills/ and project .grump/skills/.
enum SkillsStorage {
    private static let skillFileName = "SKILL.md"

    static var globalSkillsDirectory: URL {
        URL(fileURLWithPath: NSHomeDirectory())
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
