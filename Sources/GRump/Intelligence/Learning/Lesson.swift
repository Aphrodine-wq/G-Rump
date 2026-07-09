import Foundation

// MARK: - Lesson

/// One distilled, durable lesson the agent applies to future runs.
/// Confidence is Laplace-smoothed from injection outcomes: (wins+1)/(hits+2).
struct Lesson: Codable, Identifiable, Equatable {
    enum Scope: String, Codable, CaseIterable {
        case global
        case project
    }

    enum Status: String, Codable {
        case active
        case pinned
        case retired
    }

    enum Category: String, Codable, CaseIterable {
        case toolUse = "tool_use"
        case codeStyle = "code_style"
        case projectFact = "project_fact"
        case process
        case userPreference = "user_preference"

        var label: String {
            switch self {
            case .toolUse: return "Tool Use"
            case .codeStyle: return "Code Style"
            case .projectFact: return "Project Fact"
            case .process: return "Process"
            case .userPreference: return "User Preference"
            }
        }
    }

    static let textLimit = 280

    let id: String
    var text: String
    var category: Category
    var triggerKeywords: [String]
    var scope: Scope
    var hitCount: Int
    var winCount: Int
    var lossCount: Int
    var status: Status
    /// Outcome ids (and "manual"/"tool" markers) this lesson was distilled from.
    var provenance: [String]
    var createdAt: Date
    var lastHitAt: Date?

    init(
        id: String = String(UUID().uuidString.prefix(8)).lowercased(),
        text: String,
        category: Category,
        triggerKeywords: [String] = [],
        scope: Scope,
        hitCount: Int = 0,
        winCount: Int = 0,
        lossCount: Int = 0,
        status: Status = .active,
        provenance: [String] = [],
        createdAt: Date = Date(),
        lastHitAt: Date? = nil
    ) {
        self.id = id
        self.text = String(text.prefix(Self.textLimit))
        self.category = category
        self.triggerKeywords = triggerKeywords.map { $0.lowercased() }
        self.scope = scope
        self.hitCount = hitCount
        self.winCount = winCount
        self.lossCount = lossCount
        self.status = status
        self.provenance = provenance
        self.createdAt = createdAt
        self.lastHitAt = lastHitAt
    }

    /// Raw Laplace confidence — never 0 or 1, single outcomes can't dominate.
    var confidence: Double {
        Double(winCount + 1) / Double(hitCount + 2)
    }

    /// Confidence after idle decay: untouched for 45 days → −0.05 per further week.
    func effectiveConfidence(now: Date = Date()) -> Double {
        let idleDays = now.timeIntervalSince(lastHitAt ?? createdAt) / 86_400
        guard idleDays > 45 else { return confidence }
        let idleWeeks = (idleDays - 45) / 7
        return max(0, confidence - 0.05 * idleWeeks)
    }

    /// Auto-retire threshold: proven-bad lessons stop being injected.
    func shouldAutoRetire(now: Date = Date()) -> Bool {
        status != .pinned && hitCount >= 5 && effectiveConfidence(now: now) < 0.3
    }

    /// Keyword relevance against a prompt: matched keywords / total keywords,
    /// with a small floor so keyword-less lessons can still surface on confidence.
    func relevance(to promptText: String) -> Double {
        guard !triggerKeywords.isEmpty else { return 0.3 }
        let lower = promptText.lowercased()
        let matched = triggerKeywords.filter { lower.contains($0) }.count
        guard matched > 0 else { return 0.1 }
        return Double(matched) / Double(triggerKeywords.count)
    }
}
