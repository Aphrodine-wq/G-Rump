import Foundation
import Combine
#if os(macOS)
import AppKit
#endif

// MARK: - Ambient Insight

struct AmbientInsight: Identifiable, Equatable {
    let id: UUID
    let category: Category
    let title: String
    let detail: String
    let filePath: String
    let lineNumber: Int?
    let timestamp: Date
    var dismissed: Bool = false

    enum Category: String, CaseIterable {
        case todo = "TODO"
        case unusedImport = "Unused Import"
        case missingTest = "Missing Test"
        case largeFile = "Large File"
        case complexity = "Complexity"
        case error = "Error"
        case security = "Security"

        var icon: String {
            switch self {
            case .todo: return "checklist"
            case .unusedImport: return "xmark.circle"
            case .missingTest: return "testtube.2"
            case .largeFile: return "doc.badge.ellipsis"
            case .complexity: return "gauge.with.dots.needle.67percent"
            case .error: return "exclamationmark.triangle"
            case .security: return "lock.trianglebadge.exclamationmark"
            }
        }

        var color: String {
            switch self {
            case .todo: return "blue"
            case .unusedImport: return "orange"
            case .missingTest: return "purple"
            case .largeFile: return "yellow"
            case .complexity: return "red"
            case .error: return "red"
            case .security: return "red"
            }
        }
    }
}

// MARK: - Ambient Code Awareness Service

