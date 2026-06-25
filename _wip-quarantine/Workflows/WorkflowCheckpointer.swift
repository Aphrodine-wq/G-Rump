import Foundation
import CryptoKit

// MARK: - Workflow Checkpointer

/// Actor responsible for capturing, comparing, and restoring project state snapshots.
/// Uses SHA256 file hashing for efficient change detection and supports git-based rollback.
actor WorkflowCheckpointer {

    // MARK: - Configuration

    private let ignorePatterns: Set<String> = [
        ".git", ".build", "node_modules", ".swiftpm", "DerivedData",
        "Pods", ".next", "dist", "build", "__pycache__", ".cache",
        "vendor", "target", ".DS_Store", ".grump"
    ]

    private let ignoredExtensions: Set<String> = [
        "o", "d", "dylib", "a", "swiftmodule", "swiftdoc", "swiftsourceinfo",
        "xcuserstate", "pbxproj", "png", "jpg", "jpeg", "gif",
        "ico", "pdf", "zip", "tar", "gz", "lock", "resolved"
    ]

    private let maxFileSize: Int = 10 * 1024 * 1024 // 10 MB max per file
    private var snapshotCache: [String: (snapshot: ProjectStateSnapshot, date: Date)] = [:]
    private let cacheTTL: TimeInterval = 60

    // MARK: - Capture Project State

    /// Walk the directory tree, hash all source files, and return a complete snapshot.
    func captureProjectState(directory: String) async -> ProjectStateSnapshot {
        // Check cache first
        if let cached = snapshotCache[directory],
           Date().timeIntervalSince(cached.date) < cacheTTL {
            return cached.snapshot
        }

        let fm = FileManager.default
        var fileHashes: [String: String] = [:]
        var totalSize: Int64 = 0

        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: directory),
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return ProjectStateSnapshot(directoryPath: directory, fileHashes: [:], totalSize: 0)
        }

        while let url = enumerator.nextObject() as? URL {
            let path = url.path

            // Skip ignored directories
            let lastComponent = url.lastPathComponent
            if ignorePatterns.contains(lastComponent) {
                enumerator.skipDescendants()
                continue
            }

            // Skip non-regular files
            guard let resourceValues = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  resourceValues.isRegularFile == true else {
                continue
            }

            // Skip ignored extensions
            let ext = url.pathExtension.lowercased()
            if ignoredExtensions.contains(ext) {
                continue
            }

            // Skip oversized files
            let fileSize = resourceValues.fileSize ?? 0
            if fileSize > maxFileSize {
                continue
            }

            // Hash file content
            let relativePath = makeRelativePath(path, from: directory)
            if let hash = hashFile(at: path) {
                fileHashes[relativePath] = hash
                totalSize += Int64(fileSize)
            }
        }

        let snapshot = ProjectStateSnapshot(
            directoryPath: directory,
            fileHashes: fileHashes,
            totalSize: totalSize
        )

        snapshotCache[directory] = (snapshot, Date())
        return snapshot
    }

    // MARK: - Compare Snapshots

    /// Compare two snapshots and return a list of file changes (added, modified, deleted).
    func compareSnapshots(_ snapshotA: ProjectStateSnapshot,
                          _ snapshotB: ProjectStateSnapshot) -> [FileChange] {
        var changes: [FileChange] = []

        let filesA = snapshotA.fileHashes
        let filesB = snapshotB.fileHashes

        let allPaths = Set(filesA.keys).union(Set(filesB.keys))

        for path in allPaths.sorted() {
            let hashA = filesA[path]
            let hashB = filesB[path]

            switch (hashA, hashB) {
            case (.none, .some):
                changes.append(FileChange(path: path, type: .added))
            case (.some, .none):
                changes.append(FileChange(path: path, type: .deleted))
            case (.some(let a), .some(let b)) where a != b:
                changes.append(FileChange(path: path, type: .modified))
            default:
                break // unchanged
            }
        }

        // Attempt to detect renames by matching deleted+added with same hash
        let deletedFiles = changes.filter { $0.type == .deleted }
        let addedFiles = changes.filter { $0.type == .added }

        if !deletedFiles.isEmpty && !addedFiles.isEmpty {
            var renames: [(deleted: String, added: String)] = []

            for deleted in deletedFiles {
                guard let deletedHash = filesA[deleted.path] else { continue }
                for added in addedFiles {
                    guard let addedHash = filesB[added.path] else { continue }
                    if deletedHash == addedHash {
                        renames.append((deleted.path, added.path))
                        break
                    }
                }
            }

            // Replace delete+add pairs with rename entries
            var finalChanges = changes.filter { change in
                !renames.contains(where: { $0.deleted == change.path || $0.added == change.path })
            }
            for rename in renames {
                finalChanges.append(FileChange(path: "\(rename.deleted) -> \(rename.added)", type: .renamed))
            }

            return finalChanges.sorted(by: { $0.path < $1.path })
        }

        return changes.sorted(by: { $0.path < $1.path })
    }

    // MARK: - Restore Snapshot

    /// Restore project files to match a previous snapshot.
    func restoreSnapshot(_ checkpoint: CheckpointData, to directory: String) async throws {
        let fm = FileManager.default

        for fileSnapshot in checkpoint.modifiedFiles {
            let fullPath = (directory as NSString).appendingPathComponent(fileSnapshot.path)
            let parentDir = (fullPath as NSString).deletingLastPathComponent

            // Ensure parent directory exists
            if !fm.fileExists(atPath: parentDir) {
                try fm.createDirectory(atPath: parentDir, withIntermediateDirectories: true)
            }

            // Write original content back
            try fileSnapshot.originalContent.write(to: URL(fileURLWithPath: fullPath))
        }
    }

    /// Restore only specific files from a checkpoint.
    func restoreFiles(_ filePaths: [String], from checkpoint: CheckpointData, to directory: String) async throws {
        let pathSet = Set(filePaths)

        for fileSnapshot in checkpoint.modifiedFiles {
            guard pathSet.contains(fileSnapshot.path) else { continue }

            let fullPath = (directory as NSString).appendingPathComponent(fileSnapshot.path)
            let parentDir = (fullPath as NSString).deletingLastPathComponent

            let fm = FileManager.default
            if !fm.fileExists(atPath: parentDir) {
                try fm.createDirectory(atPath: parentDir, withIntermediateDirectories: true)
            }

            try fileSnapshot.originalContent.write(to: URL(fileURLWithPath: fullPath))
        }
    }

    // MARK: - Git Integration

    /// Create a git stash or commit for rollback purposes.
    func gitCheckpoint(message: String, in directory: String) async -> String? {
        let commitMessage = "checkpoint: \(message)"

        do {
            // Stage all changes
            _ = try await runGit(["add", "-A"], in: directory)

            // Check if there are changes to commit
            let status = try await runGit(["status", "--porcelain"], in: directory)
            guard !status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                // No changes to checkpoint - return current HEAD
                return try? await runGit(["rev-parse", "HEAD"], in: directory)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }

            // Create checkpoint commit
            _ = try await runGit(["commit", "-m", commitMessage], in: directory)

            // Return the commit ref
            let ref = try await runGit(["rev-parse", "HEAD"], in: directory)
            return ref.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            // Fall back to stash
            do {
                _ = try await runGit(["stash", "push", "-m", commitMessage], in: directory)
                return "stash@{0}"
            } catch {
                return nil
            }
        }
    }

    /// Rollback to a previous git ref.
    func gitRollback(to ref: String, in directory: String) {
        if ref.hasPrefix("stash@") {
            // Pop the stash
            _ = try? runGitSync(["stash", "pop"], in: directory)
        } else {
            // Reset to the commit
            _ = try? runGitSync(["reset", "--hard", ref], in: directory)
        }
    }

    /// Get the current git HEAD ref.
    func currentGitRef(in directory: String) async -> String? {
        let result = try? await runGit(["rev-parse", "HEAD"], in: directory)
        return result?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Get git status as a dictionary of path -> status.
    func gitStatus(in directory: String) async -> [String: String] {
        guard let output = try? await runGit(["status", "--porcelain"], in: directory) else {
            return [:]
        }

        var status: [String: String] = [:]
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.count > 3 else { continue }
            let code = String(trimmed.prefix(2)).trimmingCharacters(in: .whitespaces)
            let path = String(trimmed.dropFirst(3))
            status[path] = code
        }
        return status
    }

    // MARK: - File Hashing

    /// Hash a file's content using SHA256.
    func hashFile(at path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Hash arbitrary data using SHA256.
    func hashData(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Hash a string using SHA256.
    func hashString(_ string: String) -> String {
        let data = Data(string.utf8)
        return hashData(data)
    }

    // MARK: - Snapshot Comparison Utilities

    /// Calculate a summary diff between two snapshots.
    func diffSummary(_ snapshotA: ProjectStateSnapshot,
                     _ snapshotB: ProjectStateSnapshot) -> SnapshotDiffSummary {
        let changes = compareSnapshots(snapshotA, snapshotB)

        let added = changes.filter { $0.type == .added }.count
        let modified = changes.filter { $0.type == .modified }.count
        let deleted = changes.filter { $0.type == .deleted }.count
        let renamed = changes.filter { $0.type == .renamed }.count

        return SnapshotDiffSummary(
            totalChanges: changes.count,
            added: added,
            modified: modified,
            deleted: deleted,
            renamed: renamed,
            changes: changes
        )
    }

    /// Invalidate cached snapshot for a directory.
    func invalidateCache(for directory: String) {
        snapshotCache.removeValue(forKey: directory)
    }

    /// Clear all cached snapshots.
    func clearCache() {
        snapshotCache.removeAll()
    }

    // MARK: - File Snapshot Creation

    /// Create a FileSnapshot for a single file.
    func createFileSnapshot(at path: String, relativeTo baseDir: String) -> FileSnapshot? {
        let fm = FileManager.default
        guard let data = fm.contents(atPath: path) else { return nil }
        guard let hash = hashFile(at: path) else { return nil }

        let relativePath = makeRelativePath(path, from: baseDir)
        return FileSnapshot(
            path: relativePath,
            contentHash: hash,
            originalContent: data
        )
    }

    /// Create snapshots for multiple files.
    func createFileSnapshots(paths: [String], relativeTo baseDir: String) -> [FileSnapshot] {
        paths.compactMap { createFileSnapshot(at: $0, relativeTo: baseDir) }
    }

    // MARK: - Helpers

    private func makeRelativePath(_ path: String, from base: String) -> String {
        if path.hasPrefix(base) {
            var relative = String(path.dropFirst(base.count))
            if relative.hasPrefix("/") { relative = String(relative.dropFirst()) }
            return relative
        }
        return path
    }

    private func runGit(_ arguments: [String], in directory: String) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: directory)

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
            throw WorkflowCheckpointerError.gitCommandFailed(arguments.joined(separator: " "), errorOutput)
        }

        return output
    }

    private func runGitSync(_ arguments: [String], in directory: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: directory)

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

// MARK: - Snapshot Diff Summary

struct SnapshotDiffSummary: Sendable {
    let totalChanges: Int
    let added: Int
    let modified: Int
    let deleted: Int
    let renamed: Int
    let changes: [FileChange]

    var description: String {
        var parts: [String] = []
        if added > 0 { parts.append("\(added) added") }
        if modified > 0 { parts.append("\(modified) modified") }
        if deleted > 0 { parts.append("\(deleted) deleted") }
        if renamed > 0 { parts.append("\(renamed) renamed") }
        return parts.isEmpty ? "No changes" : parts.joined(separator: ", ")
    }

    var hasChanges: Bool {
        totalChanges > 0
    }
}

// MARK: - Errors

enum WorkflowCheckpointerError: Error, LocalizedError {
    case gitCommandFailed(String, String)
    case snapshotFailed(String)
    case restoreFailed(String)

    var errorDescription: String? {
        switch self {
        case .gitCommandFailed(let cmd, let error):
            return "Git command failed (\(cmd)): \(error)"
        case .snapshotFailed(let msg):
            return "Snapshot failed: \(msg)"
        case .restoreFailed(let msg):
            return "Restore failed: \(msg)"
        }
    }
}
