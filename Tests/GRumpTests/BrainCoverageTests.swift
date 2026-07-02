import XCTest
@testable import GRump

/// Additional coverage for the WALT-brain subsystems and the CI headless guard.
final class BrainCoverageTests: XCTestCase {

    // MARK: - GRumpRuntime (locks in the CI segfault fix)

    func testRuntimeIsHeadlessUnderTest() {
        XCTAssertTrue(GRumpRuntime.isHeadless, "the XCTest runner must be detected as headless")
        XCTAssertFalse(GRumpRuntime.notificationsAvailable, "notifications must be disabled headless")
    }

    // MARK: - BrainConfig

    func testBrainConfigDefaults() {
        let c = BrainConfig.default
        XCTAssertTrue(c.vaultEnabled)
        XCTAssertFalse(c.eyesEnabled)
        XCTAssertTrue(c.conscienceEnabled)
        XCTAssertFalse(c.daemonEnabled)
        XCTAssertFalse(c.ttsEnabled)
    }

    func testBrainConfigCodableRoundTrip() throws {
        var c = BrainConfig.default
        c.eyesEnabled = true
        c.daemonEnabled = true
        c.displayName = "Tester"
        c.eyesCaptureIntervalSeconds = 7
        c.eyesIgnoredBundleIDs = ["com.x.y"]
        let data = try JSONEncoder().encode(c)
        let decoded = try JSONDecoder().decode(BrainConfig.self, from: data)
        XCTAssertEqual(decoded, c)
    }

    // MARK: - Speech sanitize (Phase 1)

    @MainActor
    func testSpeechSanitizeStripsMarkdownAndCode() {
        let out = SpeechOutputService.sanitize("# Title\n```\nlet x = 1\n```\nsome *bold* and `code` text")
        XCTAssertTrue(out.contains("code block"))
        XCTAssertFalse(out.contains("```"))
        XCTAssertFalse(out.contains("#"))
        XCTAssertFalse(out.contains("*"))
    }

    // MARK: - ObservationStore (Phase 3, temp DB)

    func testObservationStoreInsertAndRecent() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("grump-obs-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store = ObservationStore(path: tmp.path)
        await store.open()
        await store.insert(Observation(app: "Code", windowTitle: "main.swift", phash: 999, redactedText: "hello", project: "P", activity: "coding", entities: ["a.swift"]))
        await store.insert(Observation(app: "Safari", windowTitle: "docs", phash: 111, redactedText: "browsing", project: "", activity: "browsing", entities: []))

        let count = await store.count()
        XCTAssertEqual(count, 2)
        let recent = await store.recent(limit: 5)
        XCTAssertEqual(recent.count, 2)
        let latest = await store.latest()
        XCTAssertNotNil(latest)
        XCTAssertEqual(latest?.phash, recent.first?.phash)
    }

    // MARK: - VaultStore generic upsert (Phase 2, temp vault)

    func testVaultStoreUpsertAndRead() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("grump-vstore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp.appendingPathComponent(".grump/vault"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store = VaultStore(workingDirectory: tmp.path)
        let note = VaultNote(title: "Idea", type: "zettel", tags: ["t"], body: "Body with [[Link]].")
        let url = await store.upsertNote(folder: .zettelkasten, filename: "idea.md", note: note)
        let content = await store.readContent(at: url)
        XCTAssertNotNil(content)
        let parsed = VaultNote.parse(content ?? "")
        XCTAssertEqual(parsed.title, "Idea")
        XCTAssertEqual(parsed.wikilinks(), ["Link"])
    }

    // MARK: - Surface classifier edge cases (Phase 4)

    func testSurfaceClassifierPriority() {
        let c = SurfaceClassifier()
        // Secrets outranks payment when both present.
        XCTAssertEqual(c.classify("your api key and card number"), .secrets)
        // Single ambiguous word does not trip (high-precision multi-word tells).
        XCTAssertEqual(c.classify("checkout the new token feature"), .neutral)
    }

    // MARK: - Awareness focus drift (Phase 4)

    @MainActor
    func testAwarenessFocusDrift() {
        let a = AwarenessMonitor.shared
        // Fill the entire window with one tool → low drift (robust to shared state).
        for _ in 0..<12 { a.record(tool: "read_file") }
        XCTAssertLessThan(a.focusDrift, 0.4)
    }
}
