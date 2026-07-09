import XCTest
@testable import GRump

final class DeveloperProfileTests: XCTestCase {

    private var tempFileURL: URL!

    override func setUpWithError() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeveloperProfileTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempFileURL = dir.appendingPathComponent("profile.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempFileURL.deletingLastPathComponent())
    }

    // MARK: - Persistence

    func testSaveLoadRoundTrip() {
        let profile = DeveloperProfile(
            name: "James",
            role: "Full-stack dev",
            preferredStack: "Swift, Next.js",
            codingStyle: "small diffs",
            conventions: "no force unwraps"
        )
        profile.save(to: tempFileURL)
        let loaded = DeveloperProfile.load(from: tempFileURL)
        XCTAssertEqual(loaded, profile)
    }

    func testLoadMissingFileReturnsEmptyProfile() {
        let loaded = DeveloperProfile.load(from: tempFileURL)
        XCTAssertTrue(loaded.isEmpty)
    }

    func testLoadCorruptFileReturnsEmptyProfile() throws {
        try Data("not json".utf8).write(to: tempFileURL)
        let loaded = DeveloperProfile.load(from: tempFileURL)
        XCTAssertTrue(loaded.isEmpty)
    }

    func testDecodeToleratesMissingKeys() throws {
        try Data(#"{"name": "James"}"#.utf8).write(to: tempFileURL)
        let loaded = DeveloperProfile.load(from: tempFileURL)
        XCTAssertEqual(loaded.name, "James")
        XCTAssertEqual(loaded.role, "")
    }

    // MARK: - Prompt Block

    func testPromptBlockNilWhenEmpty() {
        XCTAssertNil(DeveloperProfile().promptBlock)
        XCTAssertNil(DeveloperProfile(name: "   ", codingStyle: "\n").promptBlock)
    }

    func testPromptBlockContainsOnlyFilledFields() throws {
        let profile = DeveloperProfile(name: "James", preferredStack: "Swift")
        let block = try XCTUnwrap(profile.promptBlock)
        XCTAssertTrue(block.contains("Name: James"))
        XCTAssertTrue(block.contains("Preferred stack: Swift"))
        XCTAssertFalse(block.contains("Role:"))
        XCTAssertFalse(block.contains("Conventions:"))
        XCTAssertTrue(block.contains("--- Developer Profile ---"))
        XCTAssertTrue(block.contains("--- End of developer profile ---"))
    }

    func testPromptBlockRespectsCharacterCap() throws {
        let giant = String(repeating: "x", count: 5_000)
        let profile = DeveloperProfile(conventions: giant)
        let block = try XCTUnwrap(profile.promptBlock)
        // Body is capped; the wrapper adds a bounded amount on top.
        XCTAssertLessThan(block.count, DeveloperProfile.promptCharacterCap + 100)
        XCTAssertTrue(block.contains("…"))
    }

    func testIsEmpty() {
        XCTAssertTrue(DeveloperProfile().isEmpty)
        XCTAssertFalse(DeveloperProfile(role: "dev").isEmpty)
    }

    // MARK: - Prompt Chain Injection

    @MainActor
    func testPrependDeveloperProfileContentInjectsBlock() {
        let vm = ChatViewModel()
        let profile = DeveloperProfile(name: "James", role: "iOS dev")
        let result = vm.prependDeveloperProfileContent(to: "BASE", profile: profile)
        XCTAssertTrue(result.hasSuffix("BASE"))
        XCTAssertTrue(result.contains("Name: James"))
        XCTAssertTrue(result.contains("Role: iOS dev"))
    }

    @MainActor
    func testPrependDeveloperProfileContentEmptyProfileIsIdentity() {
        let vm = ChatViewModel()
        let result = vm.prependDeveloperProfileContent(to: "BASE", profile: DeveloperProfile())
        XCTAssertEqual(result, "BASE")
    }
}
