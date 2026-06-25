import Foundation

#if os(macOS)

// MARK: - Security Level

enum ExecSecurityLevel: String, Codable, CaseIterable {
    case deny
    case ask
    case allowlist
    case allow
}

// MARK: - Allowlist Entry

struct ExecAllowlistEntry: Codable, Identifiable {
    var id: String { pattern }
    let pattern: String
    let source: String // e.g. "user", "always-allow"
}

// MARK: - Exec Approvals Config

struct ExecApprovalsConfig: Codable {
    var version: Int
    var security: ExecSecurityLevel
    var askOnMiss: Bool
    var allowlist: [ExecAllowlistEntry]

    static let currentVersion = 1

    static var `default`: ExecApprovalsConfig {
        ExecApprovalsConfig(
            version: currentVersion,
            security: .deny,
            askOnMiss: true,
            allowlist: []
        )
    }
}

// MARK: - Security Presets

enum ExecSecurityPreset: String, CaseIterable, Identifiable {
    case strict
    case balanced
    case permissive

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .strict: return "Strict"
        case .balanced: return "Balanced"
        case .permissive: return "Permissive"
        }
    }

    var description: String {
        switch self {
        case .strict:
            return "Deny all shell commands. Maximum security for sensitive environments."
        case .balanced:
            return "Allow read-only tools (git status, ls, cat, which). Require approval for writes and installs."
        case .permissive:
            return "Allow most development tools. Only block destructive commands (rm -rf, sudo, format)."
        }
    }

    var icon: String {
        switch self {
        case .strict: return "lock.shield.fill"
        case .balanced: return "checkmark.shield.fill"
        case .permissive: return "shield.fill"
        }
    }

    func toConfig() -> ExecApprovalsConfig {
        switch self {
        case .strict:
            return ExecApprovalsConfig(
                version: ExecApprovalsConfig.currentVersion,
                security: .deny,
                askOnMiss: true,
                allowlist: []
            )
        case .balanced:
            return ExecApprovalsConfig(
                version: ExecApprovalsConfig.currentVersion,
                security: .allowlist,
                askOnMiss: true,
                allowlist: Self.balancedAllowlist
            )
        case .permissive:
            return ExecApprovalsConfig(
                version: ExecApprovalsConfig.currentVersion,
                security: .allowlist,
                askOnMiss: false,
                allowlist: Self.permissiveAllowlist
            )
        }
    }

    private static let balancedAllowlist: [ExecAllowlistEntry] = [
        ExecAllowlistEntry(pattern: "/usr/bin/git", source: "preset-balanced"),
        ExecAllowlistEntry(pattern: "/usr/bin/which", source: "preset-balanced"),
        ExecAllowlistEntry(pattern: "/bin/ls", source: "preset-balanced"),
        ExecAllowlistEntry(pattern: "/bin/cat", source: "preset-balanced"),
        ExecAllowlistEntry(pattern: "/usr/bin/find", source: "preset-balanced"),
        ExecAllowlistEntry(pattern: "/usr/bin/grep", source: "preset-balanced"),
        ExecAllowlistEntry(pattern: "/usr/bin/wc", source: "preset-balanced"),
        ExecAllowlistEntry(pattern: "/usr/bin/head", source: "preset-balanced"),
        ExecAllowlistEntry(pattern: "/usr/bin/tail", source: "preset-balanced"),
        ExecAllowlistEntry(pattern: "/usr/bin/diff", source: "preset-balanced"),
        ExecAllowlistEntry(pattern: "/usr/bin/file", source: "preset-balanced"),
        ExecAllowlistEntry(pattern: "/usr/bin/stat", source: "preset-balanced"),
        ExecAllowlistEntry(pattern: "/usr/bin/env", source: "preset-balanced"),
        ExecAllowlistEntry(pattern: "/usr/bin/sw_vers", source: "preset-balanced"),
        ExecAllowlistEntry(pattern: "/usr/sbin/sysctl", source: "preset-balanced"),
        ExecAllowlistEntry(pattern: "/usr/bin/uname", source: "preset-balanced"),
        ExecAllowlistEntry(pattern: "/usr/bin/mdfind", source: "preset-balanced")
    ]

    private static let permissiveAllowlist: [ExecAllowlistEntry] = balancedAllowlist + [
        ExecAllowlistEntry(pattern: "/opt/homebrew/bin/*", source: "preset-permissive"),
        ExecAllowlistEntry(pattern: "/usr/local/bin/*", source: "preset-permissive"),
        ExecAllowlistEntry(pattern: "/usr/bin/swift", source: "preset-permissive"),
        ExecAllowlistEntry(pattern: "/usr/bin/xcodebuild", source: "preset-permissive"),
        ExecAllowlistEntry(pattern: "/usr/bin/xcrun", source: "preset-permissive"),
        ExecAllowlistEntry(pattern: "/usr/bin/make", source: "preset-permissive"),
        ExecAllowlistEntry(pattern: "/bin/mkdir", source: "preset-permissive"),
        ExecAllowlistEntry(pattern: "/usr/bin/touch", source: "preset-permissive"),
        ExecAllowlistEntry(pattern: "/bin/cp", source: "preset-permissive"),
        ExecAllowlistEntry(pattern: "/bin/mv", source: "preset-permissive")
    ]
}

// MARK: - Storage

enum ExecApprovalsStorage {
    private static let fileName = "exec-approvals.json"

    static var fileURL: URL {
        let dir: URL
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let grump = appSupport.appendingPathComponent("GRump", isDirectory: true)
            if !FileManager.default.fileExists(atPath: grump.path) {
                try? FileManager.default.createDirectory(at: grump, withIntermediateDirectories: true)
            }
            dir = grump
        } else {
            dir = FileManager.default.temporaryDirectory
        }
        return dir.appendingPathComponent(fileName)
    }

    static func load() -> ExecApprovalsConfig {
        let url = fileURL
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(ExecApprovalsConfig.self, from: data) else {
            return .default
        }
        return decoded
    }

    static func save(_ config: ExecApprovalsConfig) {
        let url = fileURL
        var toSave = config
        toSave.version = ExecApprovalsConfig.currentVersion
        guard let data = try? JSONEncoder().encode(toSave) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Returns true if the resolved binary path matches the glob pattern.
    /// Pattern may be a full path or a glob (e.g. "/opt/homebrew/bin/*").
    static func path(_ resolvedPath: String, matchesPattern pattern: String) -> Bool {
        let path = (resolvedPath as NSString).standardizingPath
        let patternNorm = (pattern as NSString).standardizingPath
        if !patternNorm.contains("*") {
            return path == patternNorm
        }
        let parts = patternNorm.split(separator: "*", omittingEmptySubsequences: false).map(String.init)
        var idx = path.startIndex
        for (i, part) in parts.enumerated() {
            if part.isEmpty {
                if i == parts.count - 1 { return true }
                continue
            }
            guard let range = path.range(of: part, range: idx..<path.endIndex) else { return false }
            idx = range.upperBound
        }
        return idx == path.endIndex
    }
}

#endif
