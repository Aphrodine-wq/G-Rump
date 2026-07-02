import XCTest
@testable import GRump

final class DaemonTests: XCTestCase {

    // MARK: - GoalStore (isolated temp vault)

    func testGoalStoreRoundTrip() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("grump-goals-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp.appendingPathComponent(".grump/vault"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store = GoalStore(workingDirectory: tmp.path)
        let g1 = await store.addGoal(title: "Add tests for Foo", body: "cover the parser", priority: 2)
        _ = await store.addGoal(title: "Low priority cleanup", body: "tidy imports", priority: 1)

        let pending = await store.pendingGoals()
        XCTAssertEqual(pending.count, 2)
        XCTAssertEqual(pending.first?.title, "Add tests for Foo", "higher priority should sort first")

        await store.markStatus(g1, "done")
        let stillPending = await store.pendingGoals()
        XCTAssertEqual(stillPending.count, 1)
        XCTAssertEqual(stillPending.first?.title, "Low priority cleanup")
    }

    // MARK: - LearningStore (injected path)

    func testLearningStore() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("grump-learn-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store = LearningStore(path: tmp)
        await store.record(key: "goal", success: true, duration: 10)
        await store.record(key: "goal", success: false, duration: 20)
        await store.record(key: "goal", success: true, duration: 30)

        let rate = await store.successRate(for: "goal")
        XCTAssertEqual(rate, 2.0 / 3.0, accuracy: 0.001)
        let avg = await store.averageDuration(for: "goal")
        XCTAssertEqual(avg, 20, accuracy: 0.001)
    }

    // NOTE: DaemonApprovalCoordinator.requestApproval can't be unit-tested headlessly —
    // it posts a UNUserNotificationCenter notification, which crashes in the SPM test
    // runner (no app bundle). Its resolve/timeout logic is exercised only in the live app.

    // MARK: - Immune check (healthy environment)

    func testImmuneCheckHealthy() async {
        let issues = await ImmuneJob.check()
        XCTAssertTrue(issues.isEmpty, "expected a healthy environment, got: \(issues)")
    }
}
