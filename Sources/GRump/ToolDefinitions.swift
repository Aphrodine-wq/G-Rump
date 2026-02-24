import Foundation
#if os(iOS)
import UIKit
#endif

struct ToolDefinitions {

    /// Tools that are only available on macOS (filtered out on iOS).
    private static let macOSOnlyTools: Set<String> = [
        "system_run", "run_background", "kill_process", "which",
        "screen_record", "window_list", "window_snapshot",
        "docker_ps", "docker_images"
    ]

    /// Tools available on the current platform.
    static var toolsForCurrentPlatform: [[String: Any]] {
        #if os(iOS)
        return allTools.filter { tool in
            guard let fn = tool["function"] as? [String: Any],
                  let name = fn["name"] as? String else { return true }
            return !macOSOnlyTools.contains(name)
        }
        #else
        return allTools
        #endif
    }

    static let allTools: [[String: Any]] = [
        // File operations
        readFile,
        batchReadFiles,
        writeFile,
        editFile,
        createFile,
        deleteFile,
        moveFile,
        copyFile,
        fileInfo,
        pathExists,
        countLines,
        listDirectory,
        treeView,
        searchFiles,
        grepSearch,
        findAndReplace,
        appendFile,
        createDirectory,
        compressFiles,
        extractArchive,
        // Shell & system
        runCommand,
        runBackground,
        killProcess,
        which,
        systemRun,
        systemNotify,
        getEnv,
        getCwd,
        listEnv,
        listProcesses,
        diskUsage,
        // Clipboard & open
        clipboardRead,
        clipboardWrite,
        openURL,
        openApp,
        // Screen & camera (macOS)
        screenSnapshot,
        screenRecord,
        cameraSnap,
        windowList,
        windowSnapshot,
        // Web
        webSearch,
        readURL,
        fetchJson,
        downloadFile,
        // Code intelligence & quality
        viewCodeOutline,
        runBuild,
        runFormat,
        getPackageDeps,
        npmInstall,
        pipInstall,
        cargoAdd,
        runLinter,
        runTests,
        // Git
        gitStatus,
        gitLog,
        gitDiff,
        gitBranch,
        gitShow,
        gitAdd,
        gitCommit,
        gitStash,
        gitCheckout,
        gitPush,
        gitPull,
        getSystemInfo,
        listNetworkInterfaces,
        // Database
        sqliteQuery,
        sqliteSchema,
        sqliteTables,
        // Image
        imageInfo,
        imageResize,
        imageConvert,
        // API & DevOps
        httpRequest,
        readEnvFile,
        writeEnvFile,
        dockerPs,
        dockerImages,
        // Utilities
        getCurrentTime,
        formatDate,
        calculate,
        countWords,
        extractUrls,
        jsonParse,
        yamlParse,
        diffFiles,
        fileHash,
        backupFile,
        gitRemote,
        gitTag,
        gitReset,
        pingHost,
        resolveDns,
        hashString,
        base64Encode,
        base64Decode,
        generateUuid,
        getFileType,
        detectLanguage,
        getProcessInfo,
        // Docker & Kubernetes
        dockerRun,
        dockerBuild,
        dockerLogs,
        dockerComposeUp,
        dockerComposeDown,
        kubectlGet,
        kubectlApply,
        // Browser automation
        browserOpen,
        browserScreenshot,
        browserEvaluate,
        // AI & Embeddings
        generateEmbeddings,
        semanticSearch,
        summarizeText,
        // Cloud deployment
        vercelDeploy,
        vercelLogs,
        netlifyDeploy,
        flyDeploy,
        // Additional utilities
        regexReplace,
        portScan,
        sslCheck,
        cronParse,
        jsonSchemaValidate,
        // Code intelligence
        astParse,
        findReferences,
        typeCheck,
        dependencyGraph,
        codeComplexity,
        // Apple-native (macOS frameworks)
        spotlightSearch,
        keychainRead,
        keychainStore,
        calendarEvents,
        remindersList,
        contactsSearch,
        speechTranscribe,
        ocrExtract,
        imageClassify,
        shortcutsRun,
        systemAppearance,
        // Advanced code (Apple toolchain)
        xcodebuildTool,
        xcrunSimctl,
        swiftFormatTool,
        swiftLintTool,
        swiftPackageTool,
        // Media
        pdfExtract,
        ttsSpeak,
        qrGenerate,
        // Network
        websocketSend,
        graphqlQuery,
        bonjourDiscover,
        // Swift IDE Intelligence
        appleDocsSearch,
        lspDiagnostics,
        accessibilityAudit,
        localizationAudit,
        spmResolve,
        appStoreChecklist,
        // User interaction
        askUser
    ]

