import Foundation

/// Generates human-readable vault notes from conversation turns: a one-line daily-note
/// entry per turn, plus a decision note when a turn reads like a decision. Also bridges
/// any `[[wikilinks]]` into the backlink index and the `MemoryGraph` knowledge graph.
///
/// Singleton actor; caches a `VaultStore` + `BacklinkGraph` per working directory.
actor VaultWriteBack {
    static let shared = VaultWriteBack()

    private var cachedDir: String = "\u{0}"   // sentinel so first real dir always rebuilds
    private var store: VaultStore?
    private var backlinks: BacklinkGraph?

    /// Phrases that mark a conversation turn as a decision.
    private static let decisionTriggers = [
        "we're going with", "we are going with", "let's go with", "lets go with",
        "decided to", "decision:", "we'll use", "we will use", "let's use", "we should go with"
    ]

    private func ensure(_ workingDirectory: String) -> (VaultStore, BacklinkGraph) {
        if workingDirectory != cachedDir || store == nil || backlinks == nil {
            cachedDir = workingDirectory
            store = VaultStore(workingDirectory: workingDirectory)
            backlinks = BacklinkGraph(workingDirectory: workingDirectory)
        }
        return (store!, backlinks!)
    }

    /// Record a completed turn into the vault. `graph` (optional) receives `links_to`
    /// edges for any wikilinks so vault notes join the knowledge graph.
    func record(
        userMessage: String,
        assistantContent: String,
        workingDirectory: String,
        graph: MemoryGraph? = nil
    ) async {
        let (store, backlinks) = ensure(workingDirectory)

        // 1. Daily-note line for this turn.
        let day = VaultNote.today()
        let stamp = Self.timeStamp()
        let gist = Self.oneLine(userMessage, max: 100)
        let answer = Self.oneLine(assistantContent, max: 120)
        let line = "[\(stamp)] \(gist) \u{2192} \(answer)"
        await store.appendDailyNote(section: "Conversations", line: line)

        // 2. Decision detection.
        let combined = "\(userMessage)\n\(assistantContent)"
        if let decision = Self.detectDecision(in: combined) {
            // Link the decision back to today's daily note for traceability.
            let body = "\(decision)\n\nContext: \(Self.oneLine(userMessage, max: 300))\n\nSee [[\(day)]].\n"
            let url = await store.writeDecision(title: decision, body: body)
            let note = VaultNote.parse((await store.readContent(at: url)) ?? "")
            let targets = note.wikilinks()
            await backlinks.record(sourceTitle: note.title, targets: targets)
            if let graph {
                for target in targets {
                    await graph.addEdge(from: note.title, to: target, relationship: "links_to")
                }
            }
        }
    }

    /// Rebuild the backlink index from notes on disk.
    func rebuildIndex(workingDirectory: String) async {
        let (store, backlinks) = ensure(workingDirectory)
        await backlinks.rebuildIndex(using: store)
    }

    // MARK: - Helpers

    static func detectDecision(in text: String) -> String? {
        let lower = text.lowercased()
        guard let trigger = decisionTriggers.first(where: { lower.contains($0) }) else { return nil }
        // Pull the sentence/line containing the trigger as the decision title.
        let segments = text.components(separatedBy: CharacterSet(charactersIn: ".\n!?"))
        let match = segments.first { $0.lowercased().contains(trigger) } ?? text
        return oneLine(match, max: 90)
    }

    private static func oneLine(_ text: String, max: Int) -> String {
        let collapsed = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return collapsed.count > max ? String(collapsed.prefix(max)) + "\u{2026}" : collapsed
    }

    private static func timeStamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f.string(from: Date())
    }
}
