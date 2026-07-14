import XCTest
@testable import GRump

final class ToolDefinitionsTests: XCTestCase {

    func testToolsForCurrentPlatformNotEmpty() {
        let tools = ToolDefinitions.toolsForCurrentPlatform
        XCTAssertFalse(tools.isEmpty, "Should have at least one tool defined")
    }

    func testAllToolsHaveRequiredFields() {
        let tools = ToolDefinitions.toolsForCurrentPlatform
        for tool in tools {
            XCTAssertEqual(tool["type"] as? String, "function", "Tool must have type 'function'")
            let function = tool["function"] as? [String: Any]
            XCTAssertNotNil(function, "Tool must have 'function' key")
            let name = function?["name"] as? String
            XCTAssertNotNil(name, "Tool function must have 'name'")
            XCTAssertFalse(name?.isEmpty ?? true, "Tool name must not be empty")
            let description = function?["description"] as? String
            XCTAssertNotNil(description, "Tool '\(name ?? "?")' must have 'description'")
            XCTAssertFalse(description?.isEmpty ?? true, "Tool '\(name ?? "?")' description must not be empty")
        }
    }

    func testToolNamesAreUnique() {
        let tools = ToolDefinitions.toolsForCurrentPlatform
        let names = tools.compactMap { ($0["function"] as? [String: Any])?["name"] as? String }
        let uniqueNames = Set(names)
        XCTAssertEqual(names.count, uniqueNames.count, "Tool names must be unique, found duplicates: \(names.filter { name in names.filter { $0 == name }.count > 1 })")
    }

    func testCriticalToolsExist() {
        let tools = ToolDefinitions.toolsForCurrentPlatform
        let names = Set(tools.compactMap { ($0["function"] as? [String: Any])?["name"] as? String })
        let required = ["read_file", "write_file", "edit_file", "list_directory", "run_command", "search_files", "grep_search", "web_search"]
        for toolName in required {
            XCTAssertTrue(names.contains(toolName), "Critical tool '\(toolName)' must exist")
        }
    }

    func testToolsFilteredWithDenylist() {
        let allTools = ToolDefinitions.toolsFiltered(allowlist: nil, userDenylist: [])
        let filtered = ToolDefinitions.toolsFiltered(allowlist: nil, userDenylist: ["read_file", "write_file"])
        XCTAssertLessThan(filtered.count, allTools.count, "Denylist should reduce tool count")
        let filteredNames = Set(filtered.compactMap { ($0["function"] as? [String: Any])?["name"] as? String })
        XCTAssertFalse(filteredNames.contains("read_file"))
        XCTAssertFalse(filteredNames.contains("write_file"))
    }

    // MARK: - Expanded Tests

    func testToolCountRegression() {
        let tools = ToolDefinitions.toolsForCurrentPlatform
        XCTAssertGreaterThanOrEqual(tools.count, 50,
            "Should have at least 50 tools defined")
    }

    func testAllToolsHaveParametersSchema() {
        let tools = ToolDefinitions.toolsForCurrentPlatform
        for tool in tools {
            let function = tool["function"] as? [String: Any]
            let name = function?["name"] as? String ?? "?"
            let parameters = function?["parameters"] as? [String: Any]
            XCTAssertNotNil(parameters, "Tool '\(name)' should have parameters schema")
            if let params = parameters {
                XCTAssertEqual(params["type"] as? String, "object",
                    "Tool '\(name)' parameters type should be 'object'")
            }
        }
    }

    func testToolDescriptionsAreNonTrivial() {
        let tools = ToolDefinitions.toolsForCurrentPlatform
        for tool in tools {
            let function = tool["function"] as? [String: Any]
            let name = function?["name"] as? String ?? "?"
            let description = function?["description"] as? String ?? ""
            XCTAssertGreaterThan(description.count, 10,
                "Tool '\(name)' description should be substantive (> 10 chars)")
        }
    }

