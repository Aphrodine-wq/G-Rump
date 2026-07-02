import XCTest
@testable import GRump

final class VaultBrainTests: XCTestCase {

    // MARK: - Frontmatter

    func testFrontmatterRoundTrip() {
        var fm = Frontmatter()
        fm.set("title", "Hello World")
        fm.set("type", "note")
        fm.set("tags", "[a, b, c]")
        let serialized = fm.serialized() + "\n\nBody text here."

        let (parsed, body) = Frontmatter.parse(serialized)
        XCTAssertEqual(parsed.value("title"), "Hello World")
        XCTAssertEqual(parsed.value("type"), "note")
        XCTAssertEqual(parsed.list("tags"), ["a", "b", "c"])
        XCTAssertEqual(body, "Body text here.")
    }

    func testFrontmatterNoFrontmatter() {
        let (fm, body) = Frontmatter.parse("Just a body, no frontmatter.")
        XCTAssertTrue(fm.fields.isEmpty)
        XCTAssertEqual(body, "Just a body, no frontmatter.")
    }

    // MARK: - VaultNote

    func testWikilinkExtraction() {
        let body = "This references [[Project Alpha]] and [[Decision X]] but not [single]."
        let links = VaultNote.extractWikilinks(from: body)
        XCTAssertEqual(links, ["Project Alpha", "Decision X"])
    }

    func testSlug() {
        XCTAssertEqual(VaultNote.slug("Use Postgres, not SQLite!"), "use-postgres-not-sqlite")
        XCTAssertEqual(VaultNote.slug("   "), "note")
    }

    func testNoteSerializeParse() {
        let note = VaultNote(title: "T", type: "decision", tags: ["x"], created: "2026-06-25", body: "Body with [[Link]].")
        let parsed = VaultNote.parse(note.serialized())
        XCTAssertEqual(parsed.title, "T")
        XCTAssertEqual(parsed.type, "decision")
        XCTAssertEqual(parsed.tags, ["x"])
        XCTAssertEqual(parsed.wikilinks(), ["Link"])
    }

    // MARK: - Decision detection

    func testDecisionDetection() {
        XCTAssertNotNil(VaultWriteBack.detectDecision(in: "Let's go with Postgres for the marketplace."))
        XCTAssertNotNil(VaultWriteBack.detectDecision(in: "We decided to use SQLite."))
        XCTAssertNil(VaultWriteBack.detectDecision(in: "What database should we use?"))
    }

    // MARK: - End-to-end write-back (isolated temp vault)

    func testWriteBackEndToEnd() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("grump-vault-test-\(UUID().uuidString)")
        // Pre-create the project vault so BrainPaths resolves to it (not the global home vault).
        let vaultDir = tmp.appendingPathComponent(".grump/vault")
        try FileManager.default.createDirectory(at: vaultDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        await VaultWriteBack.shared.record(
            userMessage: "Should we use Postgres or SQLite for FTW?",
            assistantContent: "Let's go with Postgres for the marketplace — better concurrency.",
            workingDirectory: tmp.path,
            graph: nil
        )

        let today = VaultNote.today()

        // Daily note written with the conversation line.
        let dailyURL = vaultDir.appendingPathComponent("DailyNotes/\(today).md")
        let daily = try String(contentsOf: dailyURL, encoding: .utf8)
        XCTAssertTrue(daily.contains("## Conversations"), "daily note should have Conversations section")
        XCTAssertTrue(daily.contains("Postgres"), "daily note should mention the answer")

        // Decision note written.
        let decisionsDir = vaultDir.appendingPathComponent("Decisions")
        let decisions = try FileManager.default.contentsOfDirectory(atPath: decisionsDir.path)
            .filter { $0.hasSuffix(".md") }
        XCTAssertEqual(decisions.count, 1, "exactly one decision note expected")

        // Backlink index rebuilds from disk and captures the decision -> daily-note link.
        await VaultWriteBack.shared.rebuildIndex(workingDirectory: tmp.path)
        let indexURL = vaultDir.appendingPathComponent(".index/backlinks.json")
        let indexData = try Data(contentsOf: indexURL)
        let backlinks = try JSONDecoder().decode([String: [String]].self, from: indexData)
        XCTAssertNotNil(backlinks[today], "decision links to today's daily note via [[\(today)]]")
    }
}
