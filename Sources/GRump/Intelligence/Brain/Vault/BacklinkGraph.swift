import Foundation

/// Maintains the vault's `[[wikilink]]` backlink index (`<vault>/.index/backlinks.json`),
/// mapping each link target → the note titles that reference it. Fully rebuildable from
/// the notes on disk, so it is a derived cache, never a source of truth.
actor BacklinkGraph {
    private let indexURL: URL
    private var backlinks: [String: [String]] = [:]
    private var loaded = false

    init(workingDirectory: String = "") {
        self.indexURL = BrainPaths.backlinkIndex(workingDirectory: workingDirectory)
    }

    /// Record that `sourceTitle` links to `targets`, persisting the updated index.
    func record(sourceTitle: String, targets: [String]) {
        loadIfNeeded()
        for target in targets where !target.isEmpty {
            var sources = backlinks[target] ?? []
            if !sources.contains(sourceTitle) {
                sources.append(sourceTitle)
                backlinks[target] = sources
            }
        }
        save()
    }

    /// Notes that link to `target`.
    func sources(for target: String) -> [String] {
        loadIfNeeded()
        return backlinks[target] ?? []
    }

    /// Rebuild the entire index by scanning every note in the vault.
    func rebuildIndex(using store: VaultStore) async {
        var fresh: [String: [String]] = [:]
        for url in await store.allNotePaths() {
            guard let content = await store.readContent(at: url) else { continue }
            let note = VaultNote.parse(content)
            for target in note.wikilinks() where !target.isEmpty {
                var sources = fresh[target] ?? []
                if !sources.contains(note.title) { sources.append(note.title) }
                fresh[target] = sources
            }
        }
        backlinks = fresh
        loaded = true
        save()
    }

    // MARK: - Persistence

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) else {
            backlinks = [:]
            return
        }
        backlinks = decoded
    }

    private func save() {
        let dir = indexURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(backlinks)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            GRumpLogger.brain.error("Backlink index save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
