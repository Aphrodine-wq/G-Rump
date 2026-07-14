import XCTest
@testable import GRump

/// Covers the reliability contract of `executeEditFile`: uniqueness guarding,
/// explicit replace_all, and the whitespace-tolerant single-match fallback.
@MainActor
final class EditFileRobustnessTests: XCTestCase {

    private var tempDir: URL!
    private var vm: ChatViewModel!

    override func setUp() async throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("edit-robustness-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        vm = ChatViewModel()
        vm.workingDirectory = tempDir.path
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func write(_ name: String, _ content: String) throws -> String {
        let url = tempDir.appendingPathComponent(name)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    private func read(_ path: String) -> String {
        (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    }

    // MARK: - Uniqueness guard

    func testMultiMatchWithoutReplaceAllFailsAndWritesNothing() throws {
        let path = try write("multi.txt", "let x = 1\nlet x = 1\nlet y = 2\n")
        let result = vm.executeEditFile(["path": path, "old_content": "let x = 1", "new_content": "let x = 9"])
        XCTAssertTrue(result.contains("matches 2 locations"), "should refuse ambiguous edits: \(result)")
        XCTAssertTrue(result.contains("replace_all"), "error should mention the replace_all escape hatch")
        XCTAssertEqual(read(path), "let x = 1\nlet x = 1\nlet y = 2\n", "file must be untouched")
    }

    func testMultiMatchWithReplaceAllReplacesEverything() throws {
        let path = try write("all.txt", "foo()\nbar()\nfoo()\n")
        let result = vm.executeEditFile(["path": path, "old_content": "foo()", "new_content": "baz()", "replace_all": true])
        XCTAssertTrue(result.contains("2 replacements"), "unexpected result: \(result)")
        XCTAssertEqual(read(path), "baz()\nbar()\nbaz()\n")
    }

    func testUniqueExactMatchStillWorks() throws {
        let path = try write("unique.txt", "alpha\nbeta\ngamma\n")
        let result = vm.executeEditFile(["path": path, "old_content": "beta", "new_content": "BETA"])
        XCTAssertTrue(result.contains("1 replacement"), "unexpected result: \(result)")
        XCTAssertEqual(read(path), "alpha\nBETA\ngamma\n")
    }

    // MARK: - Whitespace-tolerant fallback

    func testWhitespaceTolerantSingleMatchApplies() throws {
        let path = try write("indent.swift", "func run() {\n        return compute()\n}\n")
        // Model proposes the line with WRONG indentation — exact match fails.
        let result = vm.executeEditFile([
            "path": path,
            "old_content": "    return compute()",
            "new_content": "        return computeFast()",
        ])
        XCTAssertTrue(result.contains("whitespace-tolerant"), "should flag the tolerant match: \(result)")
        XCTAssertTrue(read(path).contains("return computeFast()"))
    }

    func testWhitespaceTolerantSpliceIsVerbatim() throws {
        let path = try write("verbatim.swift", "if ok {\n            doWork()\n}\n")
        let result = vm.executeEditFile([
            "path": path,
            "old_content": "doWork()",
            "new_content": "doOtherWork()",
        ])
        XCTAssertTrue(result.contains("whitespace-tolerant"), "unexpected result: \(result)")
        // new_content splices VERBATIM — no re-indent guessing.
        XCTAssertEqual(read(path), "if ok {\ndoOtherWork()\n}\n")
    }

    func testWhitespaceTolerantMultiMatchFails() throws {
        let path = try write("ambiguous.swift", "  retry()\n\tretry()\ndone()\n")
        let result = vm.executeEditFile([
            "path": path,
            "old_content": "retry()",
            "new_content": "retryOnce()",
        ])
        XCTAssertTrue(result.contains("whitespace-tolerant") && result.contains("2 locations"), "unexpected result: \(result)")
        XCTAssertEqual(read(path), "  retry()\n\tretry()\ndone()\n", "file must be untouched")
    }

    // MARK: - Near-miss hints survive as the final fallback

    func testNearMissHintStillFires() throws {
        let path = try write("hint.swift", "let total = sum(items)\n")
        let result = vm.executeEditFile([
            "path": path,
            "old_content": "let total = sum(items, tax)",
            "new_content": "let total = sum(items)",
        ])
        XCTAssertTrue(result.contains("similar content exists at line 1"), "unexpected result: \(result)")
    }

    func testNotFoundAtAllReturnsReadFileGuidance() throws {
        let path = try write("missing.swift", "let a = 1\n")
        let result = vm.executeEditFile([
            "path": path,
            "old_content": "completely absent content",
            "new_content": "x",
        ])
        XCTAssertTrue(result.contains("not found") && result.contains("read_file"), "unexpected result: \(result)")
    }

    // MARK: - Stream retry decision (per-turn semantics)

    func testShouldRetryHonorsPerTurnAttemptCap() {
        let transient = URLError(.timedOut)
        XCTAssertTrue(vm.shouldRetry(error: transient, attempt: 1))
        XCTAssertTrue(vm.shouldRetry(error: transient, attempt: 3))
        XCTAssertFalse(vm.shouldRetry(error: transient, attempt: 4), "cap is 3 retries per turn")
    }
}
