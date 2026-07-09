import XCTest
@testable import GRump

/// Extended edge-case tests for FollowUpGenerator beyond the base FollowUpGeneratorTests.
final class FollowUpGeneratorExtendedTests: XCTestCase {

    // MARK: - Empty / Whitespace Messages

    func testEmptyMessageReturnsNoSuggestions() {
        let suggestions = FollowUpGenerator.generate(from: "", agentMode: .spec)
        XCTAssertTrue(suggestions.isEmpty, "Empty message should produce no suggestions")
    }

    func testWhitespaceOnlyMessageReturnsNoSuggestions() {
        let suggestions = FollowUpGenerator.generate(from: "   \n\t  ", agentMode: .spec)
        XCTAssertTrue(suggestions.isEmpty, "Whitespace-only message should produce no suggestions")
    }

    // MARK: - Extremely Long Messages

    func testVeryLongMessageDoesNotCrash() {
        let longMessage = String(repeating: "This is a test message with a function. ", count: 500)
        let suggestions = FollowUpGenerator.generate(from: longMessage, agentMode: .spec)
        XCTAssertLessThanOrEqual(suggestions.count, 2)
    }

    // MARK: - Overlapping Keyword Detection

    func testOverlappingKeywordsProduceMultipleSuggestions() {
        // Message triggers code + error + file-mod categories
        let message = """
        Here's the code:
        ```swift
        func fix() { }
        ```
        There's an error in the function I created.
        I've updated the file.
        """
        let suggestions = FollowUpGenerator.generate(from: message, agentMode: .spec)
        XCTAssertLessThanOrEqual(suggestions.count, 2, "Should be capped at 2")
        // Should have at least one relevant suggestion
        XCTAssertFalse(suggestions.isEmpty)
    }

    func testMaxOverlapStillCapsAtFour() {
        // Trigger ALL categories at once
        let message = """
        I refactored the function class struct and fixed the error bug issue.
        I created modified updated and wrote the plan step.
        ```code block```
        """
        let suggestions = FollowUpGenerator.generate(from: message, agentMode: .plan)
        XCTAssertLessThanOrEqual(suggestions.count, 2)
    }

    // MARK: - Case Insensitivity

    func testCaseInsensitiveErrorDetection() {
        let messages = [
            "There's an ERROR in the code.",
            "There's an Error in the code.",
            "There's an error in the code.",
            "There's an eRRoR in the code."
        ]
        for msg in messages {
            let suggestions = FollowUpGenerator.generate(from: msg, agentMode: .spec)
            XCTAssertTrue(
                suggestions.contains(where: { $0.label == "Show the fix" || $0.label == "Why did this happen?" }),
                "Failed case insensitivity for: \(msg)"
            )
        }
    }

    func testCaseInsensitiveCodeDetection() {
        let messages = [
            "I created a new FUNCTION here.",
            "Here is a Function for you.",
            "Built a new CLASS for the module.",
            "Added a Struct to handle data."
        ]
        for msg in messages {
            let suggestions = FollowUpGenerator.generate(from: msg, agentMode: .spec)
            XCTAssertTrue(
                suggestions.contains(where: { $0.label == "Write tests" }),
                "Failed case insensitivity for: \(msg)"
            )
        }
    }

    // MARK: - Refactoring Keywords

    func testRefactorKeyword() {
        let suggestions = FollowUpGenerator.generate(
            from: "I'll refactor this component to use protocol-oriented design.",
            agentMode: .spec
        )
        XCTAssertTrue(suggestions.contains(where: { $0.label == "Apply changes" }))
    }

    func testImproveKeyword() {
        let suggestions = FollowUpGenerator.generate(
            from: "Let me improve the performance of this algorithm.",
            agentMode: .spec
        )
        XCTAssertTrue(suggestions.contains(where: { $0.label == "Apply changes" }))
    }

    func testOptimizeKeyword() {
        let suggestions = FollowUpGenerator.generate(
            from: "We should optimize the database queries.",
            agentMode: .spec
        )
        XCTAssertTrue(suggestions.contains(where: { $0.label == "Apply changes" }))
    }

    // MARK: - Plan Mode + Content

    func testPlanModeWithCodeContent() {
        let message = """
        Here's my plan with a code example:
        ```swift
        let x = 1
        ```
        """
        let suggestions = FollowUpGenerator.generate(from: message, agentMode: .plan)
        // With cap at 2, both code and plan keywords trigger suggestions but only 2 survive
        XCTAssertEqual(suggestions.count, 2, "Should produce exactly 2 suggestions (capped)")
        // The first two suggestions should come from code detection (appended first)
        XCTAssertTrue(suggestions.contains(where: { $0.label == "Write tests" || $0.label == "Explain this code" }))
    }

    func testPlanKeywordInStandardMode() {
        let suggestions = FollowUpGenerator.generate(
            from: "Here is my plan for the feature.",
            agentMode: .spec
        )
        XCTAssertTrue(suggestions.contains(where: { $0.label == "Execute the plan" }))
    }

    func testStepKeywordTriggersPlanSuggestion() {
        let suggestions = FollowUpGenerator.generate(
            from: "Follow these steps to implement the feature.",
            agentMode: .spec
        )
        XCTAssertTrue(suggestions.contains(where: { $0.label == "Execute the plan" }))
    }