    // Individual tool schema definitions are in extension files:
    // - ToolDefs+FileOps.swift      (file operations, directory, search)
    // - ToolDefs+ShellSystem.swift   (shell, system, clipboard, screen)
    // - ToolDefs+GitDevOps.swift     (git, web, code intel, build, docker, browser, cloud, AI)
    // - ToolDefs+UtilsApple.swift    (utilities, Apple-native, media, network, IDE tools)

    static func toolsJSONData() throws -> Data {
        return try JSONSerialization.data(withJSONObject: allTools, options: [])
    }

    /// Returns tools filtered by allowlist. When allowlist is nil or empty, returns tools for current platform.
    static func toolsFiltered(allowlist: [String]?) -> [[String: Any]] {
        let base = toolsForCurrentPlatform
        guard let names = allowlist, !names.isEmpty else { return base }
        let set = Set(names.map { $0.trimmingCharacters(in: .whitespaces) })
        return base.filter { tool in
            guard let fn = tool["function"] as? [String: Any],
                  let name = fn["name"] as? String else { return false }
            return set.contains(name)
        }
    }

    /// Returns tools filtered by allowlist, then by user denylist (removes disabled tools).
    static func toolsFiltered(allowlist: [String]?, userDenylist: Set<String>) -> [[String: Any]] {
        let base = toolsFiltered(allowlist: allowlist)
        guard !userDenylist.isEmpty else { return base }
        return base.filter { tool in
            guard let fn = tool["function"] as? [String: Any],
                  let name = fn["name"] as? String else { return false }
            return !userDenylist.contains(name)
        }
    }

    /// Tool categories for organization in Settings.
    enum ToolCategory: String, CaseIterable, Identifiable {
        case file = "File"
        case shell = "Shell"
        case clipboard = "Clipboard"
        case screen = "Screen"
        case web = "Web"
        case code = "Code"
        case git = "Git"
        case database = "Database"
        case image = "Image"
        case apiDevOps = "API & DevOps"
        case docker = "Docker & K8s"
        case browser = "Browser"
        case ai = "AI & Embeddings"
        case cloud = "Cloud Deploy"
        case apple = "Apple Native"
        case media = "Media"
        case network = "Network"
        case utilities = "Utilities"

        var id: String { rawValue }

        static func category(for toolName: String) -> ToolCategory {
            toolCategoryMap[toolName] ?? .utilities
        }

        static let toolCategoryMap: [String: ToolCategory] = [
            "read_file": .file, "batch_read_files": .file, "write_file": .file, "edit_file": .file,
            "create_file": .file, "delete_file": .file, "move_file": .file, "copy_file": .file,
            "file_info": .file, "path_exists": .file, "count_lines": .file, "list_directory": .file,
            "tree_view": .file, "search_files": .file, "grep_search": .file, "find_and_replace": .file,
            "append_file": .file, "create_directory": .file, "compress_files": .file, "extract_archive": .file,
            "run_command": .shell, "run_background": .shell, "kill_process": .shell, "which": .shell,
            "system_run": .shell, "system_notify": .shell, "get_env": .shell, "get_cwd": .shell, "list_env": .shell, "list_processes": .shell,
            "disk_usage": .shell,
            "clipboard_read": .clipboard, "clipboard_write": .clipboard, "open_url": .clipboard, "open_app": .clipboard,
            "screen_snapshot": .screen, "screen_record": .screen, "camera_snap": .screen,
            "window_list": .screen, "window_snapshot": .screen,
            "web_search": .web, "read_url": .web, "fetch_json": .web, "download_file": .web,
            "view_code_outline": .code, "run_build": .code, "run_format": .code, "get_package_deps": .code,
            "npm_install": .code, "pip_install": .code, "cargo_add": .code, "run_linter": .code, "run_tests": .code,
            "git_status": .git, "git_log": .git, "git_diff": .git, "git_branch": .git, "git_show": .git,
            "git_add": .git, "git_commit": .git, "git_stash": .git, "git_checkout": .git, "git_push": .git,
            "git_pull": .git, "git_remote": .git, "git_tag": .git, "git_reset": .git,
            "get_system_info": .shell, "list_network_interfaces": .shell,
            "sqlite_query": .database, "sqlite_schema": .database, "sqlite_tables": .database,
            "image_info": .image, "image_resize": .image, "image_convert": .image,
            "http_request": .apiDevOps, "read_env_file": .apiDevOps, "write_env_file": .apiDevOps,
            "docker_ps": .apiDevOps, "docker_images": .apiDevOps,
            "docker_run": .docker, "docker_build": .docker, "docker_logs": .docker,
            "docker_compose_up": .docker, "docker_compose_down": .docker,
            "kubectl_get": .docker, "kubectl_apply": .docker,
            "browser_open": .browser, "browser_screenshot": .browser, "browser_evaluate": .browser,
            "generate_embeddings": .ai, "semantic_search": .ai, "summarize_text": .ai,
            "vercel_deploy": .cloud, "vercel_logs": .cloud, "netlify_deploy": .cloud, "fly_deploy": .cloud,
            "regex_replace": .utilities, "port_scan": .utilities, "ssl_check": .utilities,
            "cron_parse": .utilities, "json_schema_validate": .utilities,
            "get_current_time": .utilities, "format_date": .utilities, "calculate": .utilities,
            "count_words": .utilities, "extract_urls": .utilities, "json_parse": .utilities, "yaml_parse": .utilities,
            "diff_files": .utilities, "file_hash": .utilities, "backup_file": .utilities, "ping_host": .utilities,
            "resolve_dns": .utilities, "hash_string": .utilities, "base64_encode": .utilities, "base64_decode": .utilities, "generate_uuid": .utilities,
            "get_file_type": .utilities, "detect_language": .utilities, "get_process_info": .utilities,
            "ast_parse": .code, "find_references": .code, "type_check": .code,
            "dependency_graph": .code, "code_complexity": .code,
            // Apple-native
            "spotlight_search": .apple, "keychain_read": .apple, "keychain_store": .apple,
            "calendar_events": .apple, "reminders_list": .apple, "contacts_search": .apple,
            "speech_transcribe": .apple, "ocr_extract": .apple, "image_classify": .apple,
            "shortcuts_run": .apple, "system_appearance": .apple,
            // Advanced code (Apple toolchain)
            "xcodebuild": .code, "xcrun_simctl": .code, "swift_format": .code,
            "swift_lint": .code, "swift_package": .code,
            // Media
            "pdf_extract": .media, "tts_speak": .media, "qr_generate": .media,
            // Network
            "websocket_send": .network, "graphql_query": .network, "bonjour_discover": .network
        ]
    }

