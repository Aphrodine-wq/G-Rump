import Foundation
#if os(macOS)
import AppKit
import CoreGraphics
import ImageIO
import ScreenCaptureKit
#else
import UIKit
#endif

// MARK: - Tool Execution Utilities
//
// Shared process execution, path resolution, and utility functions
// used across all tool execution domains.

extension ChatViewModel {

    // MARK: - Process Execution

    func runShellCommand(_ command: String, cwd: String?, timeoutSeconds: Int = 60) async -> String {
        #if os(macOS)
        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", command]
            if let cwd = cwd {
                process.currentDirectoryURL = URL(fileURLWithPath: cwd)
            }

            let pipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = pipe
            process.standardError = errPipe

            do {
                try process.run()

                // Kill process after timeout
                let timeoutTask = Task {
                    try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds) * 1_000_000_000)
                    if process.isRunning {
                        process.terminate()
                    }
                }

                let outData = pipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                timeoutTask.cancel()
                var result = String(data: outData, encoding: .utf8) ?? ""

                // Truncate very long output
                if result.count > 30000 {
                    let head = String(result.prefix(15000))
                    let tail = String(result.suffix(5000))
                    result = head + "\n\n[... \(result.count - 20000) characters truncated ...]\n\n" + tail
                }

                continuation.resume(returning: result.isEmpty ? "(no output, exit code: \(process.terminationStatus))" : result)
            } catch {
                continuation.resume(returning: "Error: \(error.localizedDescription)")
            }
        }
        #else
        return await runProcess(executablePath: "/bin/sh", arguments: ["-c", command], cwd: cwd, stdoutLimitLines: nil)
        #endif
    }

    func runProcess(executablePath: String, arguments: [String], cwd: String?, stdoutLimitLines: Int?) async -> String {
        #if os(macOS)
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executablePath)
                process.arguments = arguments
                if let cwd = cwd {
                    process.currentDirectoryURL = URL(fileURLWithPath: cwd)
                }
                let pipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = pipe
                process.standardError = errPipe
                do {
                    try process.run()
                    let outData = pipe.fileHandleForReading.readDataToEndOfFile()
                    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    var outStr = String(data: outData, encoding: .utf8) ?? ""
                    if let limit = stdoutLimitLines {
                        let lines = outStr.split(separator: "\n", omittingEmptySubsequences: false)
                        if lines.count > limit {
                            outStr = lines.prefix(limit).joined(separator: "\n") + "\n[... \(lines.count - limit) more lines]"
                        }
                    }
                    if let err = String(data: errData, encoding: .utf8), !err.isEmpty {
                        outStr += "\nSTDERR:\n" + err
                    }
                    continuation.resume(returning: outStr.isEmpty ? "(no output)" : outStr)
                } catch {
                    continuation.resume(returning: "Error: \(error.localizedDescription)")
                }
            }
        }
        #else
        return "Error: process execution not available on iOS"
        #endif
    }

    // MARK: - Path Resolution

    func resolvePath(_ path: String) -> String {
        if path.hasPrefix("/") {
            return path
        }
        if path.hasPrefix("~") {
            return (path as NSString).expandingTildeInPath
        }
        let base = workingDirectory.isEmpty ? FileManager.default.currentDirectoryPath : workingDirectory
        return URL(fileURLWithPath: base).appendingPathComponent(path).path
    }

    // MARK: - Utility Functions

    func formatFileSize(_ bytes: UInt64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024) KB" }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }

    func isTransientToolError(_ result: String) -> Bool {
        let lower = result.lowercased()
        return lower.contains("error") && (
            lower.contains("timeout") ||
            lower.contains("connection refused") ||
            lower.contains("try again") ||
            lower.contains("temporarily") ||
            lower.contains("enoent") ||
            lower.contains("network") ||
            lower.contains("econnreset") ||
            lower.contains("econnrefused") ||
            lower.contains("socket") ||
            lower.contains("503") ||
            lower.contains("502") ||
            lower.contains("429")
        )
    }
}
