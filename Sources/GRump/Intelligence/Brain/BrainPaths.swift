import Foundation

/// Resolves on-disk locations for the Brain subsystem (vault, config) and seeds
/// the vault folder scaffold.
///
/// Layout mirrors the SOUL.md global-vs-project override already used by `SoulStorage`
/// and `AdvancedMemoryStore`: a global brain lives under `~/.grump/`, and a project
/// brain (when present) lives under `<project>/.grump/` and takes precedence.
///
/// Everything here is generic and user-owned — no hard-coded personal paths.
enum BrainPaths {

    // MARK: - Roots

    /// Global G-Rump home: `~/.grump`.
    static var grumpHome: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".grump")
    }

    /// Per-project `.grump` directory, or nil for an empty working directory.
    static func projectGrumpDir(workingDirectory: String) -> URL? {
        guard !workingDirectory.isEmpty else { return nil }
        return URL(fileURLWithPath: (workingDirectory as NSString).standardizingPath)
            .appendingPathComponent(".grump")
    }

    /// Resolve the active vault root. A project vault (`<project>/.grump/vault`) wins
    /// if it already exists on disk; otherwise the global vault (`~/.grump/vault`).
    static func vaultRoot(workingDirectory: String = "") -> URL {
        if let projectDir = projectGrumpDir(workingDirectory: workingDirectory) {
            let projectVault = projectDir.appendingPathComponent("vault")
            if FileManager.default.fileExists(atPath: projectVault.path) {
                return projectVault
            }
        }
        return grumpHome.appendingPathComponent("vault")
    }

    // MARK: - Vault Subfolders

    /// Canonical vault subfolders. Generic taxonomy — no fixed personal scheme.
    enum VaultFolder: String, CaseIterable {
        case workingMemory = "WorkingMemory"
        case zettelkasten  = "Zettelkasten"
        case projects      = "Projects"
        case dailyNotes    = "DailyNotes"
        case decisions     = "Decisions"
        case goals         = "Goals"
    }

    static func folder(_ folder: VaultFolder, workingDirectory: String = "") -> URL {
        vaultRoot(workingDirectory: workingDirectory).appendingPathComponent(folder.rawValue)
    }

    /// Derived backlink index file (`<vault>/.index/backlinks.json`). Rebuildable.
    static func backlinkIndex(workingDirectory: String = "") -> URL {
        vaultRoot(workingDirectory: workingDirectory)
            .appendingPathComponent(".index")
            .appendingPathComponent("backlinks.json")
    }

    // MARK: - Scaffolding

    /// Create the global vault folder tree and seed a Working Memory note if absent.
    /// Idempotent and cheap; safe to call on every launch.
    static func ensureVaultScaffold() {
        let fm = FileManager.default
        let root = grumpHome.appendingPathComponent("vault")

        for folder in VaultFolder.allCases {
            let dir = root.appendingPathComponent(folder.rawValue)
            if !fm.fileExists(atPath: dir.path) {
                do {
                    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                } catch {
                    GRumpLogger.brain.error("Failed to create vault folder \(folder.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        // Index directory for the rebuildable backlink map.
        let indexDir = root.appendingPathComponent(".index")
        if !fm.fileExists(atPath: indexDir.path) {
            try? fm.createDirectory(at: indexDir, withIntermediateDirectories: true)
        }

        // Seed a Working Memory note so the vault is never empty on first open.
        let current = root
            .appendingPathComponent(VaultFolder.workingMemory.rawValue)
            .appendingPathComponent("Current.md")
        if !fm.fileExists(atPath: current.path) {
            try? seededCurrentNote.write(to: current, atomically: true, encoding: .utf8)
        }
    }

    private static let seededCurrentNote = """
    ---
    title: Current Focus
    type: working-memory
    tags: [focus]
    ---

    # Current Focus

    _What you're working on right now. G-Rump keeps this updated as you talk._

    ## Open Loops

    """
}
