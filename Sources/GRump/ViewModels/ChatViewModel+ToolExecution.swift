import Foundation
#if os(macOS)
import AppKit
import CoreGraphics
import ImageIO
import ScreenCaptureKit
#else
import UIKit
#endif
import UserNotifications

// MARK: - Tool Execution Extension
//
// Tool dispatch, parallel execution, retry logic, path resolution, and process execution.
// Individual execute* methods are in extension files:
// - ToolExec+FileOps.swift      (file read/write/edit, directory, search)
// - ToolExec+ShellSystem.swift   (shell, system, clipboard, screen)
// - ToolExec+GitDevOps.swift     (git, web, build, database, image, docker, IDE tools)
// - ToolExec+Utils.swift         (utilities: time, hash, base64, detect, etc.)

extension ChatViewModel {

    // MARK: - Parallel Tool Execution

    func executeToolCallsParallel(_ calls: [(id: String, name: String, args: String)]) async -> [String] {
        if calls.count == 1 {
            return [await executeToolCallWithRetry(name: calls[0].name, arguments: calls[0].args)]
        }

        return await withTaskGroup(of: (Int, String).self) { group in
            for (index, call) in calls.enumerated() {
                group.addTask {
                    let result = await self.executeToolCallWithRetry(name: call.name, arguments: call.args)
                    return (index, result)
                }
            }
            var results = Array(repeating: "", count: calls.count)
            for await (index, result) in group {
                results[index] = result
            }
            return results
        }
    }

    private func executeToolCallWithRetry(name: String, arguments: String) async -> String {
        let retryDelays: [UInt64] = [200_000_000, 500_000_000, 1_000_000_000] // 200ms, 500ms, 1s
        var lastResult = await executeToolCall(name: name, arguments: arguments)
        if !isTransientToolError(lastResult) {
            return lastResult
        }
        for delay in retryDelays.prefix(2) { // Up to 2 retries
            try? await Task.sleep(nanoseconds: delay)
            lastResult = await executeToolCall(name: name, arguments: arguments)
            if !isTransientToolError(lastResult) {
                return lastResult
            }
        }
        return lastResult
    }

    // MARK: - Tool Dispatch

    func executeToolCall(name: String, arguments: String) async -> String {
        guard let data = arguments.data(using: .utf8),
              let args = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "Error: could not parse tool arguments as JSON"
        }

        // Awareness: record tool usage (fail-soft).
        AwarenessMonitor.shared.record(tool: name)

        // Conscience gate: refuse mutating/sensitive tools before they run.
        if Self.mutatingToolNames.contains(name),
           let refusal = await conscienceRefusal(toolName: name, arguments: arguments) {
            return refusal
        }

        // Daemon approve-every-write: every autonomous mutating tool needs user approval.
        if isDaemonRunActive, Self.mutatingToolNames.contains(name) {
            let approved = await DaemonApprovalCoordinator.shared.requestApproval(action: "\(name): \(arguments.prefix(200))")
            if !approved {
                return "Autonomous action denied by user: \(name)"
            }
        }

        // Identity/skill files are protected even in normal runs: a generic file
        // write to SOUL.md, MIND.md, or a skills directory needs explicit
        // approval — record_lesson/propose_skill are the sanctioned paths.
        if !isDaemonRunActive,
           let target = Self.protectedWriteTarget(toolName: name, args: args, workingDirectory: workingDirectory) {
            let approved = await DaemonApprovalCoordinator.shared.requestApproval(
                action: "\(name) → protected file \(target)"
            )
            if !approved {
                return "Write to protected file denied: \(target). Use record_lesson or propose_skill for learned content, or edit it yourself in Settings."
            }
        }

