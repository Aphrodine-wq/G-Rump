import Foundation
import os

// MARK: - ClawHub Service
//
// Shared skill registry between G-Rump and OpenClaw.
// Skills use the SKILL.md format and are stored in ~/.grump/skills/.
// Both systems can read skills from this directory.

@MainActor
final class ClawHubService: ObservableObject {
    static let shared = ClawHubService()

    @Published var installedSkills: [ClawHubSkill] = []
    @Published var isLoading = false

    private let logger = Logger(subsystem: "com.grump.clawhub", category: "SkillRegistry")

    private var skillsDirectory: String {
        (NSHomeDirectory() as NSString).appendingPathComponent(".grump/skills")
    }

    // MARK: - Load Skills

    func loadInstalledSkills() {
        let fm = FileManager.default
        let dir = skillsDirectory

        guard fm.fileExists(atPath: dir) else {
            installedSkills = []
            return
        }

        guard let files = try? fm.contentsOfDirectory(atPath: dir) else {
            installedSkills = []
            return
        }

        installedSkills = files
            .filter { $0.hasSuffix(".md") || $0.hasSuffix(".skill.md") }
            .compactMap { filename -> ClawHubSkill? in
                let path = (dir as NSString).appendingPathComponent(filename)
                guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
                return parseSkillFile(filename: filename, content: content, path: path)
            }
            .sorted { $0.name < $1.name }

        logger.info("Loaded \(self.installedSkills.count) skills from ClawHub")
    }

    // MARK: - Install Skill

    func installSkill(name: String, content: String) throws {
        let fm = FileManager.default
        try fm.createDirectory(atPath: skillsDirectory, withIntermediateDirectories: true)

        let filename = name.lowercased().replacingOccurrences(of: " ", with: "-") + ".skill.md"
        let path = (skillsDirectory as NSString).appendingPathComponent(filename)
        try content.write(toFile: path, atomically: true, encoding: .utf8)

        loadInstalledSkills()
        logger.info("Installed skill: \(name)")
    }

    // MARK: - Remove Skill

    func removeSkill(_ skill: ClawHubSkill) throws {
        try FileManager.default.removeItem(atPath: skill.path)
        loadInstalledSkills()
        logger.info("Removed skill: \(skill.name)")
    }

    // MARK: - Parsing

    private func parseSkillFile(filename: String, content: String, path: String) -> ClawHubSkill? {
        let lines = content.components(separatedBy: .newlines)

        var name = filename.replacingOccurrences(of: ".skill.md", with: "").replacingOccurrences(of: ".md", with: "")
        var description = ""
        var keywords: [String] = []
        var author = ""
        var version = ""

        // Parse YAML-style frontmatter if present
        if lines.first == "---" {
            var inFrontmatter = true
            for line in lines.dropFirst() {
                if line == "---" { inFrontmatter = false; continue }
                if !inFrontmatter { break }

                let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                guard parts.count == 2 else { continue }

                switch parts[0].lowercased() {
                case "name": name = parts[1]
                case "description": description = parts[1]
                case "keywords": keywords = parts[1].components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                case "author": author = parts[1]
                case "version": version = parts[1]
                default: break
                }
            }
        }

        // If no frontmatter, try to extract name from first heading
        if description.isEmpty {
            for line in lines {
                if line.hasPrefix("# ") {
                    name = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                } else if !line.isEmpty && !line.hasPrefix("#") && !line.hasPrefix("---") {
                    description = line
                    break
                }
            }
        }

        return ClawHubSkill(
            name: name,
            description: description,
            keywords: keywords,
            author: author,
            version: version,
            path: path,
            content: content
        )
    }

    // MARK: - Featured Skill Packs

    static let featuredPacks: [ClawHubSkillPack] = [
        ClawHubSkillPack(
            name: "iOS Development",
            description: "Complete iOS development workflow",
            skillNames: ["swift-ios", "swiftui-patterns", "app-store-prep", "xcode-testing", "accessibility-ios"]
        ),
        ClawHubSkillPack(
            name: "Full Stack Web",
            description: "Modern web application development",
            skillNames: ["react-next", "typescript-patterns", "api-design", "database-ops", "deployment"]
        ),
        ClawHubSkillPack(
            name: "DevOps",
            description: "Infrastructure and deployment automation",
            skillNames: ["docker-compose", "ci-cd", "terraform-iac", "monitoring", "security-scanning"]
        ),
        ClawHubSkillPack(
            name: "Code Quality",
            description: "Testing, refactoring, and review",
            skillNames: ["unit-testing", "code-review", "refactoring", "documentation", "performance-profiling"]
        )
    ]
}

// MARK: - Types

struct ClawHubSkill: Identifiable, Equatable {
    let name: String
    let description: String
    let keywords: [String]
    let author: String
    let version: String
    let path: String
    let content: String

    var id: String { path }

    /// Calculate relevance score for a given context (file types, keywords).
    func relevanceScore(for query: String, fileExtensions: Set<String> = []) -> Double {
        let lower = query.lowercased()
        var score = 0.0

        // Keyword matches
        for keyword in keywords {
            if lower.contains(keyword.lowercased()) { score += 0.3 }
        }

        // Name match
        if lower.contains(name.lowercased()) { score += 0.5 }

        // Description match
        let descWords = description.lowercased().components(separatedBy: .whitespaces)
        let queryWords = lower.components(separatedBy: .whitespaces)
        let overlap = Set(descWords).intersection(Set(queryWords)).count
        score += Double(overlap) * 0.1

        return min(1.0, score)
    }
}

struct ClawHubSkillPack: Identifiable {
    let name: String
    let description: String
    let skillNames: [String]

    var id: String { name }
}
