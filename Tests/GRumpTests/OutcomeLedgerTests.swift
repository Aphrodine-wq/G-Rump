import XCTest
@testable import GRump

final class OutcomeLedgerTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OutcomeLedgerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeOutcome(taskType: String = "general", success: Bool = true) -> RunOutcome {
        RunOutcome(
            conversationId: UUID(),
            taskType: taskType,
            iterations: 3,
            toolStats: [RunOutcome.ToolStat(name: "read_file", calls: 2, failures: 0)],
            buildFailures: 0,
            loopPivots: 0,
            regressionSummary: nil,
            adversarialCriticals: 0,
            success: success
        )
    }

    // MARK: - Recording + persistence

    func testRecordPersistsAndRehydrates() async {
        let ledger = OutcomeLedger()
        await ledger.setProjectDirectory(tempDir.path)
        await ledger.record(makeOutcome())

        let rehydrated = OutcomeLedger()
        await rehydrated.setProjectDirectory(tempDir.path)
        let outcomes = await rehydrated.outcomes
        XCTAssertEqual(outcomes.count, 1)
        XCTAssertEqual(outcomes.first?.toolStats.first?.name, "read_file")
    }

    func testCapDropsOldest() async {
        let ledger = OutcomeLedger()
        await ledger.setProjectDirectory(tempDir.path)
        for index in 0..<505 {
            await ledger.record(makeOutcome(taskType: "t\(index)"))
        }
        let outcomes = await ledger.outcomes
        XCTAssertEqual(outcomes.count, 500)
        XCTAssertEqual(outcomes.first?.taskType, "t5", "oldest five age out")
    }

    func testEmptyDirectoryIsInMemoryOnly() async {
        let ledger = OutcomeLedger()
        await ledger.setProjectDirectory("")
        await ledger.record(makeOutcome())
        let count = await ledger.outcomes.count
        XCTAssertEqual(count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent(".grump/outcomes.json").path))
    }

    // MARK: - Two-stage amendment

    func testAmendLastOutcomeFlipsSuccess() async {
        let ledger = OutcomeLedger()
        await ledger.setProjectDirectory(tempDir.path)
        await ledger.record(makeOutcome(success: true))
        await ledger.amendLastOutcome(corrections: ["message: \"that broke\""])

        let last = await ledger.outcomes.last
        XCTAssertEqual(last?.success, false)
        XCTAssertEqual(last?.amended, true)
        XCTAssertEqual(last?.userCorrections, ["message: \"that broke\""])
    }

    func testAmendWithNoCorrectionsIsNoOp() async {
        let ledger = OutcomeLedger()
        await ledger.setProjectDirectory(tempDir.path)
        await ledger.record(makeOutcome(success: true))
        await ledger.amendLastOutcome(corrections: [])
        let last = await ledger.outcomes.last
        XCTAssertEqual(last?.success, true)
        XCTAssertEqual(last?.amended, false)
    }

    // MARK: - Task-type success rate (Laplace)

    func testSuccessRateIsLaplaceSmoothed() async {
        let ledger = OutcomeLedger()
        await ledger.setProjectDirectory(tempDir.path)
        let empty = await ledger.successRate(taskType: "debugging")
        XCTAssertEqual(empty, 0.5, accuracy: 0.001, "no data → prior 1/2")

        await ledger.record(makeOutcome(taskType: "debugging", success: false))
        let afterLoss = await ledger.successRate(taskType: "debugging")
        XCTAssertEqual(afterLoss, 1.0 / 3.0, accuracy: 0.001)
    }

    // MARK: - Reflection counter

    func testReflectionCounterAccumulatesAndConsumes() async {
        let ledger = OutcomeLedger()
        await ledger.record(makeOutcome())
        await ledger.record(makeOutcome())
        var count = await ledger.runsSinceReflection
        XCTAssertEqual(count, 2)
        await ledger.consumeReflectionCounter()
        count = await ledger.runsSinceReflection
        XCTAssertEqual(count, 0)
    }

    // MARK: - Reflection-worthiness

    func testIsReflectionWorthy() {
        XCTAssertFalse(makeOutcome(success: true).isReflectionWorthy)
        XCTAssertTrue(makeOutcome(success: false).isReflectionWorthy)
        var pivoty = makeOutcome(success: true)
        pivoty = RunOutcome(
            conversationId: pivoty.conversationId, taskType: pivoty.taskType,
            iterations: 1, toolStats: [], buildFailures: 0, loopPivots: 2,
            regressionSummary: nil, adversarialCriticals: 0, success: true
        )
        XCTAssertTrue(pivoty.isReflectionWorthy)
    }

    // MARK: - Task classification

    func testTaskTypeClassification() {
        XCTAssertEqual(TaskType.classify(from: "Fix the crash in login"), .debugging)
        XCTAssertEqual(TaskType.classify(from: "Write tests for ProjectStore"), .testing)
        XCTAssertEqual(TaskType.classify(from: "Implement a new settings panel"), .codeGen)
        XCTAssertEqual(TaskType.classify(from: "hello"), .general)
    }
}

// MARK: - Correction Detector

final class UserCorrectionDetectorTests: XCTestCase {

    func testKeywordPhrasesDetected() {
        XCTAssertFalse(UserCorrectionDetector.reasons(message: "That's wrong, the button is blue").isEmpty)
        XCTAssertFalse(UserCorrectionDetector.reasons(message: "that didn't work at all").isEmpty)
        XCTAssertFalse(UserCorrectionDetector.reasons(message: "Undo that please").isEmpty)
    }

    func testLeadingNegationDetected() {
        XCTAssertFalse(UserCorrectionDetector.reasons(message: "No, use the other file").isEmpty)
        XCTAssertFalse(UserCorrectionDetector.reasons(message: "nope try the sidebar").isEmpty)
    }

    func testNeutralMessagesNotFlagged() {
        XCTAssertTrue(UserCorrectionDetector.reasons(message: "Now add a dark mode toggle").isEmpty)
        XCTAssertTrue(UserCorrectionDetector.reasons(message: "Thanks, looks great. Next: the footer").isEmpty)
        XCTAssertTrue(UserCorrectionDetector.reasons(message: "November is fine").isEmpty)
    }

    func testHardSignalsCountWithoutKeywords() {
        let reasons = UserCorrectionDetector.reasons(
            message: "hmm ok",
            rejectedCodeBlocks: 2,
            approvalDenials: 1
        )
        XCTAssertEqual(reasons.count, 2)
        XCTAssertTrue(reasons.contains { $0.contains("2 code block") })
        XCTAssertTrue(reasons.contains { $0.contains("1 command approval") })
    }
}
