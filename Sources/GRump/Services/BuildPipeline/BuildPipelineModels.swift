// ╔══════════════════════════════════════════════════════════════╗
// ║  BuildPipelineModels.swift                                  ║
// ║  Self-Healing Build Pipeline — type definitions             ║
// ╚══════════════════════════════════════════════════════════════╝

import Foundation

// MARK: - Build Configuration

/// Configuration for a build execution.
struct BuildConfig: Codable, Sendable {
    var projectPath: String
    var buildSystem: BuildSystem
    var buildCommand: String
    var testCommand: String?
    var cleanCommand: String?
    var env: [String: String]

    init(
        projectPath: String,
        buildSystem: BuildSystem = .swiftPM,
        buildCommand: String = "swift build",
        testCommand: String? = nil,
        cleanCommand: String? = nil,
        env: [String: String] = [:]
    ) {
        self.projectPath = projectPath
        self.buildSystem = buildSystem
        self.buildCommand = buildCommand
        self.testCommand = testCommand
        self.cleanCommand = cleanCommand
        self.env = env
    }
}

// MARK: - Build System

/// Supported build systems.
enum BuildSystem: String, CaseIterable, Codable, Sendable, Identifiable {
    case xcodebuild
    case swiftPM
    case cargo
    case npm
    case gradle
    case make
    case cmake
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .xcodebuild: return "Xcode Build"
        case .swiftPM: return "Swift Package Manager"
        case .cargo: return "Cargo (Rust)"
        case .npm: return "npm"
        case .gradle: return "Gradle"
        case .make: return "Make"
        case .cmake: return "CMake"
        case .custom: return "Custom"
        }
    }

    /// Typical file extensions for this build system's source files.
    var sourceExtensions: [String] {
        switch self {
        case .xcodebuild, .swiftPM: return ["swift"]
        case .cargo: return ["rs"]
        case .npm: return ["ts", "tsx", "js", "jsx"]
        case .gradle: return ["java", "kt", "kts"]
        case .make, .cmake: return ["c", "cpp", "h", "hpp"]
        case .custom: return []
        }
    }

    /// The project manifest file name.
    var manifestFileName: String? {
        switch self {
        case .xcodebuild: return nil // .xcodeproj is a directory
        case .swiftPM: return "Package.swift"
        case .cargo: return "Cargo.toml"
        case .npm: return "package.json"
        case .gradle: return "build.gradle"
        case .make: return "Makefile"
        case .cmake: return "CMakeLists.txt"
        case .custom: return nil
        }
    }

    /// Default build command for this system.
    var defaultBuildCommand: String {
        switch self {
        case .xcodebuild: return "xcodebuild build"
        case .swiftPM: return "swift build"
        case .cargo: return "cargo build"
        case .npm: return "npm run build"
        case .gradle: return "./gradlew build"
        case .make: return "make"
        case .cmake: return "cmake --build build"
        case .custom: return "./build.sh"
        }
    }

    /// Default test command.
    var defaultTestCommand: String? {
        switch self {
        case .xcodebuild: return "xcodebuild test"
        case .swiftPM: return "swift test"
        case .cargo: return "cargo test"
        case .npm: return "npm test"
        case .gradle: return "./gradlew test"
        case .make: return "make test"
        case .cmake: return "ctest --test-dir build"
        case .custom: return nil
        }
    }

    /// Default clean command.
    var defaultCleanCommand: String {
        switch self {
        case .xcodebuild: return "xcodebuild clean"
        case .swiftPM: return "swift package clean"
        case .cargo: return "cargo clean"
        case .npm: return "rm -rf node_modules dist"
        case .gradle: return "./gradlew clean"
        case .make: return "make clean"
        case .cmake: return "rm -rf build"
        case .custom: return "./clean.sh"
        }
    }
}

// MARK: - Build Result

/// The result of a single build execution.
struct BuildResult: Identifiable, Codable, Sendable {
    let id: UUID
    let timestamp: Date
    let success: Bool
    let duration: TimeInterval
    let output: String
    let errors: [BuildError]
    let warnings: [BuildWarning]
    let config: BuildConfig

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        success: Bool,
        duration: TimeInterval,
        output: String,
        errors: [BuildError] = [],
        warnings: [BuildWarning] = [],
        config: BuildConfig
    ) {
        self.id = id
        self.timestamp = timestamp
        self.success = success
        self.duration = duration
        self.output = output
        self.errors = errors
        self.warnings = warnings
        self.config = config
    }

    /// Brief summary for display.
    var summary: String {
        if success {
            return "Build succeeded in \(String(format: "%.1f", duration))s (\(warnings.count) warning\(warnings.count == 1 ? "" : "s"))"
        } else {
            return "Build failed with \(errors.count) error\(errors.count == 1 ? "" : "s") in \(String(format: "%.1f", duration))s"
        }
    }
}

