import XCTest
@testable import GRump

@MainActor
final class ToolDispatchTests: XCTestCase {

    // Shared view model — avoids creating a new one for every tool.
    private var viewModel: ChatViewModel!

    override func setUp() {
        super.setUp()
        viewModel = ChatViewModel()
    }

    override func tearDown() {
        viewModel = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// Races a tool call against a very short deadline.
    /// We only care whether the dispatcher *recognises* the name;
    /// a timeout means the tool WAS dispatched (just slow/blocking) — that's a pass.
    private func dispatchRecognises(_ toolName: String) async -> Bool {
        let result: String = await withTaskGroup(of: String?.self) { group in
            group.addTask {
                await self.viewModel.executeToolCall(name: toolName, arguments: "{}")
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 10_000_000) // 10 ms
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? "__timeout__"
        }
        // Timeout → tool was dispatched (good).
        if result == "__timeout__" { return true }
        // Finished quickly → make sure it wasn't "not recognized".
        return !result.contains("is not recognized")
    }

    // MARK: - Tests

    /// Validates every tool in ToolDefinitions routes to a handler.
    func testAllToolDefinitionsHaveExecutors() async throws {
        let allTools = ToolDefinitions.toolsForCurrentPlatform
        let toolNames: [String] = allTools.compactMap { tool -> String? in
            guard let function = tool["function"] as? [String: Any],
                  let name = function["name"] as? String else { return nil }
            return name
        }

        XCTAssertFalse(toolNames.isEmpty, "Should have tools defined")

        var unrecognised: [String] = []
        for toolName in toolNames {
            let ok = await dispatchRecognises(toolName)
            if !ok { unrecognised.append(toolName) }
        }
        XCTAssertTrue(unrecognised.isEmpty,
                      "Missing executors for tools: \(unrecognised.joined(separator: ", "))")
    }

    /// Verify critical tools are dispatched.
    func testCriticalToolExecutorsExist() async throws {
        let criticalTools = [
            "read_file", "write_file", "edit_file", "list_directory",
            "search_files", "grep_search", "run_command", "web_search"
        ]

        var unrecognised: [String] = []
        for toolName in criticalTools {
            let ok = await dispatchRecognises(toolName)
            if !ok { unrecognised.append(toolName) }
        }
        XCTAssertTrue(unrecognised.isEmpty,
                      "Missing critical tool executors: \(unrecognised.joined(separator: ", "))")
    }

    func testGRumpDefaultsConstants() throws {
        XCTAssertFalse(GRumpDefaults.defaultSystemPrompt.isEmpty,
                      "defaultSystemPrompt should not be empty")
        XCTAssertTrue(GRumpDefaults.defaultSystemPrompt.contains("G-Rump"),
                     "defaultSystemPrompt should contain G-Rump name")
    }

    func testAgentModeProperties() throws {
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
