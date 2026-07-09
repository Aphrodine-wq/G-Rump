import XCTest
@testable import GRump

final class LessonTests: XCTestCase {

    func testLaplaceConfidence() {
        var lesson = Lesson(text: "Test", category: .process, scope: .global)
        XCTAssertEqual(lesson.confidence, 0.5, accuracy: 0.001, "no history → prior 1/2")
        lesson.hitCount = 4
        lesson.winCount = 4
        XCTAssertEqual(lesson.confidence, 5.0 / 6.0, accuracy: 0.001)
    }

    func testTextClampedTo280() {
        let lesson = Lesson(text: String(repeating: "x", count: 500), category: .process, scope: .global)
        XCTAssertEqual(lesson.text.count, Lesson.textLimit)
    }

    func testEffectiveConfidenceDecaysAfterIdle() {
        let created = Date(timeIntervalSinceNow: -100 * 86_400)   // 100 days idle
        var lesson = Lesson(text: "Old", category: .process, scope: .global, createdAt: created)
        lesson.hitCount = 8
        lesson.winCount = 8
        let fresh = lesson.confidence
        let decayed = lesson.effectiveConfidence()
        // (100 − 45) / 7 weeks × 0.05 ≈ 0.39 penalty
        XCTAssertLessThan(decayed, fresh - 0.3)
        XCTAssertGreaterThanOrEqual(decayed, 0)
    }

    func testNoDecayWithinWindow() {
        let lesson = Lesson(text: "Fresh", category: .process, scope: .global)
        XCTAssertEqual(lesson.effectiveConfidence(), lesson.confidence, accuracy: 0.0001)
    }

    func testAutoRetireRules() {
        var bad = Lesson(text: "Bad", category: .process, scope: .global)
        bad.hitCount = 6
        bad.winCount = 0   // conf = 1/8 = 0.125
        XCTAssertTrue(bad.shouldAutoRetire())
        bad.status = .pinned
        XCTAssertFalse(bad.shouldAutoRetire(), "pinned lessons never auto-retire")
        var young = Lesson(text: "Young", category: .process, scope: .global)
        young.hitCount = 2
        XCTAssertFalse(young.shouldAutoRetire(), "needs ≥5 hits before retiring")
    }

    func testRelevanceScoring() {
        let lesson = Lesson(
            text: "Run xcodegen after editing project.yml",
            category: .toolUse,
            triggerKeywords: ["xcodegen", "project.yml"],
            scope: .project
        )
        XCTAssertEqual(lesson.relevance(to: "edit the project.yml and rebuild"), 0.5, accuracy: 0.001)
        XCTAssertEqual(lesson.relevance(to: "xcodegen broke on project.yml"), 1.0, accuracy: 0.001)
        XCTAssertEqual(lesson.relevance(to: "unrelated question"), 0.1, accuracy: 0.001)
        let keywordless = Lesson(text: "Always run tests", category: .process, scope: .global)
        XCTAssertEqual(keywordless.relevance(to: "anything"), 0.3, accuracy: 0.001)
    }
}

@MainActor
final class LessonStoreTests: XCTestCase {

    private var tempDir: URL!
    private var store: LessonStore!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LessonStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = LessonStore(globalFileURL: tempDir.appendingPathComponent("global-lessons.json"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testAddPersistsAndRehydrates() {
        store.add(text: "Prefer swift build over make", category: .toolUse, scope: .global)
        let rehydrated = LessonStore(globalFileURL: tempDir.appendingPathComponent("global-lessons.json"))
        XCTAssertEqual(rehydrated.lessons.count, 1)
        XCTAssertEqual(rehydrated.lessons.first?.scope, .global)
    }

    func testDuplicateTextReinforcesInsteadOfSplitting() {
        let first = store.add(text: "Always lint before commit.", category: .process, scope: .global)
        let second = store.add(text: "always lint before commit", category: .process, scope: .global)
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(store.lessons.count, 1)
        XCTAssertEqual(store.lessons.first?.winCount, 1)
    }

    func testInjectionAndOutcomeAttribution() {
        let lesson = store.add(text: "Check the ring buffer cap", category: .codeStyle, scope: .global)
        store.recordInjection(ids: [lesson.id])
        store.recordOutcome(ids: [lesson.id], success: true)
        let updated = store.lessons.first { $0.id == lesson.id }
        XCTAssertEqual(updated?.hitCount, 1)
        XCTAssertEqual(updated?.winCount, 1)

        store.recordInjection(ids: [lesson.id])
        store.recordOutcome(ids: [lesson.id], success: false)
        let after = store.lessons.first { $0.id == lesson.id }
        XCTAssertEqual(after?.hitCount, 2)
        XCTAssertEqual(after?.lossCount, 1)
    }

    func testRelevantPutsPinnedFirstAndSkipsRetired() {
        let pinned = store.add(text: "Pinned rule", category: .process, scope: .global)
        store.pin(id: pinned.id)
        let hot = store.add(
            text: "Use xcodegen", category: .toolUse,
            triggerKeywords: ["xcodegen"], scope: .global
        )
        let dead = store.add(text: "Retired rule", category: .process, scope: .global)
        store.retire(id: dead.id)

        let picked = store.relevant(for: "xcodegen question", limit: 5)
        XCTAssertEqual(picked.first?.id, pinned.id, "pinned first even when less relevant")
        XCTAssertTrue(picked.contains { $0.id == hot.id })
        XCTAssertFalse(picked.contains { $0.id == dead.id })
    }

    func testWeakenEnoughTimesAutoRetires() {
        let lesson = store.add(text: "Fragile advice", category: .process, scope: .global)
        for _ in 0..<6 {
            store.weaken(id: lesson.id)
        }
        XCTAssertEqual(store.lessons.first { $0.id == lesson.id }?.status, .retired)
    }

    func testProjectScopeSwapsWithDirectory() throws {
        let projectA = tempDir.appendingPathComponent("projA")
        try FileManager.default.createDirectory(at: projectA, withIntermediateDirectories: true)
        store.setProjectDirectory(projectA.path)
        store.add(text: "Project A convention", category: .projectFact, scope: .project)
        XCTAssertEqual(store.lessons.filter { $0.scope == .project }.count, 1)

        store.setProjectDirectory("")
        XCTAssertTrue(store.lessons.filter { $0.scope == .project }.isEmpty)

        store.setProjectDirectory(projectA.path)
        XCTAssertEqual(store.lessons.filter { $0.scope == .project }.count, 1, "project lessons rehydrate")
    }

    func testDigestListsByConfidence() {
        store.add(text: "Alpha", category: .process, scope: .global)
        let digest = store.digest()
        XCTAssertTrue(digest.contains("Alpha"))
        XCTAssertTrue(digest.contains("0.50"))
    }
}