// MARK: - Build Error

/// A single build error with location and categorization.
struct BuildError: Identifiable, Codable, Sendable {
    let id: UUID
    let message: String
    let filePath: String?
    let lineNumber: Int?
    let columnNumber: Int?
    let errorCode: String?
    let category: BuildErrorCategory
    let suggestedFix: String?

    init(
        id: UUID = UUID(),
        message: String,
        filePath: String? = nil,
        lineNumber: Int? = nil,
        columnNumber: Int? = nil,
        errorCode: String? = nil,
        category: BuildErrorCategory = .unknown,
        suggestedFix: String? = nil
    ) {
        self.id = id
        self.message = message
        self.filePath = filePath
        self.lineNumber = lineNumber
        self.columnNumber = columnNumber
        self.errorCode = errorCode
        self.category = category
        self.suggestedFix = suggestedFix
    }

    /// Compact location string.
    var location: String {
        var parts: [String] = []
        if let path = filePath { parts.append(path) }
        if let line = lineNumber { parts.append("line \(line)") }
        if let col = columnNumber { parts.append("col \(col)") }
        return parts.isEmpty ? "(unknown location)" : parts.joined(separator: ":")
    }
}

// MARK: - Build Error Category

/// Classification of build errors.
enum BuildErrorCategory: String, CaseIterable, Codable, Sendable {
    case syntaxError
    case typeError
    case missingImport
    case missingDependency
    case linkError
    case resourceError
    case configError
    case permissionError
    case memoryError
    case unknown

    var displayName: String {
        switch self {
        case .syntaxError: return "Syntax Error"
        case .typeError: return "Type Error"
        case .missingImport: return "Missing Import"
        case .missingDependency: return "Missing Dependency"
        case .linkError: return "Linker Error"
        case .resourceError: return "Resource Error"
        case .configError: return "Configuration Error"
        case .permissionError: return "Permission Error"
        case .memoryError: return "Memory Error"
        case .unknown: return "Unknown"
        }
    }

    /// Whether this category of error can typically be auto-fixed.
    var isAutoFixable: Bool {
        switch self {
        case .syntaxError, .missingImport, .typeError: return true
        case .missingDependency, .configError: return true
        case .linkError, .resourceError, .permissionError, .memoryError, .unknown: return false
        }
    }

    /// Priority for fix ordering. Lower = fix first (root causes before cascading errors).
    var fixPriority: Int {
        switch self {
        case .configError: return 0
        case .missingDependency: return 1
        case .missingImport: return 2
        case .syntaxError: return 3
        case .typeError: return 4
        case .linkError: return 5
        case .resourceError: return 6
        case .permissionError: return 7
        case .memoryError: return 8
        case .unknown: return 9
        }
    }
}

// MARK: - Build Warning

/// A build warning with severity classification.
struct BuildWarning: Identifiable, Codable, Sendable {
    let id: UUID
    let message: String
    let filePath: String?
    let lineNumber: Int?
    let severity: WarningLevel

    init(
        id: UUID = UUID(),
        message: String,
        filePath: String? = nil,
        lineNumber: Int? = nil,
        severity: WarningLevel = .warning
    ) {
        self.id = id
        self.message = message
        self.filePath = filePath
        self.lineNumber = lineNumber
        self.severity = severity
    }
}

// MARK: - Warning Level

enum WarningLevel: String, CaseIterable, Codable, Sendable {
    case note
    case warning
    case deprecation
}

// MARK: - Diagnostic Result

/// A diagnosed build error with root cause analysis.
struct DiagnosticResult: Codable, Sendable {
    let error: BuildError
    let rootCause: String
    let confidence: Double
    let suggestedFixes: [AutoFix]
    let relatedErrors: [BuildError]
}

// MARK: - Auto Fix

/// An automatically generated fix for a build error.
struct AutoFix: Identifiable, Codable, Sendable {
    let id: UUID
    let description: String
    let filePath: String
    let changes: [TextChange]
    let risk: FixRisk

