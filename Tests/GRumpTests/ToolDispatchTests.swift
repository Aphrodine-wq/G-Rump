import XCTest
@testable import GRump

@MainActor
final class ToolDispatchTests: XCTestCase {

    func testAllToolDefinitionsHaveExecutors() async throws {
        // Get all tool definitions
        let allTools = ToolDefinitions.toolsForCurrentPlatform
        let toolNames: [String] = allTools.compactMap { tool -> String? in
            guard let function = tool["function"] as? [String: Any],
                  let name = function["name"] as? String else { return nil }
            return name
        }

        XCTAssertFalse(toolNames.isEmpty, "Should have tools defined")

        // Verify each tool is recognized by the dispatcher (not "not recognized")
        let viewModel = ChatViewModel()
        for toolName in toolNames {
            let result = await viewModel.executeToolCall(name: toolName, arguments: "{}")
            XCTAssertFalse(result.contains("is not recognized"),
                          "Missing executor for tool: \(toolName)")
        }
    }

    func testCriticalToolExecutorsExist() async throws {
        let viewModel = ChatViewModel()

        // Test critical tools using their actual snake_case names from ToolDefinitions
        let criticalTools = [
            "read_file", "write_file", "edit_file", "list_directory",
            "search_files", "grep_search", "run_command", "web_search"
        ]

        for toolName in criticalTools {
            let result = await viewModel.executeToolCall(name: toolName, arguments: "{}")
            XCTAssertFalse(result.contains("is not recognized"),
                          "Missing critical tool executor: \(toolName)")
        }
    }

    func testGRumpDefaultsConstants() throws {
        // Test that GRumpDefaults contains expected constants
        XCTAssertFalse(GRumpDefaults.defaultSystemPrompt.isEmpty,
                      "defaultSystemPrompt should not be empty")
        XCTAssertTrue(GRumpDefaults.defaultSystemPrompt.contains("G-Rump"),
                     "defaultSystemPrompt should contain G-Rump name")
    }

    func testAgentModeProperties() throws {
        // Test that all AgentMode cases have required properties
        for mode in AgentMode.allCases {
            XCTAssertFalse(mode.displayName.isEmpty,
                          "\(mode) should have non-empty displayName")
            XCTAssertFalse(mode.icon.isEmpty,
                          "\(mode) should have non-empty icon")
            XCTAssertFalse(mode.description.isEmpty,
                          "\(mode) should have non-empty description")
            XCTAssertFalse(mode.toastMessage.isEmpty,
                          "\(mode) should have non-empty toastMessage")
        }
    }
}
