// ╔══════════════════════════════════════════════════════════════╗
// ║  SelfHealingBuildPipeline.swift                             ║
// ║  Self-Healing Build Pipeline — build, diagnose, auto-fix    ║
// ╚══════════════════════════════════════════════════════════════╝

import Foundation
#if canImport(Observation)
import Observation
#endif

// MARK: - Self-Healing Build Pipeline

@Observable
final class SelfHealingBuildPipeline {

    // MARK: - Published State

    var currentBuild: BuildResult?
    var isBuilding: Bool = false
    var healingAttempts: [HealingAttempt] = []
    var buildHistory: BuildHistory = BuildHistory()

    // MARK: - Private

    private let diagnostics = BuildFailureDiagnostics()
    private let autoFix = AutoFixEngine()
    private let tracker = BuildHistoryTracker()

    // MARK: - Build

    /// Execute a build and return the result.
    func build(config: BuildConfig) async -> BuildResult {
        isBuilding = true
        defer { isBuilding = false }

        let startTime = Date()

        // Execute the build command
        let (exitCode, output) = await executeCommand(
            config.buildCommand,
            at: config.projectPath,
            env: config.env
        )

        let success = exitCode == 0
        let duration = Date().timeIntervalSince(startTime)

        // Parse errors and warnings
        let (errors, warnings) = parseOutput(output, buildSystem: config.buildSystem)

        let result = BuildResult(
            success: success,
            duration: duration,
            output: output,
            errors: errors,
            warnings: warnings,
            config: config
        )

        currentBuild = result
        await tracker.trackResult(result)

        return result
    }

    // MARK: - Build and Heal

    /// Build with automatic healing: diagnose errors, apply safe fixes, retry.
    func buildAndHeal(config: BuildConfig, maxAttempts: Int = 3) async -> BuildResult {
        isBuilding = true
        defer { isBuilding = false }

        var lastResult: BuildResult?

        for attempt in 1...maxAttempts {
            // Run build
            let result = await build(config: config)
            lastResult = result

            // If successful, we're done
            if result.success {
                return result
            }

            // If this is the last attempt, don't try to fix
            if attempt == maxAttempts {
                break
            }

            // Diagnose errors
            let diagnosticResults = await diagnostics.diagnose(result.errors, projectPath: config.projectPath)

            // Attempt auto-fixes for safe fixes only
            var fixedAny = false
            for diagnostic in diagnosticResults {
                let safeFixes = diagnostic.suggestedFixes.filter { $0.risk == .safe }
                for fix in safeFixes {
                    do {
                        try await autoFix.applyFix(fix)
                        let healed = HealingAttempt(
                            buildId: result.id,
                            error: diagnostic.error,
                            fixApplied: fix,
                            result: .fixed // Tentative; will be confirmed by next build
                        )
                        healingAttempts.append(healed)
                        fixedAny = true
                    } catch {
                        let failedAttempt = HealingAttempt(
                            buildId: result.id,
                            error: diagnostic.error,
                            fixApplied: fix,
                            result: .failed
                        )
                        healingAttempts.append(failedAttempt)
                    }
                }
            }

            // If we couldn't fix anything, no point retrying
            if !fixedAny {
                break
            }
        }

        return lastResult ?? BuildResult(
            success: false,
            duration: 0,
            output: "No build was executed.",
            config: config
        )
    }

    // MARK: - Output Parsing

    /// Parse build output into structured errors and warnings.
    func parseOutput(_ output: String, buildSystem: BuildSystem) -> (errors: [BuildError], warnings: [BuildWarning]) {
        var errors: [BuildError] = []
        var warnings: [BuildWarning] = []

        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            switch buildSystem {
            case .swiftPM, .xcodebuild:
                // Swift error format: /path/to/file.swift:42:10: error: message
                if let parsed = parseSwiftErrorLine(trimmed) {
                    if parsed.isError {
                        errors.append(parsed.buildError)
                    } else {
                        warnings.append(parsed.buildWarning!)
                    }
                }

            case .cargo:
                // Rust error format: error[E0XXX]: message --> path:line:col
                if let parsed = parseRustErrorLine(trimmed, fullOutput: lines) {
                    errors.append(parsed)
                }
                if let parsed = parseRustWarningLine(trimmed) {
                    warnings.append(parsed)
                }

            case .npm:
                // TypeScript: path(line,col): error TSXXXX: message
                // Also: ERROR in path
                if let parsed = parseTypeScriptErrorLine(trimmed) {
                    errors.append(parsed)
                }
                if let parsed = parseNpmWarningLine(trimmed) {
                    warnings.append(parsed)
                }

            case .gradle:
                if let parsed = parseGradleErrorLine(trimmed) {
                    errors.append(parsed)
                }

            case .make, .cmake:
                // GCC/Clang: path:line:col: error: message
                if let parsed = parseCErrorLine(trimmed) {
                    if parsed.isError {
                        errors.append(parsed.buildError)
                    } else {
                        warnings.append(parsed.buildWarning!)
                    }
                }

            case .custom:
                // Best-effort: try all parsers
                if let parsed = parseSwiftErrorLine(trimmed) {
                    if parsed.isError {
                        errors.append(parsed.buildError)
                    } else {
                        warnings.append(parsed.buildWarning!)
                    }
                } else if trimmed.lowercased().contains("error") {
                    errors.append(BuildError(message: trimmed, category: .unknown))
                }
            }
        }

