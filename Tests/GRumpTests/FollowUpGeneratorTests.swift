import XCTest
@testable import GRump

final class FollowUpGeneratorTests: XCTestCase {

    // MARK: - Code Detection

    func testGeneratesSuggestionsForCodeContent() {
        let message = "Here's the code:\n```swift\nfunc hello() { }\n```"
        let suggestions = FollowUpGenerator.generate(from: message, agentMode: .spec)
        XCTAssertFalse(suggestions.isEmpty)
        XCTAssertTrue(suggestions.contains(where: { $0.label == "Write tests" }))
    }

    func testGeneratesSuggestionsForFunctionMention() {
        let message = "I've created a new function that handles authentication."
        let suggestions = FollowUpGenerator.generate(from: message, agentMode: .spec)
        XCTAssertTrue(suggestions.contains(where: { $0.label == "Write tests" }))
    }

    // MARK: - Error Detection

    func testGeneratesSuggestionsForErrors() {
        let message = "There's an error in the file: missing semicolon on line 42."
        let suggestions = FollowUpGenerator.generate(from: message, agentMode: .spec)
        XCTAssertTrue(suggestions.contains(where: { $0.label == "Show the fix" }))
    }

    func testGeneratesSuggestionsForBugMention() {
        let message = "I found a bug in the login flow."
        let suggestions = FollowUpGenerator.generate(from: message, agentMode: .spec)
        XCTAssertTrue(suggestions.contains(where: { $0.label == "Show the fix" || $0.label == "Why did this happen?" }))
    }

    // MARK: - File Modification Detection

    func testGeneratesSuggestionsForFileModifications() {
        let message = "I've updated the configuration file with the new settings."
        let suggestions = FollowUpGenerator.generate(from: message, agentMode: .spec)
        XCTAssertTrue(suggestions.contains(where: { $0.label == "Run the build" || $0.label == "Review changes" }))
    }

    // MARK: - Plan Mode

    func testGeneratesPlanModeSuggestions() {
        let message = "Here's my plan for implementing the feature."
        let suggestions = FollowUpGenerator.generate(from: message, agentMode: .plan)
        XCTAssertTrue(suggestions.contains(where: { $0.label == "Execute the plan" }))
    }

    // MARK: - Cap

    func testCapsAtTwoSuggestions() {
        let message = "I created a function that has an error and wrote a file with a plan to fix the bug."
        let suggestions = FollowUpGenerator.generate(from: message, agentMode: .plan)
        XCTAssertLessThanOrEqual(suggestions.count, 2)
    }

    // MARK: - Fallback

    func testPlainMessageGeneratesNoSuggestions() {
        let message = "Done."
        let suggestions = FollowUpGenerator.generate(from: message, agentMode: .spec)
        XCTAssertTrue(suggestions.isEmpty, "Plain messages should not generate fallback suggestions")
    }

    // MARK: - Suggestion Properties

    func testSuggestionHasRequiredFields() {
        let message = "```swift\nlet x = 1\n```"
        let suggestions = FollowUpGenerator.generate(from: message, agentMode: .spec)
        for suggestion in suggestions {
            XCTAssertFalse(suggestion.label.isEmpty)
            XCTAssertFalse(suggestion.prompt.isEmpty)
            XCTAssertFalse(suggestion.icon.isEmpty)
        }
    }

    func testSuggestionIsIdentifiable() {
        let s1 = FollowUpSuggestion(label: "A", prompt: "B", icon: "star", category: .explain)
        let s2 = FollowUpSuggestion(label: "A", prompt: "B", icon: "star", category: .explain)
        XCTAssertNotEqual(s1.id, s2.id, "Each suggestion should have a unique ID")
    }

    // MARK: - Refactoring Keywords

    func testRefactoringKeywordsGenerateSuggestions() {
        for keyword in ["refactor", "improve", "optimize"] {
            let message = "Let me \(keyword) the code."
            let suggestions = FollowUpGenerator.generate(from: message, agentMode: .spec)
            XCTAssertTrue(suggestions.contains(where: { $0.label == "Apply changes" }),
                "Keyword '\(keyword)' should trigger 'Apply changes'")
        }
    }

    // MARK: - Class / Struct Detection

    func testClassKeywordDetected() {
        let message = "I created a new class to handle authentication."
        let suggestions = FollowUpGenerator.generate(from: message, agentMode: .spec)
        XCTAssertTrue(suggestions.contains(where: { $0.label == "Write tests" }),
            "'class' keyword should trigger code suggestions")
    }

    func testStructKeywordDetected() {
        let message = "I defined a struct for the data model."
        let suggestions = FollowUpGenerator.generate(from: message, agentMode: .spec)
        XCTAssertTrue(suggestions.contains(where: { $0.label == "Write tests" }),
            "'struct' keyword should trigger code suggestions")
    }
}
