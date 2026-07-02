import Foundation

/// Generic, user-editable values the Conscience gate enforces. Ships with safe, generic
/// defaults — NO personal names. Loaded from `~/.grump/values-roster.json` when present.
struct ValuesRoster: Sendable, Codable {
    /// Counterparties never to act against in a money context (generic: empty by default).
    var protectedCounterparties: [String] = []
    /// Branches a push must never target without explicit human approval.
    var protectedBranches: [String] = ["main", "master"]
    /// Path fragments that indicate a credentials/secret file (writes refused).
    var secretPathFragments: [String] = ["id_rsa", "id_ed25519", "/.ssh/", "/.aws/credentials", ".pem"]

    static let `default` = ValuesRoster()

    private static var path: URL {
        BrainPaths.grumpHome.appendingPathComponent("values-roster.json")
    }

    /// Load from disk, or return generic defaults.
    static func load() -> ValuesRoster {
        guard let data = try? Data(contentsOf: path),
              let roster = try? JSONDecoder().decode(ValuesRoster.self, from: data) else {
            return .default
        }
        return roster
    }
}
