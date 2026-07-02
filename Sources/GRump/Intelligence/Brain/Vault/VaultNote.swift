import Foundation

/// A single markdown vault note: YAML frontmatter + body, with `[[wikilink]]` support.
struct VaultNote: Equatable {
    var title: String
    var type: String
    var tags: [String]
    var created: String          // ISO-8601 date (yyyy-MM-dd)
    var body: String

    init(title: String, type: String, tags: [String] = [], created: String = VaultNote.today(), body: String = "") {
        self.title = title
        self.type = type
        self.tags = tags
        self.created = created
        self.body = body
    }

    /// Render to markdown (frontmatter + body).
    func serialized() -> String {
        var fm = Frontmatter()
        fm.set("title", title)
        fm.set("type", type)
        fm.set("created", created)
        fm.set("tags", "[\(tags.joined(separator: ", "))]")
        return fm.serialized() + "\n\n" + body + "\n"
    }

    /// Parse a note from markdown content.
    static func parse(_ content: String) -> VaultNote {
        let (fm, body) = Frontmatter.parse(content)
        return VaultNote(
            title: fm.value("title") ?? "Untitled",
            type: fm.value("type") ?? "note",
            tags: fm.list("tags"),
            created: fm.value("created") ?? today(),
            body: body
        )
    }

    /// All `[[wikilink]]` targets referenced in the body.
    func wikilinks() -> [String] {
        VaultNote.extractWikilinks(from: body)
    }

    static func extractWikilinks(from text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "\\[\\[([^\\]]+)\\]\\]") else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var out: [String] = []
        for match in regex.matches(in: text, range: range) {
            if let r = Range(match.range(at: 1), in: text) {
                let target = String(text[r]).trimmingCharacters(in: .whitespaces)
                if !target.isEmpty { out.append(target) }
            }
        }
        return out
    }

    // MARK: - Date helpers (in-app Date is allowed; vault runs in the running app)

    static func today() -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    /// Filesystem-safe slug from a title.
    static func slug(_ title: String) -> String {
        let lowered = title.lowercased()
        let allowed = lowered.map { ch -> Character in
            (ch.isLetter || ch.isNumber) ? ch : "-"
        }
        let collapsed = String(allowed)
            .replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return collapsed.isEmpty ? "note" : String(collapsed.prefix(60))
    }
}
