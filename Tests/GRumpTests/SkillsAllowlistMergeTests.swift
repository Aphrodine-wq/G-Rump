import XCTest
@testable import GRump

final class SkillsAllowlistMergeTests: XCTestCase {

    private let packs: [SkillPack] = [
        SkillPack(
            id: "pack-a",
            name: "Pack A",
            description: "First pack",
            skillBaseIds: ["alpha", "beta"],
            icon: "a.circle"
        ),
        SkillPack(
            id: "pack-b",
            name: "Pack B",
            description: "Second pack",
            skillBaseIds: ["beta", "gamma"],
            icon: "b.circle"
        )
    ]

    // MARK: - The wipe-bug guarantee

    func testZeroSelectionReturnsExistingUnchanged() {
        let existing: Set<String> = ["global:precious", "project:custom"]
        let merged = SkillPack.mergedAllowlist(selecting: [], into: existing, packs: packs)
        XCTAssertEqual(merged, existing)
    }

    func testZeroSelectionWithEmptyExistingStaysEmpty() {
        let merged = SkillPack.mergedAllowlist(selecting: [], into: [], packs: packs)
        XCTAssertTrue(merged.isEmpty)
    }

    func testExistingEntriesAreNeverRemoved() {
        let existing: Set<String> = ["global:precious"]
        let merged = SkillPack.mergedAllowlist(selecting: ["pack-a"], into: existing, packs: packs)
        XCTAssertTrue(merged.contains("global:precious"))
    }

    // MARK: - Union semantics

    func testSelectedPackSkillsAddedWithGlobalScope() {
        let merged = SkillPack.mergedAllowlist(selecting: ["pack-a"], into: [], packs: packs)
        XCTAssertEqual(merged, ["global:alpha", "global:beta"])
    }

    func testOverlappingPacksDedupe() {
        let merged = SkillPack.mergedAllowlist(selecting: ["pack-a", "pack-b"], into: [], packs: packs)
        XCTAssertEqual(merged, ["global:alpha", "global:beta", "global:gamma"])
    }

    func testUnknownPackIdIgnored() {
        let merged = SkillPack.mergedAllowlist(selecting: ["nope"], into: ["global:kept"], packs: packs)
        XCTAssertEqual(merged, ["global:kept"])
    }

    func testMergeIntoExistingCombines() {
        let merged = SkillPack.mergedAllowlist(
            selecting: ["pack-b"],
            into: ["global:alpha"],
            packs: packs
        )
        XCTAssertEqual(merged, ["global:alpha", "global:beta", "global:gamma"])
    }

    // MARK: - Real built-in packs sanity

    func testBuiltInDefaultSelectionProducesExpectedSkills() {
        let merged = SkillPack.mergedAllowlist(
            selecting: ["ios-dev", "code-quality"],
            into: [],
            packs: SkillPack.builtInPacks
        )
        XCTAssertTrue(merged.contains("global:swift-ios"))
        XCTAssertTrue(merged.contains("global:testing"))
        XCTAssertFalse(merged.contains("global:terraform"))
    }
}
