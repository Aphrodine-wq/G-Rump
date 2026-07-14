import XCTest
@testable import GRump

@MainActor
final class CompletionCheckTests: XCTestCase {

    // MARK: - shouldRun predicate truth table

    private func should(
        gate: Bool = true, changes: Bool = true, open: Int = 0,
        iter: Int = 5, maxIter: Int = 200, retries: Int = 0
    ) -> Bool {
        CompletionCheck.shouldRun(
            gateEnabled: gate, hasCodeChanges: changes, openPlanSteps: open,
            iterationCount: iter, maxIterations: maxIter, completionRetries: retries)
    }

    func testShouldRunHappyPath() {
        XCTAssertTrue(should())
        XCTAssertTrue(should(changes: false, open: 3), "open plan steps alone warrant a check")
    }

    func testShouldRunGateDisabled() {
        XCTAssertFalse(should(gate: false))
    }

    func testShouldRunNoWorkHappened() {
        XCTAssertFalse(should(changes: false, open: 0), "conversational replies never enter the gate")
    }

    func testShouldRunFirstIterationSkipped() {
        XCTAssertFalse(should(iter: 1), "single-turn replies never enter the gate")
    }

    func testShouldRunNearStepLimitSkipped() {
        XCTAssertFalse(should(iter: 199, maxIter: 200))
        XCTAssertFalse(should(iter: 200, maxIter: 200))
    }

    func testShouldRunRetryCap() {
        XCTAssertTrue(should(retries: 1))
        XCTAssertFalse(should(retries: 2), "max 2 re-entries per run")
    }

    // MARK: - Verdict parsing (fail-open on garbage)

    func testParseCleanVerdict() {
        let v = CompletionCheck.parseVerdict(#"{"complete": false, "unfinished": ["update the README"], "reason": "readme untouched"}"#)
        XCTAssertEqual(v?.complete, false)
        XCTAssertEqual(v?.unfinished, ["update the README"])
        XCTAssertEqual(v?.reason, "readme untouched")
    }

    func testParseFencedVerdict() {
        let raw = """
        ```json
        {"complete": true, "unfinished": [], "reason": "all done"}
        ```
        """
        XCTAssertEqual(CompletionCheck.parseVerdict(raw)?.complete, true)
    }

    func testParseVerdictEmbeddedInProse() {
        let raw = #"Here's my assessment: {"complete": false, "unfinished": ["x"], "reason": "y"} — hope that helps."#
        XCTAssertEqual(CompletionCheck.parseVerdict(raw)?.complete, false)
    }

    func testParseGarbageFailsOpen() {
        XCTAssertNil(CompletionCheck.parseVerdict("I think it's probably done?"))
        XCTAssertNil(CompletionCheck.parseVerdict(""))
        XCTAssertNil(CompletionCheck.parseVerdict("{\"unfinished\": []}"), "missing 'complete' key must not parse")
    }

    // MARK: - Build-failure classifier

    func testBuildFailedOnExitCodeMarker() {
        XCTAssertTrue(ChatViewModel.buildFailed("Compiling...\nerror: cannot find 'foo'\n[exit code: 1]"))
        XCTAssertTrue(ChatViewModel.buildFailed("(no output, exit code: 2)\n[exit code: 2]"))
    }

    func testBuildFailedOnEcosystemMarkers() {
        XCTAssertTrue(ChatViewModel.buildFailed("** BUILD FAILED **"))
        XCTAssertTrue(ChatViewModel.buildFailed("npm ERR! missing script: build"))
        XCTAssertTrue(ChatViewModel.buildFailed("error[E0308]: mismatched types"))
    }

    func testBuildSucceededOutputPasses() {
        XCTAssertFalse(ChatViewModel.buildFailed("Build complete! (2.31s)"))
        XCTAssertFalse(ChatViewModel.buildFailed("Compiling GRump\nBuild succeeded"))
    }

    // MARK: - ProjectConfig verification fields

    func testProjectConfigDecodesWithoutNewFields() throws {
        let legacy = #"{"model": "claude-opus-4-8"}"#.data(using: .utf8)!
        let cfg = try JSONDecoder().decode(ProjectConfig.self, from: legacy)
        XCTAssertNil(cfg.autoVerify)
        XCTAssertNil(cfg.buildCommand)
        XCTAssertNil(cfg.testCommand)
    }

    func testProjectConfigDecodesNewFields() throws {
        let json = #"{"autoVerify": false, "buildCommand": "make fast", "testCommand": "npm test -- --quick"}"#.data(using: .utf8)!
        let cfg = try JSONDecoder().decode(ProjectConfig.self, from: json)
        XCTAssertEqual(cfg.autoVerify, false)
        XCTAssertEqual(cfg.buildCommand, "make fast")
        XCTAssertEqual(cfg.testCommand, "npm test -- --quick")
    }
}