    func testToolNamesUseSnakeCase() {
        let tools = ToolDefinitions.toolsForCurrentPlatform
        let names = tools.compactMap { ($0["function"] as? [String: Any])?["name"] as? String }
        for name in names {
            XCTAssertFalse(name.contains(" "), "Tool name '\(name)' should not contain spaces")
            XCTAssertEqual(name, name.lowercased(), "Tool name '\(name)' should be lowercase snake_case")
        }
    }

    func testToolsFilteredWithAllowlist() {
        let allowlist: [String] = ["read_file", "write_file", "run_command"]
        let filtered = ToolDefinitions.toolsFiltered(allowlist: allowlist, userDenylist: [])
        let filteredNames = Set(filtered.compactMap { ($0["function"] as? [String: Any])?["name"] as? String })
        XCTAssertEqual(filteredNames.count, 3)
        XCTAssertTrue(filteredNames.contains("read_file"))
        XCTAssertTrue(filteredNames.contains("write_file"))
        XCTAssertTrue(filteredNames.contains("run_command"))
    }

    func testToolsFilteredEmptyDenylist() {
        let all = ToolDefinitions.toolsFiltered(allowlist: nil, userDenylist: [])
        let platform = ToolDefinitions.toolsForCurrentPlatform
        XCTAssertEqual(all.count, platform.count,
            "Empty denylist should return all tools")
    }

    func testToolsFilteredDenylistOverridesAllowlist() {
        let allowlist: [String] = ["read_file", "write_file"]
        let filtered = ToolDefinitions.toolsFiltered(allowlist: allowlist, userDenylist: ["write_file"])
        let names = Set(filtered.compactMap { ($0["function"] as? [String: Any])?["name"] as? String })
        XCTAssertTrue(names.contains("read_file"))
        XCTAssertFalse(names.contains("write_file"),
            "Denylist should override allowlist")
    }

    func testFileToolsExist() {
        let tools = ToolDefinitions.toolsForCurrentPlatform
        let names = Set(tools.compactMap { ($0["function"] as? [String: Any])?["name"] as? String })
        let fileTools = ["read_file", "write_file", "edit_file", "create_file",
                         "delete_file", "move_file", "copy_file", "list_directory"]
        for tool in fileTools {
            XCTAssertTrue(names.contains(tool), "File tool '\(tool)' should exist")
        }
    }

    func testGitToolsExist() {
        let tools = ToolDefinitions.toolsForCurrentPlatform
        let names = Set(tools.compactMap { ($0["function"] as? [String: Any])?["name"] as? String })
        let gitTools = ["git_status", "git_log", "git_diff", "git_commit", "git_add"]
        for tool in gitTools {
            XCTAssertTrue(names.contains(tool), "Git tool '\(tool)' should exist")
        }
    }

    func testNetworkToolsExist() {
        let tools = ToolDefinitions.toolsForCurrentPlatform
        let names = Set(tools.compactMap { ($0["function"] as? [String: Any])?["name"] as? String })
        let netTools = ["web_search", "read_url", "fetch_json"]
        for tool in netTools {
            XCTAssertTrue(names.contains(tool), "Network tool '\(tool)' should exist")
        }
    }

    // Guards the `--dump-tools` payload consumed by scripts/agent-eval.mjs.
    func testToolsJSONDataIsValidAndContainsCoreTools() throws {
        let data = try ToolDefinitions.toolsJSONData()
        let decoded = try JSONSerialization.jsonObject(with: data)
        guard let array = decoded as? [[String: Any]] else {
            XCTFail("toolsJSONData should decode to an array of tool dicts")
            return
        }
        let names = Set(array.compactMap { ($0["function"] as? [String: Any])?["name"] as? String })
        XCTAssertTrue(names.contains("edit_file"), "dump payload must include edit_file")
        XCTAssertTrue(names.contains("run_build"), "dump payload must include run_build")
        XCTAssertGreaterThan(names.count, 100, "dump payload should carry the full tool registry")
    }
}
