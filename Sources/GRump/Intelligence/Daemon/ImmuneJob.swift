import Foundation

/// Self-heal health checks for the daemon. Returns a list of issues (empty = healthy).
/// Verifies the brain's storage substrate is intact before the daemon acts.
enum ImmuneJob {
    static func check() async -> [String] {
        var issues: [String] = []
        let fm = FileManager.default

        // ~/.grump home present and writable.
        let home = BrainPaths.grumpHome
        if !fm.fileExists(atPath: home.path) {
            try? fm.createDirectory(at: home, withIntermediateDirectories: true)
        }
        let probe = home.appendingPathComponent(".health-probe")
        do {
            try "ok".write(to: probe, atomically: true, encoding: .utf8)
            try? fm.removeItem(at: probe)
        } catch {
            issues.append("~/.grump not writable")
        }

        // Vault root writable.
        let vaultRoot = BrainPaths.vaultRoot()
        let vaultProbe = vaultRoot.appendingPathComponent(".health-probe")
        do {
            try fm.createDirectory(at: vaultRoot, withIntermediateDirectories: true)
            try "ok".write(to: vaultProbe, atomically: true, encoding: .utf8)
            try? fm.removeItem(at: vaultProbe)
        } catch {
            issues.append("vault not writable")
        }

        // Observation DB opens cleanly.
        let store = ObservationStore()
        await store.open()
        _ = await store.count()

        return issues
    }
}
