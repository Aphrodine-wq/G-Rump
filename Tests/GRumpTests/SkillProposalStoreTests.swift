import XCTest
@testable import GRump

@MainActor
final class SkillProposalStoreTests: XCTestCase {

    private var tempDir: URL!
    private var store: SkillProposalStore!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SkillProposalStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = SkillProposalStore(fileURL: tempDir.appendingPathComponent("proposals.json"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func draft(_ id: String) -> SkillProposalDraft {
        SkillProposalDraft(
            skillId: id, name: "Skill \(id)", description: "d",
            body: "# Body", rationale: "r", lessonIds: ["a", "b", "c"]
        )
    }

    func testProposePersistsAndRehydrates() {
        XCTAssertNil(store.propose(draft: draft("one"), source: "test"))
        XCTAssertEqual(store.pendingCount, 1)

        let rehydrated = SkillProposalStore(fileURL: tempDir.appendingPathComponent("proposals.json"))
        XCTAssertEqual(rehydrated.pendingCount, 1)
        XCTAssertEqual(rehydrated.pending.first?.draft.skillId, "one")
    }

    func testPendingCapRefusesNewProposals() {
        for index in 0..<10 {
            XCTAssertNil(store.propose(draft: draft("skill-\(index)"), source: "test"))
        }
        let refusal = store.propose(draft: draft("overflow"), source: "test")
        XCTAssertNotNil(refusal)
        XCTAssertTrue(refusal?.contains("full") == true)
        XCTAssertEqual(store.pendingCount, 10)
    }

    func testDuplicatePendingRefused() {
        XCTAssertNil(store.propose(draft: draft("dup"), source: "test"))
        XCTAssertNotNil(store.propose(draft: draft("dup"), source: "test"))
        XCTAssertEqual(store.pendingCount, 1)
    }

    func testRejectionPersistsAndBlocksReproposal() {
        XCTAssertNil(store.propose(draft: draft("nope"), source: "test"))
        let id = store.pending.first!.id
        store.reject(id: id)
        XCTAssertEqual(store.pendingCount, 0)
        XCTAssertEqual(store.rejectedNames, ["Skill nope"])
        XCTAssertNotNil(store.propose(draft: draft("nope"), source: "test"),
                        "rejected skill ids can never be re-proposed")

        let rehydrated = SkillProposalStore(fileURL: tempDir.appendingPathComponent("proposals.json"))
        XCTAssertEqual(rehydrated.rejectedNames, ["Skill nope"])
    }

    func testRejectOnlyTouchesPending() {
        XCTAssertNil(store.propose(draft: draft("keep"), source: "test"))
        store.reject(id: "nonexistent")
        XCTAssertEqual(store.pendingCount, 1)
    }
}
