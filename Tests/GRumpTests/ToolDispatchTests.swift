import XCTest
@testable import GRump

@MainActor
final class ToolDispatchTests: XCTestCase {

    // MARK: - Known tool registry
    // All tool names from ChatViewModel.executeToolCall switch.
    // If you add a new tool, add its name here too.
    private static let knownToolNames: Set<String> = [
        "read_file", "batch_read_files", "create_file", "write_file",
        "edit_file", "list_directory", "tree_view", "search_files",
        "grep_search", "find_and_replace", "append_file", "create_directory",
        "compress_files", "extract_archive", "run_command", "run_background",
        "kill_process", "which", "system_run", "system_notify",
        "clipboard_read", "clipboard_write", "open_url", "open_app",
        "screen_snapshot", "screen_record", "camera_snap", "window_list",
        "window_snapshot", "delete_file", "move_file", "copy_file",
        "file_info", "path_exists", "count_lines", "get_env", "get_cwd",
        "list_env", "list_processes", "disk_usage", "run_build", "run_linter",
        "run_format", "get_package_deps", "npm_install", "pip_install",
        "cargo_add", "git_log", "git_diff", "git_branch", "git_show",
        "git_add", "git_commit", "git_stash", "git_checkout", "git_push",
        "git_pull", "get_system_info", "list_network_interfaces",
        "web_search", "read_url", "fetch_json", "download_file",
        "view_code_outline", "git_status", "run_tests", "sqlite_query",
        "sqlite_schema", "sqlite_tables", "image_info", "image_resize",
        "image_convert", "http_request", "read_env_file", "write_env_file",
        "docker_ps", "docker_images", "get_current_time", "format_date",
        "calculate", "count_words", "extract_urls", "json_parse",
        "yaml_parse", "diff_files", "file_hash", "backup_file",
        "git_remote", "git_tag", "git_reset", "ping_host", "resolve_dns",
        "hash_string", "base64_encode", "base64_decode", "generate_uuid",
        "get_file_type", "detect_language", "get_process_info",
        // Swift IDE Intelligence Tools
        "apple_docs_search", "lsp_diagnostics", "accessibility_audit",
        "localization_audit", "spm_resolve", "app_store_checklist",
        // Apple-Native Tools
        "spotlight_search", "keychain_read", "keychain_store",
        "calendar_events", "reminders_list", "contacts_search",
        "speech_transcribe", "ocr_extract", "image_classify",
        "shortcuts_run", "system_appearance", "xcodebuild",
        "xcrun_simctl", "swift_format", "swift_lint", "swift_package",
        "pdf_extract", "tts_speak", "qr_generate", "websocket_send",
        "graphql_query", "bonjour_discover",
        // Docker & K8s
        "docker_run", "docker_build", "docker_logs",
        "docker_compose_up", "docker_compose_down",
        "kubectl_get", "kubectl_apply",
        // Browser tools
        "browser_open", "browser_screenshot", "browser_evaluate",
        // AI / NLP tools
        "generate_embeddings", "semantic_search", "summarize_text",
        // Deploy tools
        "vercel_deploy", "vercel_logs", "netlify_deploy", "fly_deploy",
        // Code analysis tools
        "regex_replace", "ast_parse", "find_references", "type_check",
        "dependency_graph", "code_complexity",
        // Network / validation tools
        "port_scan", "ssl_check", "cron_parse", "json_schema_validate",
        // Interactive
        "ask_user",
        // Learning loop
        "record_lesson", "remember", "reflect", "propose_skill", "add_goal",
    ]

    // MARK: - Tests

    /// Every tool declared in ToolDefinitions must have a corresponding
    /// handler in executeToolCall (i.e. exist in knownToolNames).
    func testAllToolDefinitionsHaveExecutors() throws {
        let allTools = ToolDefinitions.toolsForCurrentPlatform
        let toolNames: [String] = allTools.compactMap { tool -> String? in
            guard let function = tool["function"] as? [String: Any],
                  let name = function["name"] as? String else { return nil }
            return name
        }

        XCTAssertFalse(toolNames.isEmpty, "Should have tools defined")

        var missing: [String] = []
        for name in toolNames {
            if !Self.knownToolNames.contains(name) && !name.hasPrefix("mcp_") {
                missing.append(name)
            }
        }
        XCTAssertTrue(missing.isEmpty,
                      "Tools declared in ToolDefinitions but missing from executeToolCall: \(missing.joined(separator: ", "))")
    }

    /// Verify critical tools are in the known registry.
    func testCriticalToolExecutorsExist() throws {
        let criticalTools = [
            "read_file", "write_file", "edit_file", "list_directory",
            "search_files", "grep_search", "run_command", "web_search"
        ]

        var missing: [String] = []
        for toolName in criticalTools {
            if !Self.knownToolNames.contains(toolName) {
                missing.append(toolName)
            }
        }
        XCTAssertTrue(missing.isEmpty,
                      "Missing critical tool executors: \(missing.joined(separator: ", "))")
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