        switch name {
        case "read_file":
            return executeReadFile(args)

        case "batch_read_files":
            return executeBatchReadFiles(args)

        case "create_file":
            return executeCreateFile(args)

        case "write_file":
            return executeWriteFile(args)

        case "edit_file":
            return executeEditFile(args)

        case "list_directory":
            return executeListDirectory(args)

        case "tree_view":
            return await executeTreeView(args)

        case "search_files":
            guard let directory = args["directory"] as? String,
                  let pattern = args["pattern"] as? String else {
                return "Error: missing directory or pattern"
            }
            let dir = resolvePath(directory)
            return await runProcess(executablePath: "/usr/bin/find", arguments: [dir, "-name", pattern, "-not", "-path", "*/.git/*", "-not", "-path", "*/node_modules/*"], cwd: nil, stdoutLimitLines: 100)

        case "grep_search":
            return await executeGrepSearch(args)

        case "find_and_replace":
            return await executeFindAndReplace(args)

        case "append_file":
            return executeAppendFile(args)

        case "create_directory":
            return executeCreateDirectory(args)

        case "compress_files":
            return await executeCompressFiles(args)

        case "extract_archive":
            return await executeExtractArchive(args)

        case "run_command":
            #if os(macOS)
            // Route through exec approval pipeline (same as system_run)
            return await executeSystemRun(args)
            #else
            return "run_command is only available on macOS."
            #endif

        case "run_background":
            return await executeRunBackground(args)

        case "kill_process":
            return await executeKillProcess(args)

        case "which":
            return await executeWhich(args)

        case "system_run":
            #if os(macOS)
            return await executeSystemRun(args)
            #else
            return "system_run is only available on macOS."
            #endif

        case "system_notify":
            return executeSystemNotify(args)

        case "clipboard_read":
            return executeClipboardRead()

        case "clipboard_write":
            return executeClipboardWrite(args)

        case "open_url":
            return executeOpenURL(args)

        case "open_app":
            return executeOpenApp(args)

        case "screen_snapshot":
            return await executeScreenSnapshot()

        case "screen_record":
            return executeScreenRecord(args)

        case "camera_snap":
            return executeCameraSnap()

        case "window_list":
            return executeWindowList()

        case "window_snapshot":
            return executeWindowSnapshot(args)

        case "delete_file":
            guard let path = args["path"] as? String else { return "Error: missing path" }
            let resolved = resolvePath(path)
            do {
                try FileManager.default.removeItem(atPath: resolved)
                return "Deleted: \(resolved)"
            } catch {
                return "Error deleting: \(error.localizedDescription)"
            }

        case "move_file":
            return executeMoveFile(args)

        case "copy_file":
            return executeCopyFile(args)

        case "file_info":
            return executeFileInfo(args)

        case "path_exists":
            return executePathExists(args)

        case "count_lines":
            return executeCountLines(args)

        case "get_env":
            return executeGetEnv(args)

        case "get_cwd":
            return executeGetCwd()

        case "list_env":
            return executeListEnv(args)

        case "list_processes":
            return await executeListProcesses(args)

        case "disk_usage":
            return await executeDiskUsage(args)

        case "run_build":
            return await executeRunBuild(args)

        case "run_linter":
            return await executeRunLinter(args)

        case "run_format":
            return await executeRunFormat(args)

        case "get_package_deps":
            return await executeGetPackageDeps(args)

        case "npm_install":
            return await executeNpmInstall(args)

        case "pip_install":
            return await executePipInstall(args)

        case "cargo_add":
            return await executeCargoAdd(args)

        case "git_log":
            return await executeGitLog(args)

        case "git_diff":
            return await executeGitDiff(args)

        case "git_branch":
            return await executeGitBranch(args)

        case "git_show":
            return await executeGitShow(args)

        case "git_add":
            return await executeGitAdd(args)

        case "git_commit":
            return await executeGitCommit(args)

        case "git_stash":
            return await executeGitStash(args)

        case "git_checkout":
            return await executeGitCheckout(args)

        case "git_push":
            return await executeGitPush(args)

        case "git_pull":
            return await executeGitPull(args)

        case "get_system_info":
            return executeGetSystemInfo()

        case "list_network_interfaces":
            return await executeListNetworkInterfaces()

        case "web_search":
            return await executeWebSearch(args)

        case "read_url":
            return await executeReadURL(args)

        case "fetch_json":
            return await executeFetchJson(args)

        case "download_file":
            return await executeDownloadFile(args)

        case "view_code_outline":
            guard let path = args["path"] as? String else { return "Error: missing path" }
            let resolved = resolvePath(path)
            let lang = (path as NSString).pathExtension.lowercased()
            let pattern: String
            switch lang {
            case "swift":
                pattern = "(func |class |struct |enum |protocol |extension |@objc|var |let |typealias |import )"
            case "py", "python":
                pattern = "(def |class |import |from |async def )"
            case "js", "ts", "jsx", "tsx":
                pattern = "(function |class |const |let |var |export |import |async |interface |type )"
            case "rs":
                pattern = "(fn |struct |enum |impl |trait |mod |use |pub )"
            case "go":
                pattern = "(func |type |package |import |interface )"
            case "java", "kt":
                pattern = "(class |interface |enum |void |public |private |protected |package |import )"
            default:
                pattern = "(func |class |struct |enum |protocol |extension |def |function |interface |type |import |export )"
            }
            return await runProcess(executablePath: "/usr/bin/grep", arguments: ["-n", "-E", pattern, resolved], cwd: nil, stdoutLimitLines: 120)

        case "git_status":
            return await executeGitStatus(args)

        case "run_tests":
            return await executeRunTests(args)

        case "sqlite_query":
            return await executeSqliteQuery(args)

        case "sqlite_schema":
            return await executeSqliteSchema(args)

        case "sqlite_tables":
            return await executeSqliteTables(args)

        case "image_info":
            return executeImageInfo(args)

        case "image_resize":
            return await executeImageResize(args)

        case "image_convert":
            return await executeImageConvert(args)

        case "http_request":
            return await executeHttpRequest(args)

        case "read_env_file":
            return executeReadEnvFile(args)

        case "write_env_file":
            return executeWriteEnvFile(args)

        case "docker_ps":
            return await executeDockerPs(args)

        case "docker_images":
            return await executeDockerImages(args)

        case "get_current_time":
            return executeGetCurrentTime()
        case "format_date":
            return executeFormatDate(args)
        case "calculate":
            return await executeCalculate(args)
        case "count_words":
            return executeCountWords(args)
        case "extract_urls":
            return executeExtractUrls(args)
        case "json_parse":
            return executeJsonParse(args)
        case "yaml_parse":
            return await executeYamlParse(args)
        case "diff_files":
            return await executeDiffFiles(args)
        case "file_hash":
            return await executeFileHash(args)
        case "backup_file":
            return executeBackupFile(args)
        case "git_remote":
            return await executeGitRemote(args)
        case "git_tag":
            return await executeGitTag(args)
        case "git_reset":
            return await executeGitReset(args)
        case "ping_host":
            return await executePingHost(args)
        case "resolve_dns":
            return await executeResolveDns(args)
        case "hash_string":
            return await executeHashString(args)
        case "base64_encode":
            return executeBase64Encode(args)
        case "base64_decode":
            return executeBase64Decode(args)
        case "generate_uuid":
            return executeGenerateUuid()
        case "get_file_type":
            return executeGetFileType(args)
        case "detect_language":
            return executeDetectLanguage(args)
        case "get_process_info":
            return await executeGetProcessInfo(args)

        // Swift IDE Intelligence Tools
        case "apple_docs_search":
            return await executeAppleDocsSearch(args)
        case "lsp_diagnostics":
            return executeLSPDiagnostics(args)
        case "accessibility_audit":
            return await executeAccessibilityAudit(args)
        case "localization_audit":
            return await executeLocalizationAudit(args)
        case "spm_resolve":
            return await executeSPMResolve(args)
        case "app_store_checklist":
            return await executeAppStoreChecklist(args)

        // Apple-Native Tools
        case "spotlight_search":
            return await executeSpotlightSearch(args)
        case "keychain_read":
            return executeKeychainRead(args)
        case "keychain_store":
            return executeKeychainStore(args)
        case "calendar_events":
            return await executeCalendarEvents(args)
        case "reminders_list":
            return await executeRemindersList(args)
        case "contacts_search":
            return executeContactsSearch(args)
        case "speech_transcribe":
            return await executeSpeechTranscribe(args)
        case "ocr_extract":
            return await executeOCRExtract(args)
        case "image_classify":
            return await executeImageClassify(args)
        case "shortcuts_run":
            return await executeShortcutsRun(args)
        case "system_appearance":
            return await executeSystemAppearance(args)
        case "xcodebuild":
            return await executeXcodebuild(args)
        case "xcrun_simctl":
            return await executeXcrunSimctl(args)
        case "record_lesson":
            return await executeRecordLesson(args)
        case "remember":
            return await executeRemember(args)
        case "reflect":
            return await executeReflect(args)
        case "propose_skill":
            return await executeProposeSkill(args)
        case "add_goal":
            return await executeAddGoal(args)
        case "swift_format":
            return await executeSwiftFormat(args)
        case "swift_lint":
            return await executeSwiftLint(args)
        case "swift_package":
            return await executeSwiftPackage(args)
        case "pdf_extract":
            return executePdfExtract(args)
        case "tts_speak":
            return await executeTtsSpeak(args)
        case "qr_generate":
            return executeQrGenerate(args)
        case "websocket_send":
            return await executeWebsocketSend(args)
        case "graphql_query":
            return await executeGraphqlQuery(args)
        case "bonjour_discover":
            return await executeBonjourDiscover(args)

        // Docker & Kubernetes
        case "docker_run":
            return await executeDockerRun(args)
        case "docker_build":
            return await executeDockerBuild(args)
        case "docker_logs":
            return await executeDockerLogs(args)
        case "docker_compose_up":
            return await executeDockerComposeUp(args)
        case "docker_compose_down":
            return await executeDockerComposeDown(args)
        case "kubectl_get":
            return await executeKubectlGet(args)
        case "kubectl_apply":
            return await executeKubectlApply(args)

        // Browser automation
        case "browser_open":
            return await executeBrowserOpen(args)
        case "browser_screenshot":
            return await executeBrowserScreenshot(args)
        case "browser_evaluate":
            return await executeBrowserEvaluate(args)

        // AI & Embeddings
        case "generate_embeddings":
            return await executeGenerateEmbeddings(args)
        case "semantic_search":
            return await executeSemanticSearchTool(args)
        case "summarize_text":
            return await executeSummarizeText(args)

        // Cloud Deploy
        case "vercel_deploy":
            return await executeVercelDeploy(args)
        case "vercel_logs":
            return await executeVercelLogs(args)
        case "netlify_deploy":
            return await executeNetlifyDeploy(args)
        case "fly_deploy":
            return await executeFlyDeploy(args)

        // Code Analysis
        case "regex_replace":
            return await executeRegexReplace(args)
        case "ast_parse":
            return await executeAstParse(args)
        case "find_references":
            return await executeFindReferences(args)
        case "type_check":
            return await executeTypeCheck(args)
        case "dependency_graph":
            return await executeDependencyGraph(args)
        case "code_complexity":
            return await executeCodeComplexity(args)

        // Network / Validation
        case "port_scan":
            return await executePortScan(args)
        case "ssl_check":
            return await executeSslCheck(args)
        case "cron_parse":
            return await executeCronParse(args)
        case "json_schema_validate":
            return await executeJsonSchemaValidate(args)

        // Interactive
        case "ask_user":
            return await executeAskUser(args)

        default:
            if name.hasPrefix("mcp_") {
                return await executeMCPToolCall(name: name, arguments: args)
            }
            return "Tool '\(name)' is not recognized. Use list_directory, read_file, edit_file, grep_search, run_command, web_search, or other available tools."
        }
    }

    private func executeMCPToolCall(name: String, arguments: [String: Any]) async -> String {
        let prefix = "mcp_"
        guard name.hasPrefix(prefix) else { return "Error: invalid MCP tool name" }
        let suffix = String(name.dropFirst(prefix.count))
        let parts = suffix.split(separator: "_", maxSplits: 1)
        guard parts.count >= 2 else { return "Error: MCP tool name must be mcp_<serverId>_<toolName>" }
        let serverId = String(parts[0])
        let configs = MCPServerConfigStorage.load().filter { $0.enabled && $0.id == serverId }
        guard let cfg = configs.first else { return "Error: MCP server '\(serverId)' not found or disabled" }
        return await MCPService.callTool(
            serverId: serverId,
            transport: cfg.transport,
            toolNameWithPrefix: name,
            arguments: arguments
        )
    }
}
