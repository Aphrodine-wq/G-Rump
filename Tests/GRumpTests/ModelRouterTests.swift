import XCTest
@testable import GRump

final class ModelRouterTests: XCTestCase {

    // MARK: - Basic Routing

    func testRouteReturnsModel() {
        let fallback = AIModel.qwenCoderPlus
        let model = ModelRouter.route(taskType: .codeGen, fallback: fallback)
        XCTAssertFalse(model.displayName.isEmpty)
    }

    func testRouteAllTaskTypes() {
        let fallback = AIModel.qwenCoderPlus
        for taskType in TaskType.allCases {
            let model = ModelRouter.route(taskType: taskType, fallback: fallback)
            XCTAssertFalse(model.rawValue.isEmpty,
                "Route returned empty model for \(taskType.rawValue)")
        }
    }

    // MARK: - Fallback Chain

    func testFallbackChainNotEmpty() {
        let fallback = AIModel.qwenPlus
        for taskType in TaskType.allCases {
            let chain = ModelRouter.fallbackChain(for: taskType, fallback: fallback)
            XCTAssertFalse(chain.isEmpty,
                "Fallback chain empty for \(taskType.rawValue)")
        }
    }

    func testFallbackChainContainsFallback() {
        let fallback = AIModel.qwenTurbo
        for taskType in TaskType.allCases {
            let chain = ModelRouter.fallbackChain(for: taskType, fallback: fallback)
            XCTAssertTrue(chain.contains(fallback),
                "Fallback chain for \(taskType.rawValue) should contain the fallback model")
        }
    }

    func testFallbackChainFirstIsPreferred() {
        let fallback = AIModel.qwenCoderPlus
        // For code gen, the first should be a coding-focused model
        let chain = ModelRouter.fallbackChain(for: .codeGen, fallback: fallback)
        XCTAssertGreaterThanOrEqual(chain.count, 2)
        // First model should be a strong coder
        let first = chain[0]
        XCTAssertFalse(first.displayName.isEmpty)
    }

    // MARK: - Context-Aware Routing

    func testRouteWithSmallTokenCount() {
        let fallback = AIModel.qwenCoderPlus
        let model = ModelRouter.route(taskType: .codeGen, fallback: fallback, estimatedTokens: 1000)
        XCTAssertGreaterThan(model.contextWindow - model.maxOutput, 1000)
    }

    func testRouteWithLargeTokenCount() {
        let fallback = AIModel.qwenCoderPlus
        let model = ModelRouter.route(taskType: .reasoning, fallback: fallback, estimatedTokens: 500_000)
        // Should pick a model with large context
        XCTAssertGreaterThan(model.contextWindow, 100_000)
    }

    func testRouteWithZeroTokens() {
        let fallback = AIModel.qwenPlus
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
