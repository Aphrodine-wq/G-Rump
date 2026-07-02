import Foundation

/// Actor-isolated CRUD over the markdown vault. All writes are atomic. The vault is a
/// human-readable durability + write-back layer; `AdvancedMemoryStore`/`MemoryGraph`
/// remain the source of truth for ranked recall.
actor VaultStore {
    private let root: URL
    private let fm = FileManager.default

    init(workingDirectory: String = "") {
        self.root = BrainPaths.vaultRoot(workingDirectory: workingDirectory)
    }

    private func ensureDir(_ url: URL) {
        if !fm.fileExists(atPath: url.path) {
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    private func folderURL(_ folder: BrainPaths.VaultFolder) -> URL {
        let url = root.appendingPathComponent(folder.rawValue)
        ensureDir(url)
        return url
    }

    // MARK: - Daily Notes

    /// Append a bullet line under `## section` in today's daily note, creating the file
    /// (with frontmatter) and the section heading as needed. Returns the note path.
    @discardableResult
    func appendDailyNote(section: String, line: String) -> URL {
        let day = VaultNote.today()
        let url = folderURL(.dailyNotes).appendingPathComponent("\(day).md")

        var content: String
        if let existing = try? String(contentsOf: url, encoding: .utf8) {
            content = existing
        } else {
            let note = VaultNote(title: day, type: "daily-note", tags: ["daily"], created: day, body: "")
            content = note.serialized()
        }

        let heading = "## \(section)"
        let bullet = "- \(line)"
        if content.contains(heading) {
            // Insert the bullet right after the heading line.
            var lines = content.components(separatedBy: "\n")
            if let idx = lines.firstIndex(of: heading) {
                lines.insert(bullet, at: idx + 1)
            } else {
                lines.append(contentsOf: ["", heading, bullet])
            }
            content = lines.joined(separator: "\n")
        } else {
            if !content.hasSuffix("\n") { content += "\n" }
            content += "\n\(heading)\n\(bullet)\n"
        }

        write(content, to: url)
        return url
    }

    // MARK: - Decisions

    /// Write a decision note (`Decisions/yyyy-MM-dd-slug.md`). Returns its path.
    @discardableResult
    func writeDecision(title: String, body: String, tags: [String] = ["decision"]) -> URL {
        let day = VaultNote.today()
        let filename = "\(day)-\(VaultNote.slug(title)).md"
        let url = folderURL(.decisions).appendingPathComponent(filename)
        let note = VaultNote(title: title, type: "decision", tags: tags, created: day, body: body)
        write(note.serialized(), to: url)
        return url
    }

    // MARK: - Generic upsert

    @discardableResult
    func upsertNote(folder: BrainPaths.VaultFolder, filename: String, note: VaultNote) -> URL {
        let url = folderURL(folder).appendingPathComponent(filename)
        write(note.serialized(), to: url)
        return url
    }

    // MARK: - Reads

    /// All markdown note paths in the vault (excludes the `.index` dir).
    func allNotePaths() -> [URL] {
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
        var out: [URL] = []
        for case let url as URL in enumerator {
            if url.pathExtension == "md" && !url.path.contains("/.index/") {
                out.append(url)
            }
        }
        return out
    }

    func readContent(at url: URL) -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }

    var vaultRoot: URL { root }

    // MARK: - Private

    private func write(_ content: String, to url: URL) {
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            GRumpLogger.brain.error("Vault write failed (\(url.lastPathComponent, privacy: .public)): \(error.localizedDescription, privacy: .public)")
        }
    }
}