    /// Tools grouped by category for Settings UI.
    static func toolsByCategory(_ category: ToolCategory) -> [(name: String, icon: String)] {
        toolDisplayInfo.filter { ToolCategory.category(for: $0.name) == category }
    }

    /// Display info (name, SF Symbol icon) for all tools. Used in Settings UI.
    static let toolDisplayInfo: [(name: String, icon: String)] = {
        let iconMap: [String: String] = [
            "read_file": "doc.text",
            "batch_read_files": "doc.on.doc",
            "write_file": "pencil",
            "edit_file": "square.and.pencil",
            "create_file": "doc.badge.plus",
            "delete_file": "trash",
            "move_file": "arrow.right.doc",
            "copy_file": "doc.on.doc.fill",
            "file_info": "info.circle",
            "path_exists": "questionmark.folder",
            "count_lines": "list.number",
            "list_directory": "folder",
            "tree_view": "list.bullet.indent",
            "search_files": "magnifyingglass",
            "grep_search": "text.magnifyingglass",
            "find_and_replace": "arrow.left.arrow.right",
            "append_file": "plus.doc",
            "create_directory": "folder.badge.plus",
            "compress_files": "arrow.down.doc.zip",
            "extract_archive": "arrow.up.doc",
            "run_command": "terminal",
            "run_background": "play.circle",
            "kill_process": "stop.circle",
            "which": "magnifyingglass",
            "system_run": "terminal.fill",
            "system_notify": "bell.fill",
            "get_env": "leaf.arrow.circlepath",
            "get_cwd": "folder",
            "list_env": "list.bullet.rectangle.fill",
            "list_processes": "list.bullet.rectangle",
            "disk_usage": "internaldrive",
            "clipboard_read": "doc.on.clipboard",
            "clipboard_write": "doc.on.clipboard.fill",
            "open_url": "link",
            "open_app": "app.badge",
            "screen_snapshot": "rectangle.dashed.badge.record",
            "screen_record": "record.circle",
            "camera_snap": "camera.fill",
            "window_list": "list.bullet.rectangle",
            "window_snapshot": "macwindow",
            "web_search": "globe",
            "read_url": "link",
            "fetch_json": "doc.text.magnifyingglass",
            "download_file": "arrow.down.doc",
            "view_code_outline": "chevron.left.forwardslash.chevron.right",
            "run_build": "hammer.fill",
            "run_linter": "checkmark.seal",
            "run_format": "doc.richtext",
            "get_package_deps": "shippingbox",
            "npm_install": "square.stack.3d.up",
            "pip_install": "rectangle.stack",
            "cargo_add": "plus.rectangle.on.folder",
            "run_tests": "checkmark.circle",
            "git_status": "vault",
            "git_log": "clock.arrow.circlepath",
            "git_diff": "doc.diff",
            "git_branch": "branch",
            "git_show": "eye",
            "git_add": "plus.circle",
            "git_commit": "checkmark.circle.fill",
            "git_stash": "tray.full",
            "git_checkout": "arrow.triangle.branch",
            "git_push": "square.and.arrow.up",
            "git_pull": "square.and.arrow.down",
            "get_system_info": "info.circle.fill",
            "list_network_interfaces": "network",
            "sqlite_query": "cylinder.split.1x2",
            "sqlite_schema": "list.bullet.rectangle",
            "sqlite_tables": "tablecells",
            "image_info": "photo",
            "image_resize": "arrow.up.left.and.arrow.down.right",
            "image_convert": "photo.on.rectangle.angled",
            "http_request": "arrow.triangle.2.circlepath",
            "read_env_file": "doc.text",
            "write_env_file": "pencil.and.outline",
            "docker_ps": "shippingbox.fill",
            "docker_images": "square.stack.3d.up.fill",
            "get_current_time": "clock",
            "format_date": "calendar",
            "calculate": "function",
            "count_words": "text.word.spacing",
            "extract_urls": "link",
            "json_parse": "curlybraces",
            "yaml_parse": "doc.plaintext",
            "diff_files": "doc.on.doc",
            "file_hash": "number",
            "backup_file": "doc.badge.plus",
            "git_remote": "antenna.radiowaves.left.and.right",
            "git_tag": "tag",
            "git_reset": "arrow.uturn.backward",
            "ping_host": "network",
            "resolve_dns": "globe",
            "hash_string": "number",
            "base64_encode": "character.textbox",
            "base64_decode": "character.textbox.ko",
            "generate_uuid": "number.circle",
            "get_file_type": "doc.text",
            "detect_language": "character.book.closed",
            "get_process_info": "info.circle",
            "docker_run": "play.rectangle",
            "docker_build": "hammer",
            "docker_logs": "doc.text.below.ecg",
            "docker_compose_up": "square.stack.3d.up",
            "docker_compose_down": "square.stack.3d.down.right",
            "kubectl_get": "cloud",
            "kubectl_apply": "cloud.fill",
            "browser_open": "safari",
            "browser_screenshot": "camera.viewfinder",
            "browser_evaluate": "chevron.left.forwardslash.chevron.right",
            "generate_embeddings": "waveform",
            "semantic_search": "brain",
            "summarize_text": "text.redaction",
            "vercel_deploy": "arrow.up.to.line",
            "vercel_logs": "doc.text.magnifyingglass",
            "netlify_deploy": "arrow.up.to.line",
            "fly_deploy": "paperplane.fill",
            "regex_replace": "textformat.abc.dottedunderline",
            "port_scan": "network",
            "ssl_check": "lock.shield",
            "cron_parse": "clock.arrow.2.circlepath",
            "json_schema_validate": "checkmark.seal",
            "ast_parse": "tree",
            "find_references": "magnifyingglass.circle",
            "type_check": "checkmark.diamond",
            "dependency_graph": "point.3.connected.trianglepath.dotted",
            "code_complexity": "gauge.with.dots.needle.33percent",
            // Apple-native
            "spotlight_search": "magnifyingglass.circle.fill",
            "keychain_read": "key.fill",
            "keychain_store": "key.viewfinder",
            "calendar_events": "calendar.badge.clock",
            "reminders_list": "checklist",
            "contacts_search": "person.crop.rectangle.fill",
            "speech_transcribe": "waveform.and.mic",
            "ocr_extract": "text.viewfinder",
            "image_classify": "photo.badge.checkmark",
            "shortcuts_run": "arrow.right.circle.fill",
            "system_appearance": "paintbrush.pointed.fill",
            // Advanced code
            "xcodebuild": "hammer.circle.fill",
            "xcrun_simctl": "iphone",
            "swift_format": "text.alignleft",
            "swift_lint": "checkmark.seal.fill",
            "swift_package": "shippingbox.fill",
            // Media
            "pdf_extract": "doc.richtext.fill",
            "tts_speak": "speaker.wave.3.fill",
            "qr_generate": "qrcode",
            // Network
            "websocket_send": "arrow.up.arrow.down.circle",
            "graphql_query": "arrow.triangle.branch",
            "bonjour_discover": "antenna.radiowaves.left.and.right",
            // Swift IDE Intelligence
            "apple_docs_search": "book.fill",
            "lsp_diagnostics": "stethoscope",
            "accessibility_audit": "figure.stand",
            "localization_audit": "globe",
            "spm_resolve": "shippingbox.fill",
            "app_store_checklist": "bag.fill",
            "ask_user": "questionmark.circle.fill"
        ]
        return allTools.compactMap { tool -> (String, String)? in
            guard let fn = tool["function"] as? [String: Any],
                  let name = fn["name"] as? String else { return nil }
            let icon = iconMap[name] ?? "wrench.and.screwdriver"
            return (name, icon)
        }
    }()
}
