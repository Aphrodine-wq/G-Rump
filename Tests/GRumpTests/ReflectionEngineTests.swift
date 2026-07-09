import XCTest
@testable import GRump

final class ReflectionEngineTests: XCTestCase {

    // MARK: - Trigger policy

    func testShouldReflectOnSignals() {
        let bad = RunOutcome(
            conversationId: nil, taskType: "debugging", iterations: 5, toolStats: [],
            buildFailures: 1, loopPivots: 0, regressionSummary: nil,
            adversarialCriticals: 0, success: false
        )
        XCTAssertTrue(ReflectionEngine.shouldReflect(outcome: bad, runsSinceReflection: 0, cadence: 5))
    }

    func testShouldReflectOnCadence() {
        let quiet = RunOutcome(
            conversationId: nil, taskType: "general", iterations: 2, toolStats: [],
            buildFailures: 0, loopPivots: 0, regressionSummary: nil,
            adversarialCriticals: 0, success: true
        )
        XCTAssertFalse(ReflectionEngine.shouldReflect(outcome: quiet, runsSinceReflection: 3, cadence: 5))
        XCTAssertTrue(ReflectionEngine.shouldReflect(outcome: quiet, runsSinceReflection: 5, cadence: 5))
    }

    // MARK: - Op parsing

    func testParsesAllOpKinds() {
        let json = """
        [
          {"op": "add", "text": "Run xcodegen after project.yml edits", "category": "tool_use", "keywords": ["xcodegen"], "scope": "project"},
          {"op": "reinforce", "id": "abc123"},
          {"op": "weaken", "id": "def456"},
          {"op": "revise", "id": "ghi789", "text": "Better wording"}
        ]
        """
        let ops = ReflectionEngine.parseOps(from: json)
        XCTAssertEqual(ops.count, 4)
        XCTAssertEqual(ops[1], .reinforce(id: "abc123"))
        XCTAssertEqual(ops[2], .weaken(id: "def456"))
        XCTAssertEqual(ops[3], .revise(id: "ghi789", text: "Better wording"))
        if case .add(let text, let category, let keywords, let scope) = ops[0] {
            XCTAssertEqual(text, "Run xcodegen after project.yml edits")
            XCTAssertEqual(category, .toolUse)
            XCTAssertEqual(keywords, ["xcodegen"])
            XCTAssertEqual(scope, .project)
        } else {
            XCTFail("first op should be add")
        }
    }

    func testParsesFencedAndPaddedResponses() {
        let fenced = """
        ```json
        [{"op": "reinforce", "id": "abc"}]
        ```
        """
        XCTAssertEqual(ReflectionEngine.parseOps(from: fenced), [.reinforce(id: "abc")])

        let padded = "Here are my ops: [{\"op\": \"weaken\", \"id\": \"xyz\"}] — done."
        XCTAssertEqual(ReflectionEngine.parseOps(from: padded), [.weaken(id: "xyz")])
    }

    func testEmptyAndGarbageResponsesParseToNoOps() {
        XCTAssertTrue(ReflectionEngine.parseOps(from: "[]").isEmpty)
        XCTAssertTrue(ReflectionEngine.parseOps(from: "no json here").isEmpty)
        XCTAssertTrue(ReflectionEngine.parseOps(from: "[{\"op\": \"unknown\"}]").isEmpty)
    }

    func testProposeSkillRequiresThreeLessonCluster() {
        let two = """
        [{"op": "propose_skill", "skill_id": "x", "name": "X", "body": "b", "lesson_ids": ["a", "b"]}]
        """
        XCTAssertTrue(ReflectionEngine.parseOps(from: two).isEmpty, "under-clustered proposals are dropped")

        let three = """
        [{"op": "propose_skill", "skill_id": "x", "name": "X", "description": "d", "body": "b", "rationale": "r", "lesson_ids": ["a", "b", "c"]}]
        """
        let ops = ReflectionEngine.parseOps(from: three)
        XCTAssertEqual(ops.count, 1)
        if case .proposeSkill(let draft) = ops[0] {
            XCTAssertEqual(draft.skillId, "x")
            XCTAssertEqual(draft.lessonIds.count, 3)
        } else {
            XCTFail("expected proposeSkill")
        }
    }

    // MARK: - Input assembly

    func testReflectionInputContainsTheSignals() {
        let outcome = RunOutcome(
            conversationId: nil, taskType: "debugging", iterations: 7,
            toolStats: [RunOutcome.ToolStat(name: "run_build", calls: 3, failures: 2)],
            buildFailures: 2, loopPivots: 1, regressionSummary: "suspected abc123: broke parser",
            adversarialCriticals: 1, injectedLessonIds: ["l1"],
            userCorrections: ["message: \"that broke\""], success: false
        )
        let lesson = Lesson(id: "l1", text: "Check the parser first", category: .process, scope: .project)
        let input = ReflectionEngine.buildReflectionInput(
            outcome: outcome,
            transcriptTail: "user: fix it\n---\nassistant: done",
            injectedLessons: [lesson],
            lessonDigest: "[l1] (0.50, project) Check the parser first",
            rejectedProposalNames: ["bad-skill"],
            trigger: "signal"
        )
        XCTAssertTrue(input.contains("run_build: 3 calls, 2 failures"))
        XCTAssertTrue(input.contains("suspected abc123"))
        XCTAssertTrue(input.contains("that broke"))
        XCTAssertTrue(input.contains("Check the parser first"))
        XCTAssertTrue(input.contains("bad-skill"))
        XCTAssertTrue(input.contains("Transcript tail"))
    }

    // MARK: - Result notices

    func testNoticeTextSummarizesOps() {
        var result = ReflectionResult()
        XCTAssertNil(result.noticeText)
        result.added = 2
        result.weakened = 1
        let notice = result.noticeText ?? ""
        XCTAssertTrue(notice.contains("saved 2 lessons"))
        XCTAssertTrue(notice.contains("weakened 1"))
        XCTAssertTrue(notice.hasPrefix("Learning:"))
    }

    func testRouterHasReflectionChain() {
        // Reflection routes cheap-first and never to Fable.
        let fallback = AIModelRegistry.shared.defaultModel()
        let chain = ModelRouter.fallbackChain(for: .reflection, fallback: fallback)
        XCTAssertFalse(chain.isEmpty)
        XCTAssertFalse(chain.contains { $0.id.contains("fable") })
    }
}
