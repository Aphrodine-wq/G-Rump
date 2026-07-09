import XCTest
@testable import GRump

final class ModelRouterTests: XCTestCase {

    private var fallback: EnhancedAIModel {
        AIModelRegistry.shared.defaultModel()
    }

    private var sonnet: EnhancedAIModel? {
        AIModelRegistry.shared.getModel(by: "claude-sonnet-5")
    }

    // MARK: - Basic Routing

    func testRouteReturnsModel() {
        let model = ModelRouter.route(taskType: .codeGen, fallback: fallback)
        XCTAssertFalse(model.displayName.isEmpty)
    }

    func testRouteAllTaskTypes() {
        for taskType in TaskType.allCases {
            let model = ModelRouter.route(taskType: taskType, fallback: fallback)
            XCTAssertFalse(model.rawValue.isEmpty,
                "Route returned empty model for \(taskType.rawValue)")
        }
    }

    func testHeavyTasksRouteToOpus() {
        for taskType in [TaskType.reasoning, .planning, .debugging, .codeGen, .testing] {
            let model = ModelRouter.route(taskType: taskType, fallback: fallback)
            XCTAssertEqual(model.id, "claude-opus-4-8", "\(taskType.rawValue) should lead with Opus")
        }
    }

    func testLightTasksRouteToHaiku() {
        for taskType in [TaskType.fileOps, .search] {
            let model = ModelRouter.route(taskType: taskType, fallback: fallback)
            XCTAssertEqual(model.id, "claude-haiku-4-5", "\(taskType.rawValue) should lead with Haiku")
        }
    }

    func testGeneralRoutesToFallback() {
        guard let sonnet else { return XCTFail("catalog missing sonnet") }
        let model = ModelRouter.route(taskType: .general, fallback: sonnet)
        XCTAssertEqual(model.id, sonnet.id)
    }

    // MARK: - Fallback Chain

    func testFallbackChainNotEmpty() {
        for taskType in TaskType.allCases {
            let chain = ModelRouter.fallbackChain(for: taskType, fallback: fallback)
            XCTAssertFalse(chain.isEmpty,
                "Fallback chain empty for \(taskType.rawValue)")
        }
    }

    func testFallbackChainContainsFallback() {
        guard let sonnet else { return XCTFail("catalog missing sonnet") }
        for taskType in TaskType.allCases {
            let chain = ModelRouter.fallbackChain(for: taskType, fallback: sonnet)
            XCTAssertTrue(chain.contains(where: { $0.id == sonnet.id }),
                "Fallback chain for \(taskType.rawValue) should contain the fallback model")
        }
    }

    func testFallbackChainNeverAutoRoutesToFable() {
        for taskType in TaskType.allCases {
            let chain = ModelRouter.fallbackChain(for: taskType, fallback: fallback)
            XCTAssertFalse(chain.contains(where: { $0.id == "claude-fable-5" }),
                "\(taskType.rawValue) chain must never auto-route to Fable (premium)")
        }
    }

    func testFallbackChainHasNoDuplicates() {
        guard let sonnet else { return XCTFail("catalog missing sonnet") }
        for taskType in TaskType.allCases {
            // Sonnet appears in most preference lists AND as the fallback —
            // the chain must dedupe by id.
            let chain = ModelRouter.fallbackChain(for: taskType, fallback: sonnet)
            let ids = chain.map(\.id)
            XCTAssertEqual(ids.count, Set(ids).count, "\(taskType.rawValue) chain has duplicates: \(ids)")
        }
    }

    // MARK: - Context-Aware Routing

    func testRouteWithSmallTokenCount() {
        let model = ModelRouter.route(taskType: .codeGen, fallback: fallback, estimatedTokens: 1000)
        XCTAssertGreaterThan(model.contextWindow - model.maxOutput, 1000)
    }

    func testRouteWithLargeTokenCountSkipsSmallContextModels() {
        // 500K tokens exceeds Haiku's 200K window — fileOps must not pick it.
        let model = ModelRouter.route(taskType: .fileOps, fallback: fallback, estimatedTokens: 500_000)
        XCTAssertGreaterThan(model.contextWindow - model.maxOutput, 500_000)
        XCTAssertNotEqual(model.id, "claude-haiku-4-5")
    }

    func testRouteWithZeroTokens() {
        let model = ModelRouter.route(taskType: .general, fallback: fallback, estimatedTokens: 0)
        XCTAssertFalse(model.rawValue.isEmpty)
    }

    // MARK: - Task Type Detection

    func testDetectCodeGen() {
        let taskType = ModelRouter.detectTaskType(from: "implement a login page with authentication")
        XCTAssertEqual(taskType, .codeGen)
    }

    func testDetectDebugging() {
        let taskType = ModelRouter.detectTaskType(from: "fix the bug causing a crash in the login flow")
        XCTAssertEqual(taskType, .debugging)
    }

    func testDetectTesting() {
        let taskType = ModelRouter.detectTaskType(from: "write unit tests for the authentication module")
        XCTAssertEqual(taskType, .testing)
    }

    func testDetectReasoning() {
        let taskType = ModelRouter.detectTaskType(from: "analyze the tradeoff between REST and GraphQL, compare pros and cons")
        XCTAssertEqual(taskType, .reasoning)
    }

    func testDetectPlanning() {
        let taskType = ModelRouter.detectTaskType(from: "outline the steps for the migration strategy")
        XCTAssertEqual(taskType, .planning)
    }

    func testDetectFileOps() {
        let taskType = ModelRouter.detectTaskType(from: "read file and edit file to rename the variable")
        XCTAssertEqual(taskType, .fileOps)
    }

    func testDetectWeb() {
        let taskType = ModelRouter.detectTaskType(from: "web search for the latest Swift concurrency documentation")
        XCTAssertEqual(taskType, .web)
    }

    func testDetectWriting() {
        let taskType = ModelRouter.detectTaskType(from: "write docs and update the readme changelog")
        XCTAssertEqual(taskType, .writing)
    }

    func testDetectGeneralForAmbiguous() {
        let taskType = ModelRouter.detectTaskType(from: "hello world")
        XCTAssertEqual(taskType, .general)
    }

    func testDetectGeneralForEmpty() {
        let taskType = ModelRouter.detectTaskType(from: "")
        XCTAssertEqual(taskType, .general)
    }

    func testDetectIsCaseInsensitive() {
        let lower = ModelRouter.detectTaskType(from: "debug the crash")
        let upper = ModelRouter.detectTaskType(from: "DEBUG THE CRASH")
        XCTAssertEqual(lower, upper)
    }
}
