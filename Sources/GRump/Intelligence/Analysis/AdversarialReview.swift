import Foundation
import OSLog

// MARK: - Adversarial Self-Review Engine
//
// After the agent generates code in Build mode, automatically spawns a
// "red team" critic agent (using a different model via ModelRouter) that:
//   1. Tries to find bugs, edge cases, security holes, performance issues
//   2. Rates severity of each finding
//   3. The original agent then addresses the critical findings
//
// No AI tool auto-adversarially reviews its own output. Cursor, Copilot,
// Windsurf — they all generate and hope. This builds in a second-opinion loop.

// MARK: - Finding Severity

enum FindingSeverity: String, Codable, CaseIterable, Comparable {
    case info = "info"
    case warning = "warning"
    case critical = "critical"
    case blocker = "blocker"

    var icon: String {
        switch self {
        case .info:     return "info.circle"
        case .warning:  return "exclamationmark.triangle"
        case .critical: return "xmark.octagon"
        case .blocker:  return "xmark.octagon.fill"
        }
    }

    var colorName: String {
        switch self {
        case .info:     return "blue"
        case .warning:  return "orange"
        case .critical: return "red"
        case .blocker:  return "red"
        }
    }

    private var sortOrder: Int {
        switch self {
        case .info: return 0
        case .warning: return 1
        case .critical: return 2
        case .blocker: return 3
        }
    }

    static func < (lhs: FindingSeverity, rhs: FindingSeverity) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

// MARK: - Finding Category

enum FindingCategory: String, Codable, CaseIterable {
    case bug = "Bug"
    case security = "Security"
    case performance = "Performance"
    case edgeCase = "Edge Case"
    case errorHandling = "Error Handling"
    case concurrency = "Concurrency"
    case memoryLeak = "Memory Leak"
    case apiMisuse = "API Misuse"
    case codeSmell = "Code Smell"

    var icon: String {
        switch self {
        case .bug:           return "ladybug"
        case .security:      return "lock.trianglebadge.exclamationmark"
        case .performance:   return "gauge.with.dots.needle.33percent"
        case .edgeCase:      return "arrow.triangle.branch"
        case .errorHandling: return "exclamationmark.bubble"
        case .concurrency:   return "arrow.triangle.2.circlepath"
        case .memoryLeak:    return "memorychip"
        case .apiMisuse:     return "xmark.app"
        case .codeSmell:     return "nose"
        }
    }
}

// MARK: - Review Finding

struct ReviewFinding: Identifiable, Codable {
    let id: UUID
    let severity: FindingSeverity
    let category: FindingCategory
    let title: String
    let description: String
    let filePath: String?
    let lineRange: String?
    let suggestedFix: String?

    init(
        id: UUID = UUID(),
        severity: FindingSeverity,
        category: FindingCategory,
        title: String,
        description: String,
        filePath: String? = nil,
        lineRange: String? = nil,
        suggestedFix: String? = nil
    ) {
        self.id = id
        self.severity = severity
        self.category = category
        self.title = title
        self.description = description
        self.filePath = filePath
        self.lineRange = lineRange
        self.suggestedFix = suggestedFix
    }
}

// MARK: - Review Report

struct AdversarialReviewReport: Identifiable {
    let id = UUID()
    let findings: [ReviewFinding]
    let reviewModel: String
    let durationSeconds: Double
    let timestamp: Date

    var criticalCount: Int { findings.filter { $0.severity >= .critical }.count }
    var warningCount: Int { findings.filter { $0.severity == .warning }.count }
    var infoCount: Int { findings.filter { $0.severity == .info }.count }
    var hasBlockers: Bool { findings.contains { $0.severity == .blocker } }

    /// Formatted markdown summary for injection into the conversation.
    var markdownSummary: String {
        if findings.isEmpty {
            return "**Adversarial Review** — No issues found. Code looks solid."
        }

        var lines: [String] = []
        lines.append("**Adversarial Review** — \(findings.count) finding(s):")
        lines.append("")

        let sorted = findings.sorted { $0.severity > $1.severity }
        for finding in sorted {
            let severity = finding.severity.rawValue.uppercased()
            let location = [finding.filePath, finding.lineRange].compactMap { $0 }.joined(separator: ":")
            let locationStr = location.isEmpty ? "" : " (`\(location)`)"
            lines.append("- **[\(severity)] \(finding.category.rawValue)**: \(finding.title)\(locationStr)")
            lines.append("  \(finding.description)")
            if let fix = finding.suggestedFix {
                lines.append("  → *Fix*: \(fix)")
            }
        }

        if hasBlockers {
            lines.append("")
            lines.append("⚠️ **Blockers found.** Address critical issues before proceeding.")
        }

        return lines.joined(separator: "\n")
    }
}

// MARK: - Adversarial Review Engine

@MainActor
final class AdversarialReviewEngine: ObservableObject {

    @Published private(set) var isReviewing = false
    @Published private(set) var lastReport: AdversarialReviewReport?

    private let logger = GRumpLogger.general