    init(
        id: UUID = UUID(),
        description: String,
        filePath: String,
        changes: [TextChange],
        risk: FixRisk = .safe
    ) {
        self.id = id
        self.description = description
        self.filePath = filePath
        self.changes = changes
        self.risk = risk
    }
}

// MARK: - Text Change

/// A single text change within a file.
struct TextChange: Codable, Sendable {
    let startLine: Int
    let endLine: Int?
    let oldText: String?
    let newText: String
    let type: ChangeType

    init(
        startLine: Int,
        endLine: Int? = nil,
        oldText: String? = nil,
        newText: String,
        type: ChangeType = .replace
    ) {
        self.startLine = startLine
        self.endLine = endLine
        self.oldText = oldText
        self.newText = newText
        self.type = type
    }
}

// MARK: - Change Type

enum ChangeType: String, CaseIterable, Codable, Sendable {
    case insert
    case replace
    case delete
}

// MARK: - Fix Risk

/// Risk level of applying an automatic fix.
enum FixRisk: String, CaseIterable, Codable, Sendable {
    case safe
    case moderate
    case risky

    var displayName: String {
        switch self {
        case .safe: return "Safe"
        case .moderate: return "Moderate"
        case .risky: return "Risky"
        }
    }

    var shouldAutoApply: Bool {
        self == .safe
    }
}

// MARK: - Build History

/// Aggregate build history for a project.
struct BuildHistory: Codable, Sendable {
    var results: [BuildResult]
    var averageDuration: TimeInterval
    var successRate: Double
    var commonErrors: [ErrorFrequency]

    init(results: [BuildResult] = []) {
        self.results = results
        self.averageDuration = results.isEmpty ? 0 : results.map(\.duration).reduce(0, +) / Double(results.count)
        self.successRate = results.isEmpty ? 0 : Double(results.filter(\.success).count) / Double(results.count)
        self.commonErrors = BuildHistory.computeCommonErrors(results)
    }

    /// Recompute derived fields.
    mutating func recompute() {
        averageDuration = results.isEmpty ? 0 : results.map(\.duration).reduce(0, +) / Double(results.count)
        successRate = results.isEmpty ? 0 : Double(results.filter(\.success).count) / Double(results.count)
        commonErrors = BuildHistory.computeCommonErrors(results)
    }

    private static func computeCommonErrors(_ results: [BuildResult]) -> [ErrorFrequency] {
        var counts: [BuildErrorCategory: (count: Int, lastSeen: Date, autoFixable: Bool)] = [:]
        for result in results {
            for error in result.errors {
                let existing = counts[error.category]
                counts[error.category] = (
                    count: (existing?.count ?? 0) + 1,
                    lastSeen: max(existing?.lastSeen ?? .distantPast, result.timestamp),
                    autoFixable: error.category.isAutoFixable
                )
            }
        }
        return counts.map { category, info in
            ErrorFrequency(
                category: category,
                count: info.count,
                lastSeen: info.lastSeen,
                autoFixable: info.autoFixable
            )
        }.sorted { $0.count > $1.count }
    }
}

// MARK: - Error Frequency

/// Tracks how often a specific error category appears.
struct ErrorFrequency: Codable, Sendable {
    let category: BuildErrorCategory
    let count: Int
    let lastSeen: Date
    let autoFixable: Bool
}

// MARK: - Healing Attempt

/// Record of an auto-healing attempt.
struct HealingAttempt: Identifiable, Codable, Sendable {
    let id: UUID
    let buildId: UUID
    let error: BuildError
    let fixApplied: AutoFix
    let result: HealingResult

    init(
        id: UUID = UUID(),
        buildId: UUID,
        error: BuildError,
        fixApplied: AutoFix,
        result: HealingResult
    ) {
        self.id = id
        self.buildId = buildId
        self.error = error
        self.fixApplied = fixApplied
        self.result = result
    }
}

// MARK: - Healing Result

enum HealingResult: String, CaseIterable, Codable, Sendable {
    case fixed
    case partiallyFixed
    case failed
    case madeWorse
}

// MARK: - Build Trend

/// Trend analysis of build history.
enum BuildTrend: String, Sendable {
    case improving
    case stable
    case degrading

    var displayName: String {
        switch self {
        case .improving: return "Improving"
        case .stable: return "Stable"
        case .degrading: return "Degrading"
        }
    }
}
