import Foundation

/// Lightweight, on-device classifier mapping (app, OCR text) → a coarse activity, an
/// optional project hint, and extracted entities. Rules-based; no model download.
struct ActivityClassifier {

    struct Result: Sendable {
        let project: String
        let activity: String
        let entities: [String]
    }

    private static let activityByAppFragment: [(fragments: [String], activity: String)] = [
        (["code", "xcode", "iterm", "terminal", "vim", "emacs", "cursor", "sublime", "intellij", "pycharm", "studio", "nova", "zed"], "coding"),
        (["safari", "chrome", "firefox", "arc", "brave", "edge", "opera"], "browsing"),
        (["obsidian", "notes", "notion", "bear", "ulysses", "word", "pages", "typora", "craft"], "writing"),
        (["mail", "slack", "zoom", "teams", "discord", "messages", "telegram", "outlook", "spark"], "comms"),
        (["figma", "sketch", "photoshop", "illustrator", "affinity", "pixelmator"], "design")
    ]

    func classify(appName: String, bundleId: String, text: String) -> Result {
        let haystack = (appName + " " + bundleId).lowercased()
        var activity = "other"
        for rule in Self.activityByAppFragment where rule.fragments.contains(where: { haystack.contains($0) }) {
            activity = rule.activity
            break
        }

        let entities = Self.extractEntities(from: text)
        let project = Self.inferProject(from: entities)
        return Result(project: project, activity: activity, entities: entities)
    }

    // MARK: - Entities

    static func extractEntities(from text: String) -> [String] {
        var out: [String] = []
        for (pattern, cap) in entityPatterns {
            out.append(contentsOf: matches(of: pattern, in: text, limit: cap))
        }
        // De-dup, preserve order, cap total.
        var seen = Set<String>()
        return out.filter { seen.insert($0).inserted }.prefix(20).map { $0 }
    }

    /// Best-effort project hint: the parent directory of the first file path seen.
    static func inferProject(from entities: [String]) -> String {
        for e in entities where e.contains("/") && e.contains(".") {
            let comps = e.split(separator: "/")
            if comps.count >= 2 {
                return String(comps[comps.count - 2])
            }
        }
        return ""
    }

    private static let entityPatterns: [(String, Int)] = [
        ("https?://[^\\s)>\\]\"']+", 5),
        ("\\b[\\w./~-]+\\.(swift|ts|tsx|js|jsx|py|go|rs|java|rb|md|json|yml|yaml|sql)\\b", 8),
        ("\\b(?:Error|Exception|Traceback|FATAL|panic|fatal error)\\b", 3),
        ("\\$\\s?\\d[\\d,]*(?:\\.\\d{2})?", 3)
    ]

    private static func matches(of pattern: String, in text: String, limit: Int) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var out: [String] = []
        for m in regex.matches(in: text, range: range).prefix(limit) {
            if let r = Range(m.range, in: text) {
                out.append(String(text[r]))
            }
        }
        return out
    }
}