@MainActor
final class AmbientCodeAwarenessService: ObservableObject {
    static let shared = AmbientCodeAwarenessService()
    @Published var insights: [AmbientInsight] = []
    @Published var isEnabled: Bool = UserDefaults.standard.bool(forKey: "AmbientCodeAwarenessEnabled") {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "AmbientCodeAwarenessEnabled")
            if isEnabled {
                startWatching()
            } else {
                stopWatching()
                insights.removeAll()
            }
        }
    }
    @Published var isAnalyzing = false
    @Published var currentFile: String?

    var activeInsightCount: Int {
        insights.filter { !$0.dismissed }.count
    }

    private var workingDirectory: String = ""
    private var debounceTask: Task<Void, Never>?
    private var lastAnalysisTime: Date = .distantPast
    private let analysisCooldown: TimeInterval = 30
    private let debounceInterval: TimeInterval = 5

    #if os(macOS)
    private var fsEventStream: FSEventStreamRef?
    private var streamContext: UnsafeMutablePointer<AmbientCodeAwarenessService>?
    #endif

    private static let ignoredExtensions: Set<String> = [
        "o", "d", "dylib", "a", "swiftmodule", "swiftdoc", "swiftsourceinfo",
        "DS_Store", "xcuserstate", "pbxproj", "png", "jpg", "jpeg", "gif",
        "ico", "pdf", "zip", "tar", "gz", "lock", "resolved"
    ]

    private static let ignoredDirectories: Set<String> = [
        ".build", ".git", "node_modules", ".swiftpm", "DerivedData",
        "Pods", ".next", "dist", "build", "__pycache__", ".cache",
        "vendor", "target"
    ]

    private static let codeExtensions: Set<String> = [
        "swift", "ts", "tsx", "js", "jsx", "py", "go", "rs", "rb",
        "java", "kt", "c", "cpp", "h", "hpp", "cs", "m", "mm",
        "vue", "svelte", "html", "css", "scss", "sql", "sh", "bash",
        "yaml", "yml", "json", "toml", "md"
    ]

    // MARK: - Lifecycle

    func setWorkingDirectory(_ path: String) {
        let changed = workingDirectory != path
        workingDirectory = path
        if changed && isEnabled && !path.isEmpty {
            stopWatching()
            startWatching()
            // Run initial analysis
            scheduleAnalysis(changedPaths: [])
        }
    }

    func startWatching() {
        guard isEnabled, !workingDirectory.isEmpty else { return }
        #if os(macOS)
        startFSEventStream()
        #endif
    }

    func stopWatching() {
        #if os(macOS)
        stopFSEventStream()
        #endif
        debounceTask?.cancel()
        debounceTask = nil
    }

    // MARK: - Dismiss / Act

    func dismissInsight(_ id: UUID) {
        if let idx = insights.firstIndex(where: { $0.id == id }) {
            insights[idx].dismissed = true
        }
    }

    func dismissAll() {
        for i in insights.indices {
            insights[i].dismissed = true
        }
    }

    func promptForInsight(_ insight: AmbientInsight) -> String {
        var prompt = "I noticed: \(insight.title)"
        if !insight.detail.isEmpty {
            prompt += "\n\(insight.detail)"
        }
        if !insight.filePath.isEmpty {
            prompt += "\nFile: \(insight.filePath)"
            if let line = insight.lineNumber {
                prompt += " (line \(line))"
            }
        }
        prompt += "\n\nPlease help me address this."
        return prompt
    }

    // MARK: - FSEvents (macOS)

    #if os(macOS)
    private func startFSEventStream() {
        guard fsEventStream == nil else { return }
        let pathsToWatch = [workingDirectory] as CFArray

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, info, numEvents, eventPaths, _, _ in
            guard let info = info else { return }
            let service = Unmanaged<AmbientCodeAwarenessService>.fromOpaque(info).takeUnretainedValue()
            guard let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as? [String] else { return }
            let changedPaths = Array(paths.prefix(numEvents))

            Task { @MainActor in
                service.scheduleAnalysis(changedPaths: changedPaths)
            }
        }

        fsEventStream = FSEventStreamCreate(
            nil,
            callback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            2.0, // latency in seconds
            UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        )

        if let stream = fsEventStream {
            FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
            FSEventStreamStart(stream)
        }
    }

    private func stopFSEventStream() {
        if let stream = fsEventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            fsEventStream = nil
        }
    }
    #endif

    // MARK: - Analysis Pipeline

    private func scheduleAnalysis(changedPaths: [String]) {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(debounceInterval))
            guard !Task.isCancelled else { return }

            let now = Date()
            guard now.timeIntervalSince(lastAnalysisTime) >= analysisCooldown else { return }
            lastAnalysisTime = now

            await runAnalysis(changedPaths: changedPaths)
        }
    }

    private func runAnalysis(changedPaths: [String]) async {
        guard !workingDirectory.isEmpty else { return }
        isAnalyzing = true
        defer { isAnalyzing = false }

        let filesToAnalyze: [String]
        if changedPaths.isEmpty {
            // Initial scan: find all code files
            filesToAnalyze = discoverCodeFiles(in: workingDirectory, maxFiles: 200)
        } else {
            // Incremental: only analyze changed files that are code files
            filesToAnalyze = changedPaths.filter { path in
                let ext = (path as NSString).pathExtension.lowercased()
                return Self.codeExtensions.contains(ext) && !isIgnoredPath(path)
            }
        }

        guard !filesToAnalyze.isEmpty else { return }

        var newInsights: [AmbientInsight] = []

        for path in filesToAnalyze {
            guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            let relativePath = makeRelativePath(path)

            // TODO detection
            newInsights.append(contentsOf: detectTODOs(in: content, path: relativePath))

            // Large file detection
            if let insight = detectLargeFile(content: content, path: relativePath) {
                newInsights.append(insight)
            }

            // Unused import detection
            newInsights.append(contentsOf: detectUnusedImports(in: content, path: relativePath))

            // Security pattern detection
            newInsights.append(contentsOf: detectSecurityIssues(in: content, path: relativePath))

            // Missing test detection
            if let insight = detectMissingTests(path: relativePath) {
                newInsights.append(insight)
            }
        }

        // Merge: keep existing dismissed state, add new, remove stale
        let existingDismissed = Set(insights.filter { $0.dismissed }.map { "\($0.filePath):\($0.title)" })
        for i in newInsights.indices {
            let key = "\(newInsights[i].filePath):\(newInsights[i].title)"
            if existingDismissed.contains(key) {
                newInsights[i].dismissed = true
            }
        }
        insights = newInsights
    }

    // MARK: - Detectors

    private func detectTODOs(in content: String, path: String) -> [AmbientInsight] {
        var results: [AmbientInsight] = []
        let lines = content.components(separatedBy: .newlines)
        let patterns = ["TODO:", "FIXME:", "HACK:", "XXX:", "BUG:"]

        for (lineIndex, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            for pattern in patterns {
                if trimmed.localizedCaseInsensitiveContains(pattern) {
                    let detail = trimmed
                        .replacingOccurrences(of: "//", with: "")
                        .replacingOccurrences(of: "#", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    results.append(AmbientInsight(
                        id: UUID(),
                        category: .todo,
                        title: "\(pattern.dropLast()) in \((path as NSString).lastPathComponent)",
                        detail: String(detail.prefix(120)),
                        filePath: path,
                        lineNumber: lineIndex + 1,
                        timestamp: Date()
                    ))
                    break
                }
            }
        }
        return results
    }

    private func detectLargeFile(content: String, path: String) -> AmbientInsight? {
        let lineCount = content.components(separatedBy: .newlines).count
        guard lineCount > 500 else { return nil }

        let severity = lineCount > 1000 ? "very large" : "large"
        return AmbientInsight(
            id: UUID(),
            category: .largeFile,
            title: "\((path as NSString).lastPathComponent) is \(severity) (\(lineCount) lines)",
            detail: "Consider splitting into smaller, focused files for better maintainability.",
            filePath: path,
            lineNumber: nil,
            timestamp: Date()
        )
    }

    private func detectUnusedImports(in content: String, path: String) -> [AmbientInsight] {
        let ext = (path as NSString).pathExtension.lowercased()
        var results: [AmbientInsight] = []

        let lines = content.components(separatedBy: .newlines)
        let contentWithoutImports = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return !trimmed.hasPrefix("import ") && !trimmed.hasPrefix("from ") && !trimmed.hasPrefix("require(")
        }.joined(separator: "\n")

        for (lineIndex, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if ext == "swift" && trimmed.hasPrefix("import ") {
                let module = trimmed.replacingOccurrences(of: "import ", with: "").trimmingCharacters(in: .whitespaces)
                // Skip common always-needed imports
                if ["Foundation", "SwiftUI", "UIKit", "AppKit", "Combine"].contains(module) { continue }
                // Check if module name appears elsewhere in file
                if !contentWithoutImports.contains(module) {
                    results.append(AmbientInsight(
                        id: UUID(),
                        category: .unusedImport,
                        title: "Possibly unused import: \(module)",
                        detail: "'\(module)' doesn't appear to be referenced in \((path as NSString).lastPathComponent).",
                        filePath: path,
                        lineNumber: lineIndex + 1,
                        timestamp: Date()
                    ))
                }
            }
        }
        return results
    }

    private func detectSecurityIssues(in content: String, path: String) -> [AmbientInsight] {
        var results: [AmbientInsight] = []
        let lines = content.components(separatedBy: .newlines)
        let patterns: [(String, String)] = [
            ("password", "Hardcoded password or credential detected"),
            ("api_key", "Hardcoded API key detected"),
            ("apiKey", "Hardcoded API key detected"),
            ("secret", "Hardcoded secret detected"),
            ("private_key", "Hardcoded private key detected")
        ]

        for (lineIndex, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Skip comments
            if trimmed.hasPrefix("//") || trimmed.hasPrefix("#") || trimmed.hasPrefix("*") { continue }

            for (pattern, message) in patterns {
                // Look for assignment patterns like: password = "...", apiKey: "..."
                let lowered = trimmed.lowercased()
                if lowered.contains(pattern) && (trimmed.contains("= \"") || trimmed.contains("= '") || trimmed.contains(": \"")) {
                    // Skip .env files, config templates, and test files
                    let filename = (path as NSString).lastPathComponent.lowercased()
                    if filename.contains(".env") || filename.contains("example") || filename.contains("test") || filename.contains("mock") { continue }

                    results.append(AmbientInsight(
                        id: UUID(),
                        category: .security,
                        title: message,
                        detail: "Consider using environment variables or a secure vault instead. File: \((path as NSString).lastPathComponent)",
                        filePath: path,
                        lineNumber: lineIndex + 1,
                        timestamp: Date()
                    ))
                    break
                }
            }
        }
        return results
    }

    private func detectMissingTests(path: String) -> AmbientInsight? {
        let ext = (path as NSString).pathExtension.lowercased()
        let filename = (path as NSString).lastPathComponent
        let nameWithoutExt = (filename as NSString).deletingPathExtension

        // Only check source files, not test files themselves
        guard ["swift", "ts", "tsx", "js", "jsx", "py"].contains(ext) else { return nil }
        guard !filename.lowercased().contains("test") && !filename.lowercased().contains("spec") else { return nil }
        guard !filename.lowercased().contains("mock") && !filename.lowercased().contains("fixture") else { return nil }

        // Check if there's a corresponding test file
        let testPatterns = [
            "\(nameWithoutExt)Tests.\(ext)",
            "\(nameWithoutExt)Test.\(ext)",
            "\(nameWithoutExt).test.\(ext)",
            "\(nameWithoutExt).spec.\(ext)",
            "test_\(nameWithoutExt).\(ext)"
        ]

        let fm = FileManager.default
        let baseDir = (workingDirectory as NSString).standardizingPath

        // Quick check in common test directories
        let testDirs = ["Tests", "tests", "test", "__tests__", "spec"]
        for testDir in testDirs {
            let testDirPath = (baseDir as NSString).appendingPathComponent(testDir)
            if fm.fileExists(atPath: testDirPath) {
                for pattern in testPatterns {
                    // Check recursively (shallow)
                    if let enumerator = fm.enumerator(atPath: testDirPath) {
                        while let file = enumerator.nextObject() as? String {
                            if (file as NSString).lastPathComponent == pattern {
                                return nil // Test exists
                            }
                        }
                    }
                }
            }
        }

        // Only flag files that look like they contain meaningful logic
        // (have classes/structs/functions)
        guard let content = try? String(contentsOfFile: (workingDirectory as NSString).appendingPathComponent(path), encoding: .utf8) else {
            return nil
        }

        let hasLogic = content.contains("func ") || content.contains("class ") || content.contains("struct ") ||
                       content.contains("function ") || content.contains("def ") || content.contains("export ")
        guard hasLogic else { return nil }

        return AmbientInsight(
            id: UUID(),
            category: .missingTest,
            title: "No tests found for \(filename)",
            detail: "Consider adding tests to improve coverage and catch regressions.",
            filePath: path,
            lineNumber: nil,
            timestamp: Date()
        )
    }

    // MARK: - File Discovery

    private func discoverCodeFiles(in directory: String, maxFiles: Int) -> [String] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: directory) else { return [] }

        var files: [String] = []
        while let file = enumerator.nextObject() as? String {
            guard files.count < maxFiles else { break }

            let fullPath = (directory as NSString).appendingPathComponent(file)
            if isIgnoredPath(fullPath) {
                enumerator.skipDescendants()
                continue
            }

            let ext = (file as NSString).pathExtension.lowercased()
            if Self.codeExtensions.contains(ext) {
                files.append(fullPath)
            }
        }
        return files
    }

    private func isIgnoredPath(_ path: String) -> Bool {
        let components = path.components(separatedBy: "/")
        for component in components {
            if Self.ignoredDirectories.contains(component) { return true }
            if component.hasPrefix(".") && component != "." && component != ".." { return true }
        }
        let ext = (path as NSString).pathExtension.lowercased()
        return Self.ignoredExtensions.contains(ext)
    }

    private func makeRelativePath(_ path: String) -> String {
        if path.hasPrefix(workingDirectory) {
            var relative = String(path.dropFirst(workingDirectory.count))
            if relative.hasPrefix("/") { relative = String(relative.dropFirst()) }
            return relative
        }
        return path
    }
}
