import XCTest
@testable import GRump

/// Tests for system prompt construction per agent mode.
/// Validates that `prependModeInstructions` produces the expected mode-specific
/// instructions for each `AgentMode`.
final class PromptBuildingTests: XCTestCase {

    // MARK: - Mode-Specific Instructions

    @MainActor
    func testPlanMode_containsPlanInstructions() {
        let vm = ChatViewModel()
        vm.agentMode = .plan
        let result = vm.prependModeInstructions(to: "BASE")
        XCTAssertTrue(result.contains("Plan"))
        XCTAssertTrue(result.hasSuffix("BASE"))
    }

    @MainActor
    func testFullStackMode_containsBuildInstructions() {
        let vm = ChatViewModel()
        vm.agentMode = .fullStack
        let result = vm.prependModeInstructions(to: "BASE")
        XCTAssertTrue(result.contains("Full Stack"))
        XCTAssertTrue(result.contains("IMMEDIATELY"))
    }

    @MainActor
    func testSpecMode_containsSpecInstructions() {
        let vm = ChatViewModel()
        vm.agentMode = .spec
        let result = vm.prependModeInstructions(to: "BASE")
        XCTAssertTrue(result.contains("spec") || result.contains("Spec"))
    }

    // MARK: - Base Prompt Preserved

    @MainActor
    func testModeInstructions_appendsBasePrompt() {
        let vm = ChatViewModel()
        let base = "You are a helpful assistant."
        for mode in AgentMode.allCases {
            vm.agentMode = mode
            let result = vm.prependModeInstructions(to: base)
            XCTAssertTrue(result.contains(base), "Mode \(mode) should contain the base prompt")
        }
    }

    // MARK: - Mode Instructions Are Non-Empty

    @MainActor
    func testAllModes_produceNonEmptyInstructions() {
        let vm = ChatViewModel()
        for mode in AgentMode.allCases {
            vm.agentMode = mode
            let result = vm.prependModeInstructions(to: "")
            XCTAssertFalse(result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                           "Mode \(mode) should produce non-empty instructions")
        }
    }

    // MARK: - File Extension Detection

    @MainActor
    func testDetectFileExtensions_emptyWorkingDirectory_returnsEmpty() {
        let vm = ChatViewModel()
        vm.workingDirectory = ""
        let extensions = vm.detectFileExtensions()
        XCTAssertTrue(extensions.isEmpty)
    }

    @MainActor
    func testDetectFileExtensions_invalidPath_returnsEmpty() {
        let vm = ChatViewModel()
        vm.workingDirectory = "/nonexistent/path/that/should/not/exist"
        let extensions = vm.detectFileExtensions()
        XCTAssertTrue(extensions.isEmpty)
    }

    @MainActor
    func testDetectFileExtensions_validDirectory_returnsExtensions() {
        let vm = ChatViewModel()
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        FileManager.default.createFile(atPath: tmpDir.appendingPathComponent("test.swift").path, contents: nil)
        FileManager.default.createFile(atPath: tmpDir.appendingPathComponent("readme.md").path, contents: nil)

        vm.workingDirectory = tmpDir.path
        let extensions = vm.detectFileExtensions()
        XCTAssertTrue(extensions.contains(".swift"))
        XCTAssertTrue(extensions.contains(".md"))
    }

    // MARK: - Developer Profile Layer

    @MainActor
    func testDeveloperProfileBlockSitsBeforeBasePrompt() {
        let vm = ChatViewModel()
        let profile = DeveloperProfile(preferredStack: "SwiftUI")
        let result = vm.prependDeveloperProfileContent(to: "BASE", profile: profile)
        let blockRange = result.range(of: "--- Developer Profile ---")
        let baseRange = result.range(of: "BASE")
        XCTAssertNotNil(blockRange)
        XCTAssertNotNil(baseRange)
        if let blockRange, let baseRange {
            XCTAssertTrue(blockRange.lowerBound < baseRange.lowerBound,
                          "profile block must precede the base prompt")
        }
    }

    @MainActor
    func testDeveloperProfileLayerComposesWithModeInstructions() {
        // [Mode][...][DevProfile][Base]: mode instructions must wrap outside the profile block.
        let vm = ChatViewModel()
        vm.agentMode = .plan
        let profile = DeveloperProfile(name: "James")
        let result = vm.prependModeInstructions(to: vm.prependDeveloperProfileContent(to: "BASE", profile: profile))
        let modeIdx = result.range(of: "Plan")?.lowerBound
        let profileIdx = result.range(of: "--- Developer Profile ---")?.lowerBound
        XCTAssertNotNil(modeIdx)
        XCTAssertNotNil(profileIdx)
        if let modeIdx, let profileIdx {
            XCTAssertTrue(modeIdx < profileIdx, "mode instructions must precede the profile block")
        }
        XCTAssertTrue(result.hasSuffix("BASE"))
    }
}
