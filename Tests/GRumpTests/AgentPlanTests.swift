import XCTest
@testable import GRump

@MainActor
final class AgentPlanTests: XCTestCase {

    // MARK: - Model

    func testOpenStepsExcludesDone() {
        let plan = AgentPlan(steps: [
            .init(title: "a", status: .done),
            .init(title: "b", status: .inProgress),
            .init(title: "c", status: .pending),
        ])
        XCTAssertEqual(plan.openSteps.map(\.title), ["b", "c"])
    }

    func testMarkdownSnapshotMarkers() {
        let plan = AgentPlan(steps: [
            .init(title: "read files", status: .done),
            .init(title: "edit code", status: .inProgress),
            .init(title: "run build", status: .pending),
        ])
        let md = plan.markdownSnapshot()
        XCTAssertTrue(md.contains("- [x] read files"))
        XCTAssertTrue(md.contains("- [~] edit code"))
        XCTAssertTrue(md.contains("- [ ] run build"))
    }

    func testMarkdownSnapshotCaps() {
        let steps = (0..<30).map { AgentPlan.Step(title: "step \($0) with a reasonably long title padding", status: .pending) }
        let plan = AgentPlan(steps: steps)
        let md = plan.markdownSnapshot(cap: 200)
        XCTAssertLessThanOrEqual(md.count, 230, "cap plus truncation marker")
        XCTAssertTrue(md.contains("truncated"))
    }

    // MARK: - Tool executor

    func testExecuteUpdatePlanStoresAndRenders() {
        let vm = ChatViewModel()
        let result = vm.executeUpdatePlan(["steps": [
            ["title": "inspect repo", "status": "done"],
            ["title": "make edits", "status": "in_progress"],
            ["title": "verify build", "status": "pending"],
        ]])
        XCTAssertTrue(result.contains("3 steps, 2 open"), "unexpected result: \(result)")
        XCTAssertEqual(vm.currentPlan?.steps.count, 3)
        XCTAssertEqual(vm.currentPlan?.openSteps.count, 2)
    }

    func testExecuteUpdatePlanRejectsMissingSteps() {
        let vm = ChatViewModel()
        XCTAssertTrue(vm.executeUpdatePlan([:]).hasPrefix("Error"))
        XCTAssertNil(vm.currentPlan)
    }

    func testExecuteUpdatePlanRejectsEmptyTitle() {
        let vm = ChatViewModel()
        let result = vm.executeUpdatePlan(["steps": [["title": "  ", "status": "pending"]]])
        XCTAssertTrue(result.hasPrefix("Error"))
        XCTAssertNil(vm.currentPlan)
    }

    func testExecuteUpdatePlanEmptyArrayClears() {
        let vm = ChatViewModel()
        _ = vm.executeUpdatePlan(["steps": [["title": "x", "status": "pending"]]])
        XCTAssertNotNil(vm.currentPlan)
        let result = vm.executeUpdatePlan(["steps": [[String: Any]]()])
        XCTAssertTrue(result.contains("cleared"))
        XCTAssertNil(vm.currentPlan)
    }

    func testExecuteUpdatePlanUnknownStatusDefaultsToPending() {
        let vm = ChatViewModel()
        _ = vm.executeUpdatePlan(["steps": [["title": "x", "status": "bogus"]]])
        XCTAssertEqual(vm.currentPlan?.steps.first?.status, .pending)
    }

    // MARK: - Conversation scoping

    func testNewConversationClearsPlan() {
        let vm = ChatViewModel()
        _ = vm.executeUpdatePlan(["steps": [["title": "x", "status": "pending"]]])
        XCTAssertNotNil(vm.currentPlan)
        vm.createNewConversation()
        XCTAssertNil(vm.currentPlan)
    }

    // MARK: - Prompt injection

    func testBuildAPIMessagesAppendsTrailingPlanNote() {
        let vm = ChatViewModel()
        vm.createNewConversation()
        vm.currentConversation?.messages.append(Message(role: .user, content: "do the thing"))
        _ = vm.executeUpdatePlan(["steps": [["title": "first step", "status": "pending"]]])
        let messages = vm.buildAPIMessages(cachedPrompt: "sys")
        let last = messages.last
        XCTAssertEqual(last?.role, .user)
        XCTAssertTrue(last?.content.contains("Current tracked plan") ?? false)
        XCTAssertTrue(last?.content.contains("first step") ?? false)
    }
}
