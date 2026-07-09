import XCTest
@testable import GRump

final class ProtectedPathsTests: XCTestCase {

    private func target(_ tool: String, path: String, wd: String = "/proj") -> String? {
        ChatViewModel.protectedWriteTarget(toolName: tool, args: ["path": path], workingDirectory: wd)
    }

    func testSoulAndMindAreProtected() {
        XCTAssertNotNil(target("write_file", path: "/Users/x/.grump/SOUL.md"))
        XCTAssertNotNil(target("edit_file", path: ".grump/SOUL.md"))
        XCTAssertNotNil(target("delete_file", path: "/proj/.grump/MIND.md"))
        XCTAssertNotNil(target("append_file", path: "soul.md", wd: "/proj"))
    }

    func testSkillsDirectoriesAreProtected() {
        XCTAssertNotNil(target("write_file", path: "/Users/x/.grump/skills/foo/SKILL.md"))
        XCTAssertNotNil(target("create_file", path: ".grump/skills/new/SKILL.md"))
    }

    func testOrdinaryWritesAreNot() {
        XCTAssertNil(target("write_file", path: "/proj/Sources/App/Main.swift"))
        XCTAssertNil(target("edit_file", path: "README.md"))
    }

    func testReadOnlyToolsAreNeverProtected() {
        XCTAssertNil(target("read_file", path: "/Users/x/.grump/SOUL.md"))
        XCTAssertNil(target("list_directory", path: "/Users/x/.grump/skills"))
    }

    func testRelativePathsResolveAgainstWorkingDirectory() {
        XCTAssertNotNil(target("write_file", path: "../.grump/skills/x/SKILL.md", wd: "/proj/sub"))
    }
}
