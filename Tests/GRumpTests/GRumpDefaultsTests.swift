import XCTest
@testable import GRump

final class GRumpDefaultsTests: XCTestCase {

    // MARK: - System Prompt

    func testDefaultSystemPromptNotEmpty() {
        XCTAssertFalse(GRumpDefaults.defaultSystemPrompt.isEmpty)
    }

    func testDefaultSystemPromptContainsBrandName() {
        XCTAssertTrue(GRumpDefaults.defaultSystemPrompt.contains("G-Rump"))
    }

    func testDefaultSystemPromptContainsCoreGuidance() {
        let prompt = GRumpDefaults.defaultSystemPrompt
        XCTAssertTrue(prompt.contains("Inspect before modifying"), "Missing inspection guidance")
        XCTAssertTrue(prompt.contains("Minimal, surgical changes"), "Missing minimal changes guidance")
        XCTAssertTrue(prompt.contains("Verify your work"), "Missing verification guidance")
        XCTAssertTrue(prompt.contains("Recover from errors"), "Missing error recovery guidance")
        XCTAssertTrue(prompt.contains("Think step by step"), "Missing step-by-step guidance")
    }

    func testDefaultSystemPromptContainsToolGuidance() {
        let prompt = GRumpDefaults.defaultSystemPrompt
        XCTAssertTrue(prompt.contains("tree_view"))
        XCTAssertTrue(prompt.contains("grep_search"))
        XCTAssertTrue(prompt.contains("read_file"))
        XCTAssertTrue(prompt.contains("edit_file"))
        XCTAssertTrue(prompt.contains("run_command"))
        XCTAssertTrue(prompt.contains("web_search"))
    }

    func testDefaultSystemPromptContainsCodeQualityStandards() {
        let prompt = GRumpDefaults.defaultSystemPrompt
        XCTAssertTrue(prompt.contains("Code Quality Standards"))
        XCTAssertTrue(prompt.contains("error handling"))
    }

    func testDefaultSystemPromptContainsCommunicationStyle() {
        let prompt = GRumpDefaults.defaultSystemPrompt
        XCTAssertTrue(prompt.contains("Communication Style"))
        XCTAssertTrue(prompt.contains("direct and concise"))
        XCTAssertTrue(prompt.contains("Lead with the answer"), "Missing lead-with-outcome guidance")
        XCTAssertTrue(prompt.contains("Match the response to the question"), "Missing length-calibration guidance")
        XCTAssertTrue(prompt.contains("Report outcomes faithfully"), "Missing honest-reporting guidance")
        XCTAssertTrue(prompt.contains("language tag"), "Missing code fence guidance")
    }

    func testDefaultSystemPromptContainsAnsweringVsActing() {
        let prompt = GRumpDefaults.defaultSystemPrompt
        XCTAssertTrue(prompt.contains("Answering vs. Acting"), "Missing answering-vs-acting contract")
        XCTAssertTrue(prompt.contains("the deliverable is the answer"), "Questions must be answered, not acted on")
        XCTAssertTrue(prompt.contains("apply it only when asked"), "Reported problems must not trigger unasked fixes")
    }

    func testDefaultSystemPromptContainsWorkingDirectoryGuidance() {
        let prompt = GRumpDefaults.defaultSystemPrompt
        XCTAssertTrue(prompt.contains("Working Directory"))
    }

    func testDefaultSystemPromptReasonableLength() {
        let prompt = GRumpDefaults.defaultSystemPrompt
        // Should be substantial but not absurdly long
        XCTAssertGreaterThan(prompt.count, 500, "System prompt too short")
        XCTAssertLessThan(prompt.count, 10000, "System prompt too long")
    }
}
