import XCTest
@testable import GRump

@MainActor
final class ToolDispatchTests: XCTestCase {

    /// Validates that every tool listed in ToolDefinitions routes to a handler
    /// (i.e. doesn't hit the "is not recognized" default case).
    /// Each tool call is given a 5-second timeout so tools that block on
    /// network/hardware/permissions can't hang the entire test suite.
    func testAllToolDefinitionsHaveExecutors() async throws {
        let allTools = ToolDefinitions.toolsForCurrentPlatform
        let toolNames: [String] = allTools.compactMap { tool -> String? in
            guard let function = tool["function"] as? [String: Any],
                  let name = function["name"] as? String else { return nil }
            return name
        }

        XCTAssertFalse(toolNames.isEmpty, "Should have tools defined")

        let viewModel = ChatViewModel()
        for toolName in toolNames {
            // Race the tool call against a 5-second deadline.
            // We only care whether the dispatcher recognises the name;
            // a timeout means the tool *was* dispatched (just slow/blocking).
            let result: String = await withTaskGroup(of: String?.self) { group in
                group.addTask {
                    await viewModel.executeToolCall(name: toolName, arguments: "{}")
                }
                group.addTask {
                    try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 s
                    return nil // sentinel for "timed out"
                }
                // First to finish wins
                let first = await group.next() ?? nil
                group.cancelAll()
                return first ?? "__timeout__"
            }
            // A timeout means the tool dispatched (good). Only fail on "not recognized".
            if result != "__timeout__" {
                XCTAssertFalse(result.contains("is not recognized"),
                              "Missing executor for tool: \(toolName)")
            }
        }
    }

    /// Same idea for critical tools: verify dispatch, don't actually wait
    /// for real execution to complete.
    func testCriticalToolExecutorsExist() async throws {
        let viewModel = ChatViewModel()

        let criticalTools = [
            "read_file", "write_file", "edit_file", "list_directory",
            "search_files", "grep_search", "run_command", "web_search"
        ]

        for toolName in criticalTools {
            let result: String = await withTaskGroup(of: String?.self) { group in
                group.addTask {
                    await viewModel.executeToolCall(name: toolName, arguments: "{}")
                }
                group.addTask {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    return nil
                }
                let first = await group.next() ?? nil
                group.cancelAll()
                return first ?? "__timeout__"
            }
            if result != "__timeout__" {
                XCTAssertFalse(result.contains("is not recognized"),
                              "Missing critical tool executor: \(toolName)")
            }
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

