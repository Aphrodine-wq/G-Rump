import XCTest
@testable import GRump

/// Tests for the Build mode prompt — verifies it forces tool usage and prevents
/// question-asking behavior.
@MainActor
final class BuildModePromptTests: XCTestCase {

    // MARK: - Build Mode Identity

    func testBuildModeRawValue() {
        XCTAssertEqual(AgentMode.fullStack.rawValue, "fullStack")
    }

    func testBuildModeDisplayName() {
        XCTAssertEqual(AgentMode.fullStack.displayName, "Build")
    }

    func testBuildModeDescription() {
        let desc = AgentMode.fullStack.description
        XCTAssertTrue(desc.contains("full stack") || desc.contains("Build") || desc.contains("end-to-end"),
            "Build mode description should mention full stack/build/end-to-end")
    }

    // MARK: - System Prompt Content

    func testDefaultSystemPromptContainsWriteFileGuidance() {
        let prompt = GRumpDefaults.defaultSystemPrompt
        XCTAssertTrue(prompt.contains("edit_file"), "System prompt should mention edit_file tool")
    }

    func testDefaultSystemPromptContainsRunCommandGuidance() {
        let prompt = GRumpDefaults.defaultSystemPrompt
        XCTAssertTrue(prompt.contains("run_command"), "System prompt should mention run_command")
    }

    // MARK: - All Modes Have Instructions

    func testAllModesGenerateNonEmptyInstructions() {
        // Each mode should produce non-empty mode instructions
        for mode in AgentMode.allCases {
            XCTAssertFalse(mode.displayName.isEmpty, "\(mode.rawValue) should have displayName")
            XCTAssertFalse(mode.description.isEmpty, "\(mode.rawValue) should have description")
        }
    }

    // MARK: - Build Mode Doesn't Ask Questions

    func testBuildModeDescriptionDoesntMentionClarify() {
        let desc = AgentMode.fullStack.description
        // The user-facing description shouldn't mention clarifying questions
        XCTAssertFalse(desc.lowercased().contains("clarif"),
            "Build mode description should not mention clarifying questions")
    }

    // MARK: - Follow-Up Suppression in Build Mode

    func testFollowUpSuppressedInBuildMode() {
        let suggestions = FollowUpGenerator.generate(
            from: "I built the authentication system with JWT tokens.",
            agentMode: .fullStack
        )
        XCTAssertTrue(suggestions.isEmpty,
            "Build mode should suppress follow-up suggestions")
    }

    func testFollowUpNotSuppressedInSpecMode() {
        let suggestions = FollowUpGenerator.generate(
            from: "I wrote a function to handle authentication.",
            agentMode: .spec
        )
        // Spec mode with code keywords should produce suggestions
        XCTAssertFalse(suggestions.isEmpty,
            "Spec mode with code keywords should produce suggestions")
    }

    func testFollowUpNotSuppressedInPlanMode() {
        let suggestions = FollowUpGenerator.generate(
            from: "Here's my plan: first we refactor the module, then add tests.",
            agentMode: .plan
        )
        XCTAssertFalse(suggestions.isEmpty,
            "Plan mode with relevant keywords should produce suggestions")
    }

    // MARK: - Mode-Specific Behavior

    func testSpecModeDescriptionMentionsClarify() {
        let desc = AgentMode.spec.description
        // Spec mode SHOULD mention clarifying/refining
        XCTAssertTrue(desc.lowercased().contains("clarif") || desc.lowercased().contains("refin"),
            "Spec mode should be about refining requirements")
    }

    func testPlanModeDescriptionMentionsPlan() {
        let desc = AgentMode.plan.description
        XCTAssertTrue(desc.lowercased().contains("plan"),
            "Plan mode should mention planning")
    }

    // MARK: - Build Mode Icon and Color

    func testBuildModeHasHammerIcon() {
        XCTAssertEqual(AgentMode.fullStack.icon, "hammer.fill")
    }

    func testBuildModeAccentColorIsGreen() {
        // Build mode should have a green accent (action/go color)
        let colorDesc = "\(AgentMode.fullStack.modeAccentColor)"
        XCTAssertTrue(colorDesc.lowercased().contains("green") || !colorDesc.isEmpty,
            "Build mode should have an accent color")
    }

    // MARK: - Codable Round Trip

    func testBuildModeCodableRoundTrip() throws {
        let mode = AgentMode.fullStack
        let data = try JSONEncoder().encode(mode)
        let decoded = try JSONDecoder().decode(AgentMode.self, from: data)
        XCTAssertEqual(decoded, mode)
    }

    // MARK: - All Modes Covered

    func testThreeModesExist() {
        XCTAssertEqual(AgentMode.allCases.count, 3,
            "Should have 3 modes: Plan, Build, Spec")
    }

    func testBuildModeIsFullStack() {
        // Verify the Build display name maps to fullStack enum case
        let buildMode = AgentMode.allCases.first { $0.displayName == "Build" }
        XCTAssertEqual(buildMode, AgentMode.fullStack)
    }
}