    // MARK: - All Categories Exercised

    func testExplainCategoryExists() {
        let suggestion = FollowUpSuggestion(
            label: "Test", prompt: "Test", icon: "star", category: .explain
        )
        XCTAssertEqual(suggestion.category, .explain)
    }

    func testExpandCategoryExists() {
        let suggestion = FollowUpSuggestion(
            label: "Test", prompt: "Test", icon: "star", category: .expand
        )
        XCTAssertEqual(suggestion.category, .expand)
    }

    func testFixCategoryExists() {
        let suggestion = FollowUpSuggestion(
            label: "Test", prompt: "Test", icon: "star", category: .fix
        )
        XCTAssertEqual(suggestion.category, .fix)
    }

    func testTestCategoryExists() {
        let suggestion = FollowUpSuggestion(
            label: "Test", prompt: "Test", icon: "star", category: .test
        )
        XCTAssertEqual(suggestion.category, .test)
    }

    func testRefactorCategoryExists() {
        let suggestion = FollowUpSuggestion(
            label: "Test", prompt: "Test", icon: "star", category: .refactor
        )
        XCTAssertEqual(suggestion.category, .refactor)
    }

    func testDeployCategoryExists() {
        let suggestion = FollowUpSuggestion(
            label: "Test", prompt: "Test", icon: "star", category: .deploy
        )
        XCTAssertEqual(suggestion.category, .deploy)
    }

    // MARK: - Fallback Behavior

    func testNoFallbackOnGenericMessages() {
        // A generic message with no keywords should get no suggestions (no fallback)
        let suggestions = FollowUpGenerator.generate(
            from: "Thanks, that's helpful!",
            agentMode: .spec
        )
        XCTAssertTrue(suggestions.isEmpty, "Generic messages should not produce suggestions")
    }

    func testCappedAtTwoWhenManySuggestions() {
        // A message triggering many keyword matches should still cap at 2
        let message = "I created a function that has an error."
        let suggestions = FollowUpGenerator.generate(from: message, agentMode: .spec)
        XCTAssertLessThanOrEqual(suggestions.count, 2)
    }

    // MARK: - Prompt Content Validation

    func testAllSuggestionsHaveNonEmptyPrompts() {
        let testMessages = [
            "Here's some ```code```",
            "There's an error here.",
            "I've updated the file.",
            "Let me refactor this.",
            "Here's the plan.",
            "Thanks!"
        ]
        for msg in testMessages {
            let suggestions = FollowUpGenerator.generate(from: msg, agentMode: .spec)
            for suggestion in suggestions {
                XCTAssertFalse(suggestion.prompt.isEmpty, "Suggestion '\(suggestion.label)' has empty prompt")
                XCTAssertFalse(suggestion.icon.isEmpty, "Suggestion '\(suggestion.label)' has empty icon")
                XCTAssertFalse(suggestion.label.isEmpty, "Suggestion has empty label")
            }
        }
    }

    // MARK: - File Modification Keywords

    func testCreatedKeyword() {
        let suggestions = FollowUpGenerator.generate(from: "I created the new module.", agentMode: .spec)
        XCTAssertTrue(suggestions.contains(where: { $0.label == "Run the build" || $0.label == "Review changes" }))
    }

    func testModifiedKeyword() {
        let suggestions = FollowUpGenerator.generate(from: "I modified the config file.", agentMode: .spec)
        XCTAssertTrue(suggestions.contains(where: { $0.label == "Run the build" || $0.label == "Review changes" }))
    }

    func testWroteKeyword() {
        let suggestions = FollowUpGenerator.generate(from: "I wrote the implementation.", agentMode: .spec)
        XCTAssertTrue(suggestions.contains(where: { $0.label == "Run the build" || $0.label == "Review changes" }))
    }

    // MARK: - Bug Keyword Variations

    func testBugKeyword() {
        let suggestions = FollowUpGenerator.generate(from: "Found a bug in the parser.", agentMode: .spec)
        XCTAssertTrue(suggestions.contains(where: { $0.category == .fix || $0.category == .explain }))
    }

    func testIssueKeyword() {
        let suggestions = FollowUpGenerator.generate(from: "There's an issue with the API.", agentMode: .spec)
        XCTAssertTrue(suggestions.contains(where: { $0.category == .fix || $0.category == .explain }))
    }

    func testFixKeyword() {
        let suggestions = FollowUpGenerator.generate(from: "Let me fix that problem.", agentMode: .spec)
        XCTAssertTrue(suggestions.contains(where: { $0.category == .fix || $0.category == .explain }))
    }

    // MARK: - AgentMode Variants

    func testAllAgentModesProduceSuggestions() {
        let message = "Here is some code: ```let x = 1```"
        for mode in AgentMode.allCases {
            let suggestions = FollowUpGenerator.generate(from: message, agentMode: mode)
            if mode == .fullStack {
                // Build mode suppresses all follow-ups
                XCTAssertTrue(suggestions.isEmpty, "Build mode should suppress suggestions")
            } else {
                XCTAssertFalse(suggestions.isEmpty, "No suggestions for mode \(mode.rawValue)")
            }
        }
    }
}
