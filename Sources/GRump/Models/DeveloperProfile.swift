import Foundation

// MARK: - Developer Profile

/// Who the developer is and how they like to work. Lives at
/// `~/.grump/profile.json` (wiped by `make reset`), edited in Profile → You,
/// and injected into the system prompt between Mind and Soul.
struct DeveloperProfile: Codable, Equatable {
    var name: String = ""
    var role: String = ""
    var preferredStack: String = ""
    var codingStyle: String = ""
    var conventions: String = ""

    /// Ceiling for the prompt body — the profile is context seasoning, not a document.
    static let promptCharacterCap = 1_200

    init(name: String = "", role: String = "", preferredStack: String = "",
         codingStyle: String = "", conventions: String = "") {
        self.name = name
        self.role = role
        self.preferredStack = preferredStack
        self.codingStyle = codingStyle
        self.conventions = conventions
    }

    // Tolerant decode so older/newer profile.json files never fail to load.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        role = try container.decodeIfPresent(String.self, forKey: .role) ?? ""
        preferredStack = try container.decodeIfPresent(String.self, forKey: .preferredStack) ?? ""
        codingStyle = try container.decodeIfPresent(String.self, forKey: .codingStyle) ?? ""
        conventions = try container.decodeIfPresent(String.self, forKey: .conventions) ?? ""
    }

    var isEmpty: Bool {
        [name, role, preferredStack, codingStyle, conventions]
            .allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// System-prompt block, or nil when there's nothing to say. Only filled
    /// fields appear; the body is hard-capped at `promptCharacterCap`.
    var promptBlock: String? {
        let fields: [(label: String, value: String)] = [
            ("Name", name),
            ("Role", role),
            ("Preferred stack", preferredStack),
            ("Coding style", codingStyle),
            ("Conventions", conventions)
        ].map { ($0.0, $0.1.trimmingCharacters(in: .whitespacesAndNewlines)) }

        let filled = fields.filter { !$0.value.isEmpty }
        guard !filled.isEmpty else { return nil }

        var body = filled.map { "\($0.label): \($0.value)" }.joined(separator: "\n")
        if body.count > Self.promptCharacterCap {
            body = String(body.prefix(Self.promptCharacterCap)) + "…"
        }
        return "\n\n--- Developer Profile ---\n" + body + "\n\n--- End of developer profile ---\n\n"
    }

    // MARK: - Persistence

    static var defaultFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".grump")
            .appendingPathComponent("profile.json")
    }

    static func load(from fileURL: URL = defaultFileURL) -> DeveloperProfile {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(DeveloperProfile.self, from: data) else {
            return DeveloperProfile()
        }
        return decoded
    }

    func save(to fileURL: URL = DeveloperProfile.defaultFileURL) {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(self).write(to: fileURL)
        } catch {
            GRumpLogger.persistence.error("DeveloperProfile save failed: \(error.localizedDescription)")
        }
    }
}
