import Foundation
#if os(macOS)
import AppKit
import CoreGraphics
import ScreenCaptureKit
#else
import UIKit
#endif
import UserNotifications

// MARK: - Shell, System, Clipboard, Screen Tool Execution
// Extracted from ChatViewModel+ToolExecution.swift for maintainability.

extension ChatViewModel {

    // MARK: - Shell

    func executeRunBackground(_ args: [String: Any]) async -> String {
        guard let command = args["command"] as? String else { return "Error: missing command" }
        #if os(macOS)
        let cwd = (args["cwd"] as? String).map { resolvePath($0) } ?? (workingDirectory.isEmpty ? nil : workingDirectory)
        return await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-l", "-c", command]
                if let cwd = cwd {
                    process.currentDirectoryURL = URL(fileURLWithPath: cwd)
                }
                do {
                    try process.run()
                    cont.resume(returning: "Started in background. PID: \(process.processIdentifier)")
                } catch {
                    cont.resume(returning: "Error: \(error.localizedDescription)")
                }
            }
        }
        #else
        return "Error: run_background is not available on iOS"
        #endif
    }

    func executeKillProcess(_ args: [String: Any]) async -> String {
        guard let pid = args["pid"] as? Int else { return "Error: missing pid" }
        let sig = args["signal"] as? Int ?? 15
        return await runProcess(executablePath: "/bin/kill", arguments: ["-\(sig)", "\(pid)"], cwd: nil, stdoutLimitLines: 10)
    }

    func executeWhich(_ args: [String: Any]) async -> String {
        guard let name = args["name"] as? String else { return "Error: missing name" }
        // Validate executable name contains only safe characters
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.+"))
        guard name.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return "Error: invalid executable name"
        }
        return await runProcess(executablePath: "/usr/bin/which", arguments: [name], cwd: nil, stdoutLimitLines: 10)
    }

    // MARK: - Environment

    func executeGetCwd() -> String {
        let cwd = workingDirectory.isEmpty ? (FileManager.default.currentDirectoryPath) : workingDirectory
        return (cwd as NSString).standardizingPath
    }

    func executeListEnv(_ args: [String: Any]) -> String {
        let env = ProcessInfo.processInfo.environment
        let prefix = args["prefix"] as? String ?? ""
        var pairs: [(String, String)] = env.map { ($0.key, $0.value) }
        if !prefix.isEmpty {
            pairs = pairs.filter { $0.0.hasPrefix(prefix) }
        }
        let sorted = pairs.sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
        return sorted.map { "\($0.0)=\($0.1)" }.joined(separator: "\n")
    }

    func executeGetEnv(_ args: [String: Any]) -> String {
        if let name = args["name"] as? String, !name.isEmpty {
            let value = ProcessInfo.processInfo.environment[name] ?? ""
            return "\(name)=\(value)"
        }
        let env = ProcessInfo.processInfo.environment
        let keys = ["PATH", "HOME", "USER", "SHELL", "LANG", "PWD", "EDITOR", "GIT_EDITOR", "NODE_ENV", "VIRTUAL_ENV", "RUST_BACKTRACE"]
        var out: [String] = []
        for key in keys {
            if let v = env[key], !v.isEmpty {
                let display = v.count > 120 ? String(v.prefix(120)) + "…" : v
                out.append("\(key)=\(display)")
            }
        }
        if out.isEmpty {
            return "No common env vars set. Use get_env with name to read a specific variable."
        }
        return out.joined(separator: "\n")
    }

    func executeListProcesses(_ args: [String: Any]) async -> String {
        let filter = args["filter"] as? String
        let limit = args["limit"] as? Int ?? 50
        let output = await runProcess(executablePath: "/bin/ps", arguments: ["-eo", "pid,comm"], cwd: nil, stdoutLimitLines: limit + 100)
        var lines = output.components(separatedBy: "\n")
        // Remove header
        if !lines.isEmpty { lines.removeFirst() }
        // Apply filter in Swift
        if let f = filter, !f.isEmpty {
            lines = lines.filter { $0.localizedCaseInsensitiveContains(f) }
        }
        return Array(lines.prefix(limit)).joined(separator: "\n")
    }

    func executeDiskUsage(_ args: [String: Any]) async -> String {
        let path = (args["path"] as? String).map { resolvePath($0) } ?? (workingDirectory.isEmpty ? FileManager.default.currentDirectoryPath : workingDirectory)
        return await runProcess(executablePath: "/bin/df", arguments: ["-h", path], cwd: nil, stdoutLimitLines: 20)
    }

    // MARK: - System Info

    func executeGetSystemInfo() -> String {
        var lines: [String] = []
        #if os(macOS)
        lines.append("OS: macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("Host: \(ProcessInfo.processInfo.hostName)")
        lines.append("Cores: \(ProcessInfo.processInfo.processorCount)")
        #else
        lines.append("OS: iOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("Host: \(ProcessInfo.processInfo.hostName)")
        #endif
        return lines.joined(separator: "\n")
    }

    func executeListNetworkInterfaces() async -> String {
        let output = await runProcess(executablePath: "/sbin/ifconfig", arguments: [], cwd: nil, stdoutLimitLines: 200)
        let filtered = output.components(separatedBy: "\n").filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("inet ") || (!line.hasPrefix("\t") && !line.hasPrefix(" ") && !line.isEmpty)
        }
        return Array(filtered.prefix(60)).joined(separator: "\n")
    }

    // MARK: - System Run (macOS)

    #if os(macOS)
    func executeSystemRun(_ args: [String: Any]) async -> String {
        guard let command = args["command"] as? String, !command.trimmingCharacters(in: .whitespaces).isEmpty else {
            return "Error: missing or empty command"
        }
        let cwd = (args["cwd"] as? String).map { ($0 as NSString).expandingTildeInPath }
        let timeoutSeconds = args["timeout_seconds"] as? Int ?? 60
        let resolvedPath = resolveExecutablePath(from: command, cwd: cwd)

        // Conscience gate runs first — short-circuits before the approval flow.
        if let refusal = await conscienceRefusal(toolName: "system_run", arguments: command) {
            return refusal
        }

        var config = ExecApprovalsStorage.load()
        let allowed: Bool
        switch config.security {
        case .allow:
            allowed = true
        case .deny:
            allowed = false
        case .allowlist, .ask:
            let inList = config.allowlist.contains { ExecApprovalsStorage.path(resolvedPath, matchesPattern: $0.pattern) }
            if inList {
                allowed = true
            } else if config.security == .allowlist {
                allowed = false
            } else if config.askOnMiss {
                // Notify user if app is backgrounded
                if let conv = currentConversation {
                    GRumpNotificationService.shared.notifyApprovalNeeded(
                        conversationId: conv.id,
                        conversationTitle: conv.title,
                        command: resolvedPath,
                        approvalId: conv.id.uuidString
                    )
                }
                let response = await withCheckedContinuation { (cont: CheckedContinuation<SystemRunApprovalResponse, Never>) in
                    systemRunApprovalContinuation = cont
                    pendingSystemRunApproval = (command, resolvedPath)
                }
                switch response {
                case .deny:
                    systemRunHistory.append(SystemRunHistoryEntry(command: command, resolvedPath: resolvedPath, allowed: false))
                    return "Command denied by user: \(resolvedPath)"
                case .allowOnce:
                    allowed = true
                case .allowAlways:
                    config.allowlist.append(ExecAllowlistEntry(pattern: resolvedPath, source: "always-allow"))
                    ExecApprovalsStorage.save(config)
                    allowed = true
                }
            } else {
                allowed = false
            }
        }
        if !allowed {
            systemRunHistory.append(SystemRunHistoryEntry(command: command, resolvedPath: resolvedPath, allowed: false))
            return "Command not allowed by exec approvals: \(resolvedPath). Check Settings → Security or allow this command when prompted."
        }
        systemRunHistory.append(SystemRunHistoryEntry(command: command, resolvedPath: resolvedPath, allowed: true))
        let env = filteredEnvironmentForSystemRun()
        return await runShellCommandWithEnvironment(command: command, cwd: cwd, timeoutSeconds: timeoutSeconds, environment: env)
    }

    func resolveExecutablePath(from command: String, cwd: String?) -> String {
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.split(separator: " ", omittingEmptySubsequences: true).first else {
            return trimmed
        }
        let firstToken = String(first)
        if firstToken.contains("/") {
            return (firstToken as NSString).expandingTildeInPath
        }
        let pathEnv = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        for dir in pathEnv.split(separator: ":") {
            let candidate = (String(dir).trimmingCharacters(in: .whitespaces) as NSString).appendingPathComponent(firstToken)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate, isDirectory: &isDir), !isDir.boolValue {
                return (candidate as NSString).standardizingPath
            }
        }
        return firstToken
    }

    func filteredEnvironmentForSystemRun() -> [String: String] {
        let dropPrefixes = ["DYLD_", "LD_", "NODE_OPTIONS", "PYTHON", "PERL", "RUBYOPT"]
        let dropExact = Set(["PATH"])
        var out = ProcessInfo.processInfo.environment
        for key in out.keys {
            if dropExact.contains(key) { out[key] = nil; continue }
            if dropPrefixes.contains(where: { key.hasPrefix($0) }) { out[key] = nil }
        }
        return out
    }

    func runShellCommandWithEnvironment(command: String, cwd: String?, timeoutSeconds: Int?, environment: [String: String]) async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-l", "-c", command]
                process.environment = environment
                if let cwd = cwd {
                    process.currentDirectoryURL = URL(fileURLWithPath: cwd)
                }
                let pipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = pipe
                process.standardError = errPipe
                do {
                    try process.run()
                    final class TimeoutFlag: @unchecked Sendable { var didTimeout = false }
                    let timeoutFlag = TimeoutFlag()
                    if let t = timeoutSeconds, t > 0 {
                        DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(t)) {
                            if process.isRunning {
                                timeoutFlag.didTimeout = true
                                process.terminate()
                            }
                        }
                    }
                    let outData = pipe.fileHandleForReading.readDataToEndOfFile()
                    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    var result = String(data: outData, encoding: .utf8) ?? ""
                    let exitCode = process.terminationStatus
                    if let err = String(data: errData, encoding: .utf8), !err.isEmpty {
                        result += "\nSTDERR:\n" + err
                    }
                    if timeoutFlag.didTimeout, let t = timeoutSeconds {
                        result = (result.isEmpty ? "" : result + "\n") + "⚠️ Command timed out after \(t) seconds."
                    }
                    if exitCode != 0 {
                        result += "\n[Exit code: \(exitCode)]"
                    }
                    if result.count > 30000 {
                        let head = String(result.prefix(15000))
                        let tail = String(result.suffix(5000))
                        result = head + "\n\n[... \(result.count - 20000) characters truncated ...]\n\n" + tail
                    }
                    continuation.resume(returning: result.isEmpty ? "(no output, exit code: \(exitCode))" : result)
                } catch {
                    continuation.resume(returning: "Error: \(error.localizedDescription)")
                }
            }
        }
    }
    #endif

    // MARK: - System Notify

    func executeSystemNotify(_ args: [String: Any]) -> String {
        guard let title = args["title"] as? String,
              let body = args["body"] as? String else {
            return "Error: missing title or body"
        }
        let subtitle = args["subtitle"] as? String
        Task { @MainActor in
            await postSystemNotification(title: title, body: body, subtitle: subtitle)
        }
        return "Notification sent."
    }

    func postSystemNotification(title: String, body: String, subtitle: String?) async {
        let allowNotifications = UserDefaults.standard.object(forKey: "AllowSystemNotifications") as? Bool ?? true
        if !allowNotifications {
            return
        }
        guard GRumpRuntime.notificationsAvailable else { return }
        let center = UNUserNotificationCenter.current()
        let soundEnabled = UserDefaults.standard.object(forKey: "NotificationSoundEnabled") as? Bool ?? true
        let options: UNAuthorizationOptions = soundEnabled ? [.alert, .sound] : [.alert]
        do {
            let granted = try await center.requestAuthorization(options: options)
            if !granted {
                return
            }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            if let sub = subtitle, !sub.isEmpty {
                content.subtitle = sub
            }
            content.sound = soundEnabled ? .default : nil
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            try await center.add(request)
        } catch {}
    }

    // MARK: - Clipboard & Open

    func executeClipboardRead() -> String {
        #if os(macOS)
        let str = NSPasteboard.general.string(forType: .string)
        if let s = str, !s.isEmpty {
            return s
        }
        return "(clipboard is empty or contains non-text data)"
        #else
        let str = UIPasteboard.general.string
        if let s = str, !s.isEmpty {
            return s
        }
        return "(clipboard is empty or contains non-text data)"
        #endif
    }

    func executeClipboardWrite(_ args: [String: Any]) -> String {
        guard let text = args["text"] as? String else { return "Error: missing text" }
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
        return "Copied \(text.count) characters to clipboard."
    }

    func executeOpenURL(_ args: [String: Any]) -> String {
        guard let urlString = args["url"] as? String,
              let url = URL(string: urlString) else {
            return "Error: invalid URL"
        }
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        Task { @MainActor in _ = await UIApplication.shared.open(url) }
        #endif
        return "Opened URL: \(urlString)"
    }

    func executeOpenApp(_ args: [String: Any]) -> String {
        guard let nameOrScheme = args["name"] as? String else { return "Error: missing name" }
        #if os(macOS)
        if let url = URL(string: nameOrScheme), nameOrScheme.contains(":") {
            NSWorkspace.shared.open(url)
            return "Opened: \(nameOrScheme)"
        }
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: nameOrScheme) {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(at: appURL, configuration: config)
            return "Opened: \(nameOrScheme)"
        }
        let appPath = "/Applications/\(nameOrScheme).app"
        if FileManager.default.fileExists(atPath: appPath) {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: appPath), configuration: config)
            return "Opened: \(nameOrScheme)"
        }
        return "Could not open '\(nameOrScheme)'. Make sure it's installed."
        #else
        if let url = URL(string: nameOrScheme), nameOrScheme.contains(":") {
            Task { @MainActor in _ = await UIApplication.shared.open(url) }
            return "Opened: \(nameOrScheme)"
        }
        return "open_app on iOS supports URL schemes only (e.g. tel:123, maps:). Use open_url for web links."
        #endif
    }

    // MARK: - Screen & Window

    #if os(macOS)
    func executeScreenSnapshot() async -> String {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else {
                return "Error: no display found for screen capture."
            }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.width = display.width * 2
            config.height = display.height * 2
            config.showsCursor = false
            let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            let tempDir = FileManager.default.temporaryDirectory
            let fileURL = tempDir.appendingPathComponent("g-rump-screenshot-\(UUID().uuidString.prefix(8)).png")
            guard let dest = CGImageDestinationCreateWithURL(fileURL as CFURL, "public.png" as CFString, 1, nil) else {
                return "Error: could not create image file"
            }
            CGImageDestinationAddImage(dest, cgImage, nil)
            guard CGImageDestinationFinalize(dest) else {
                return "Error: could not write image"
            }
            return "Screenshot saved to: \(fileURL.path)"
        } catch {
            return "Error: could not capture screen (\(error.localizedDescription)). Ensure Screen Recording permission is granted in System Settings → Privacy & Security."
        }
    }

    func executeScreenRecord(_ args: [String: Any]) -> String {
        let duration = args["duration_seconds"] as? Int ?? 5
        let capped = min(max(duration, 1), 60)
        return "Screen recording is not yet implemented in-app. To record the screen, use system_run with a command such as: screencapture -v -T \(capped) /tmp/recording.mp4 (requires Screen Recording permission)."
    }

    func executeCameraSnap() -> String {
        return "Camera capture is not yet implemented. Enable Camera permission in System Settings → Privacy & Security → Camera for future support."
    }

    func executeWindowList() -> String {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[CFString: Any]] else {
            return "Error: could not get window list"
        }
        var lines: [String] = []
        for info in list.prefix(100) {
            let name = info[kCGWindowOwnerName as CFString] as? String ?? "?"
            let layer = info[kCGWindowLayer as CFString] as? Int ?? 0
            let title = info[kCGWindowName as CFString] as? String ?? ""
            if layer == 0, !name.isEmpty {
                lines.append("\(name): \(title.isEmpty ? "(no title)" : title)")
            }
        }
        if lines.isEmpty { return "No windows found." }
        return "Windows:\n" + lines.joined(separator: "\n")
    }

    func executeWindowSnapshot(_ args: [String: Any]) -> String {
        let appName = args["app_name"] as? String
        if appName != nil {
            return "window_snapshot for a specific app requires Accessibility permission. Enable in System Settings → Privacy & Security → Accessibility. Frontmost-window snapshot is not yet implemented."
        }
        return "window_snapshot requires Accessibility permission. Enable in System Settings → Privacy & Security → Accessibility, then use window_list to see available windows."
    }
    #else
    func executeScreenSnapshot() async -> String {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: { $0.isKeyWindow }) else {
            return "Error: could not get key window for screen capture."
        }
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
        guard let pngData = image.pngData() else {
            return "Error: could not encode screenshot."
        }
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("g-rump-screenshot-\(UUID().uuidString.prefix(8)).png")
        do {
            try pngData.write(to: fileURL)
            return "Screenshot saved to: \(fileURL.path)"
        } catch {
            return "Error saving screenshot: \(error.localizedDescription)"
        }
    }
    func executeScreenRecord(_ args: [String: Any]) -> String { "screen_record is only available on macOS." }
    func executeCameraSnap() -> String {
        "Camera capture on iOS requires AVFoundation integration. Enable Camera permission in Settings → Privacy. Use screen_snapshot for screen capture."
    }
    func executeWindowList() -> String { "window_list is only available on macOS." }
    func executeWindowSnapshot(_ args: [String: Any]) -> String { "window_snapshot is only available on macOS." }
    #endif
}