        return (errors, warnings)
    }

    // MARK: - Build System Detection

    /// Auto-detect the build system from project files at the given path.
    func detectBuildSystem(at path: String) -> BuildConfig {
        let fm = FileManager.default

        // Check for various manifest files
        let checks: [(String, BuildSystem)] = [
            ("Package.swift", .swiftPM),
            ("Cargo.toml", .cargo),
            ("package.json", .npm),
            ("build.gradle", .gradle),
            ("build.gradle.kts", .gradle),
            ("CMakeLists.txt", .cmake),
            ("Makefile", .make),
        ]

        for (fileName, system) in checks {
            let filePath = (path as NSString).appendingPathComponent(fileName)
            if fm.fileExists(atPath: filePath) {
                return BuildConfig(
                    projectPath: path,
                    buildSystem: system,
                    buildCommand: system.defaultBuildCommand,
                    testCommand: system.defaultTestCommand,
                    cleanCommand: system.defaultCleanCommand
                )
            }
        }

        // Check for .xcodeproj
        if let items = try? fm.contentsOfDirectory(atPath: path) {
            if items.contains(where: { $0.hasSuffix(".xcodeproj") }) {
                return BuildConfig(
                    projectPath: path,
                    buildSystem: .xcodebuild,
                    buildCommand: "xcodebuild build",
                    testCommand: "xcodebuild test"
                )
            }
        }

        return BuildConfig(
            projectPath: path,
            buildSystem: .custom,
            buildCommand: "make"
        )
    }

    // MARK: - Error Line Parsers

    /// Parse result from a Swift/Clang error line.
    private struct ParsedLine {
        let isError: Bool
        let buildError: BuildError
        let buildWarning: BuildWarning?

        init(error: BuildError) {
            self.isError = true
            self.buildError = error
            self.buildWarning = nil
        }

        init(warning: BuildWarning) {
            self.isError = false
            self.buildError = BuildError(message: warning.message) // Placeholder
            self.buildWarning = warning
        }
    }

    /// Parse Swift/Clang format: /path:line:col: error|warning: message
    private func parseSwiftErrorLine(_ line: String) -> ParsedLine? {
        // Pattern: /some/path.swift:42:10: error: some message
        let pattern = #"^(.+?):(\d+):(\d+):\s+(error|warning|note):\s+(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else {
            return nil
        }

        let path = extractGroup(match, group: 1, in: line)
        let lineNum = Int(extractGroup(match, group: 2, in: line)) ?? 0
        let col = Int(extractGroup(match, group: 3, in: line)) ?? 0
        let level = extractGroup(match, group: 4, in: line)
        let message = extractGroup(match, group: 5, in: line)

        if level == "error" {
            let category = categorizeSwiftError(message)
            return ParsedLine(error: BuildError(
                message: message,
                filePath: path,
                lineNumber: lineNum,
                columnNumber: col,
                category: category,
                suggestedFix: nil
            ))
        } else {
            let severity: WarningLevel
            switch level {
            case "warning": severity = .warning
            case "note": severity = .note
            default: severity = .warning
            }
            return ParsedLine(warning: BuildWarning(
                message: message,
                filePath: path,
                lineNumber: lineNum,
                severity: severity
            ))
        }
    }

    /// Parse Rust error: error[EXXXX]: message
    private func parseRustErrorLine(_ line: String, fullOutput: [String]) -> BuildError? {
        let pattern = #"^error(\[E\d+\])?:\s+(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else {
            return nil
        }

        let errorCode = match.range(at: 1).location != NSNotFound
            ? extractGroup(match, group: 1, in: line)
            : nil
        let message = extractGroup(match, group: 2, in: line)

        return BuildError(
            message: message,
            errorCode: errorCode,
            category: categorizeRustError(message, code: errorCode)
        )
    }

    /// Parse Rust warning line.
    private func parseRustWarningLine(_ line: String) -> BuildWarning? {
        let pattern = #"^warning:\s+(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else {
            return nil
        }
        let message = extractGroup(match, group: 1, in: line)
        let severity: WarningLevel = message.contains("deprecated") ? .deprecation : .warning
        return BuildWarning(message: message, severity: severity)
    }

    /// Parse TypeScript error: path(line,col): error TSXXXX: message
    private func parseTypeScriptErrorLine(_ line: String) -> BuildError? {
        let pattern = #"^(.+?)\((\d+),(\d+)\):\s+error\s+(TS\d+):\s+(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else {
            return nil
        }

        let path = extractGroup(match, group: 1, in: line)
        let lineNum = Int(extractGroup(match, group: 2, in: line)) ?? 0
        let col = Int(extractGroup(match, group: 3, in: line)) ?? 0
        let code = extractGroup(match, group: 4, in: line)
        let message = extractGroup(match, group: 5, in: line)

        return BuildError(
            message: message,
            filePath: path,
            lineNumber: lineNum,
            columnNumber: col,
            errorCode: code,
            category: categorizeTypeScriptError(code)
        )
    }

    /// Parse npm warning line.
    private func parseNpmWarningLine(_ line: String) -> BuildWarning? {
        if line.lowercased().hasPrefix("warn") || line.contains("WARN") {
            return BuildWarning(message: line, severity: .warning)
        }
        return nil
    }

    /// Parse Gradle error.
    private func parseGradleErrorLine(_ line: String) -> BuildError? {
        if line.contains("FAILURE:") || line.contains("error:") {
            return BuildError(message: line, category: .unknown)
        }
        return nil
    }

    /// Parse C/C++ error (same format as Swift, handled by parseSwiftErrorLine).
    private func parseCErrorLine(_ line: String) -> ParsedLine? {
        return parseSwiftErrorLine(line)
    }

    // MARK: - Error Categorization

    /// Categorize a Swift build error message.
    private func categorizeSwiftError(_ message: String) -> BuildErrorCategory {
        let lower = message.lowercased()
        if lower.contains("cannot find") && lower.contains("in scope") { return .missingImport }
        if lower.contains("no such module") { return .missingDependency }
        if lower.contains("cannot convert") || lower.contains("type") { return .typeError }
        if lower.contains("expected") { return .syntaxError }
        if lower.contains("undefined symbol") || lower.contains("linker") { return .linkError }
        if lower.contains("permission") { return .permissionError }
        if lower.contains("memory") { return .memoryError }
        return .unknown
    }

    /// Categorize a Rust build error.
    private func categorizeRustError(_ message: String, code: String?) -> BuildErrorCategory {
        if let code {
            // Common Rust error codes
            switch code {
            case "[E0432]", "[E0433]": return .missingImport
            case "[E0308]", "[E0277]": return .typeError
            case "[E0463]": return .missingDependency
            default: break
            }
        }
        let lower = message.lowercased()
        if lower.contains("cannot find") || lower.contains("not found") { return .missingImport }
        if lower.contains("mismatched types") || lower.contains("expected") { return .typeError }
        return .unknown
    }

    /// Categorize a TypeScript error by code.
    private func categorizeTypeScriptError(_ code: String) -> BuildErrorCategory {
        // Common TS error codes
        switch code {
        case "TS2304", "TS2305": return .missingImport
        case "TS2322", "TS2345": return .typeError
        case "TS1005", "TS1128": return .syntaxError
        case "TS2307": return .missingDependency
        default: return .unknown
        }
    }

    // MARK: - Command Execution

    /// Execute a shell command and return (exit code, combined output).
    private func executeCommand(
        _ command: String,
        at workingDir: String,
        env: [String: String] = [:]
    ) async -> (Int32, String) {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", command]
            process.currentDirectoryURL = URL(fileURLWithPath: workingDir)

            var environment = ProcessInfo.processInfo.environment
            for (key, value) in env {
                environment[key] = value
            }
            process.environment = environment

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            do {
                try process.run()
                process.waitUntilExit()

                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""

                let combined = stdout + (stderr.isEmpty ? "" : "\n" + stderr)
                continuation.resume(returning: (process.terminationStatus, combined))
            } catch {
                continuation.resume(returning: (-1, "Failed to execute command: \(error.localizedDescription)"))
            }
        }
    }

    // MARK: - Regex Helpers

    private func extractGroup(_ match: NSTextCheckingResult, group: Int, in string: String) -> String {
        guard group < match.numberOfRanges,
              let range = Range(match.range(at: group), in: string) else {
            return ""
        }
        return String(string[range])
    }
}