    /// Whether adversarial review is enabled (user toggle).
    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "AdversarialReviewEnabled") as? Bool ?? true
    }

    // MARK: - Review

    /// Run adversarial review on code changes from the current agent run.
    /// Returns a report with findings, or nil if no issues.
    func review(
        codeChanges: [CodeChange],
        conversationContext: String,
        primaryModel: AIModel
    ) async -> AdversarialReviewReport? {
        guard isEnabled, !codeChanges.isEmpty else { return nil }

        isReviewing = true
        let startTime = Date()

        defer { isReviewing = false }

        // Use a different model than the primary for genuine adversarial perspective
        let reviewModel = ModelRouter.route(taskType: .debugging, fallback: primaryModel)
        let reviewModelId = reviewModel.rawValue

        let changeSummary = codeChanges.map { change in
            var block = "**\(change.operation.rawValue)** `\(change.filePath)`"
            if let content = change.content {
                block += "\n```\n\(String(content.prefix(2000)))\n```"
            }
            return block
        }.joined(separator: "\n\n")

        let systemPrompt = """
        You are a ruthless code reviewer — a "red team" critic. Your ONLY job is to find \
        problems in the code changes below. You are adversarial: assume the code has bugs \
        until proven otherwise.

        Look for:
        1. **Bugs**: Logic errors, off-by-one, nil/null issues, type mismatches
        2. **Security**: Injection, hardcoded secrets, insecure defaults, missing auth checks
        3. **Edge cases**: Empty inputs, large inputs, concurrent access, race conditions
        4. **Error handling**: Missing catches, swallowed errors, incorrect error types
        5. **Performance**: O(n²) where O(n) is possible, unnecessary allocations, retain cycles
        6. **API misuse**: Deprecated APIs, incorrect framework usage, platform gotchas
        7. **Concurrency**: Data races, deadlocks, missing @MainActor, Sendable violations

        Respond with ONLY valid JSON — an array of findings:
        [
          {
            "severity": "critical",
            "category": "Bug",
            "title": "Short title",
            "description": "What's wrong and why it matters",
            "filePath": "path/to/file.swift",
            "lineRange": "42-45",
            "suggestedFix": "How to fix it"
          }
        ]

        If the code looks correct, return an empty array: []
        Severity levels: info, warning, critical, blocker
        Categories: Bug, Security, Performance, Edge Case, Error Handling, Concurrency, Memory Leak, API Misuse, Code Smell

        Be specific. No vague findings. Every finding must point to a concrete problem.
        """

        let messages: [Message] = [
            Message(role: .system, content: systemPrompt),
            Message(role: .user, content: "Review these code changes:\n\n\(changeSummary)\n\nContext: \(String(conversationContext.prefix(1000)))")
        ]

        var fullResponse = ""

        do {
            // Routes through the multi-provider dispatcher; unknown review
            // model ids fall back to the app default model.
            let stream = MultiProviderAIService.stream(messages: messages, modelID: reviewModelId)
            for try await event in stream {
                if case .text(let chunk) = event { fullResponse += chunk }
            }
        } catch {
            logger.error("AdversarialReview failed: \(error.localizedDescription)")
            return nil
        }

        let findings = parseFindings(from: fullResponse)
        let duration = Date().timeIntervalSince(startTime)

        let report = AdversarialReviewReport(
            findings: findings,
            reviewModel: reviewModel.displayName,
            durationSeconds: duration,
            timestamp: Date()
        )

        lastReport = report
        logger.info("AdversarialReview completed: \(findings.count) findings in \(String(format: "%.1f", duration))s")
        return report
    }

    // MARK: - Parsing

    private func parseFindings(from json: String) -> [ReviewFinding] {
        var cleaned = json.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip markdown code fences if present
        if cleaned.hasPrefix("```") {
            let lines = cleaned.components(separatedBy: "\n")
            cleaned = lines.dropFirst().dropLast().joined(separator: "\n")
        }

        guard let data = cleaned.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            // Try to find JSON array within the response
            if let start = cleaned.firstIndex(of: "["),
               let end = cleaned.lastIndex(of: "]") {
                let substring = String(cleaned[start...end])
                if let data = substring.data(using: .utf8),
                   let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                    return arr.compactMap(parseSingleFinding)
                }
            }
            return []
        }

        return arr.compactMap(parseSingleFinding)
    }

    private func parseSingleFinding(_ dict: [String: Any]) -> ReviewFinding? {
        guard let title = dict["title"] as? String,
              let description = dict["description"] as? String else { return nil }

        let severityStr = (dict["severity"] as? String)?.lowercased() ?? "warning"
        let categoryStr = dict["category"] as? String ?? "Bug"

        let severity = FindingSeverity(rawValue: severityStr) ?? .warning
        let category = FindingCategory(rawValue: categoryStr) ?? .bug

        return ReviewFinding(
            severity: severity,
            category: category,
            title: title,
            description: description,
            filePath: dict["filePath"] as? String,
            lineRange: dict["lineRange"] as? String,
            suggestedFix: dict["suggestedFix"] as? String
        )
    }
}

// MARK: - Code Change (for tracking what the agent modified)

struct CodeChange: Identifiable {
    let id = UUID()
    let filePath: String
    let operation: Operation
    let content: String?

    enum Operation: String {
        case created = "Created"
        case edited = "Edited"
        case deleted = "Deleted"
    }
}
