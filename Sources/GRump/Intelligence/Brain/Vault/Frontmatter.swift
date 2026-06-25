import Foundation

/// Minimal YAML-frontmatter parser/serializer shared by the vault (and reusable by
/// SOUL.md / MIND.md). Supports scalar `key: value` and simple `key: [a, b]` lists —
/// deliberately small, not a full YAML engine.
struct Frontmatter: Equatable {
    /// Order-preserving fields.
    private(set) var fields: [(key: String, value: String)]

    init(_ fields: [(key: String, value: String)] = []) {
        self.fields = fields
    }

    static func == (lhs: Frontmatter, rhs: Frontmatter) -> Bool {
        lhs.fields.map { "\($0.key)=\($0.value)" } == rhs.fields.map { "\($0.key)=\($0.value)" }
    }

    func value(_ key: String) -> String? {
        fields.first { $0.key == key }?.value
    }

    /// List value (`tags: [a, b]`) parsed into elements.
    func list(_ key: String) -> [String] {
        guard let raw = value(key) else { return [] }
        let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
        guard !trimmed.isEmpty else { return [] }
        return trimmed.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    mutating func set(_ key: String, _ value: String) {
        if let idx = fields.firstIndex(where: { $0.key == key }) {
            fields[idx].value = value
        } else {
            fields.append((key, value))
        }
    }

    /// Render as a `---` fenced block (no trailing newline beyond the closing fence).
    func serialized() -> String {
        guard !fields.isEmpty else { return "" }
        var lines = ["---"]
        for field in fields {
            lines.append("\(field.key): \(field.value)")
        }
        lines.append("---")
        return lines.joined(separator: "\n")
    }

    /// Split markdown content into (frontmatter, body). Mirrors the SOUL.md parser.
    static func parse(_ content: String) -> (frontmatter: Frontmatter, body: String) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("---") else {
            return (Frontmatter(), trimmed)
        }
        let parts = trimmed.components(separatedBy: "\n---\n")
        guard parts.count >= 2 else {
            return (Frontmatter(), trimmed)
        }
        let header = parts[0].replacingOccurrences(of: "---", with: "")
        let body = parts.dropFirst().joined(separator: "\n---\n").trimmingCharacters(in: .whitespacesAndNewlines)

        var fm = Frontmatter()
        for line in header.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard let colon = t.firstIndex(of: ":") else { continue }
            let key = String(t[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(t[t.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            fm.set(key, value)
        }
        return (fm, body)
    }
}
