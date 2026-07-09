import Foundation

// MARK: - Skill Proposal

/// A reflection- or agent-authored skill change awaiting the user's decision.
/// The agent has NO direct SKILL.md write path — approval here is the only way
/// a proposal becomes a real skill.
struct SkillProposal: Codable, Identifiable, Equatable {
    enum Status: String, Codable {
        case pending
        case approved
        case rejected
    }

    let id: String
    let draft: SkillProposalDraft
    /// Current body of the skill this would replace; nil = brand-new skill.
    let existingBody: String?
    var status: Status
    let createdAt: Date
    let source: String   // "reflection" | "tool:propose_skill"

    var isUpdate: Bool { existingBody != nil }
}

// MARK: - Skill Proposal Store

/// Pending proposals at `~/.grump/skill-proposals.json`. Pending cap 10 —
/// beyond that, new proposals are refused until the user clears the queue.
/// Rejections persist forever so reflection never re-proposes them.
@MainActor
final class SkillProposalStore: ObservableObject {
    static let shared = SkillProposalStore()

    @Published private(set) var proposals: [SkillProposal] = []

    private let fileURL: URL
    private let pendingCap = 10

    static var defaultFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".grump")
            .appendingPathComponent("skill-proposals.json")
    }

    init(fileURL: URL = SkillProposalStore.defaultFileURL) {
        self.fileURL = fileURL
        proposals = Self.load(from: fileURL)
    }

    var pending: [SkillProposal] { proposals.filter { $0.status == .pending } }
    var pendingCount: Int { pending.count }
    /// Names reflection must never re-propose.
    var rejectedNames: [String] {
        proposals.filter { $0.status == .rejected }.map(\.draft.name)
    }

    // MARK: - Proposing

    /// Queues a proposal. Returns a failure reason, or nil on success.
    @discardableResult
    func propose(draft: SkillProposalDraft, source: String, workingDirectory: String = "") -> String? {
        guard pendingCount < pendingCap else {
            return "Proposal queue is full (\(pendingCap) pending) — review them in the Learning panel first."
        }
        let normalized = draft.skillId.lowercased()
        if pending.contains(where: { $0.draft.skillId.lowercased() == normalized }) {
            return "A proposal for '\(draft.skillId)' is already pending."
        }
        if proposals.contains(where: { $0.status == .rejected && $0.draft.skillId.lowercased() == normalized }) {
            return "A proposal for '\(draft.skillId)' was previously rejected."
        }

        let existingBody = SkillsStorage.loadSkills(workingDirectory: workingDirectory)
            .first { $0.baseId == draft.skillId && $0.scope != .project }?
            .body

        let proposal = SkillProposal(
            id: String(UUID().uuidString.prefix(8)).lowercased(),
            draft: draft,
            existingBody: existingBody,
            status: .pending,
            createdAt: Date(),
            source: source
        )
        proposals.append(proposal)
        save()
        return nil
    }

    // MARK: - The gate

    /// User approved: the skill is written (create or update, global scope)
    /// and enabled in the allowlist. Returns false if the write failed.
    @discardableResult
    func approve(id: String, workingDirectory: String = "") -> Bool {
        guard let index = proposals.firstIndex(where: { $0.id == id && $0.status == .pending }) else {
            return false
        }
        let draft = proposals[index].draft

        let allSkills = SkillsStorage.loadSkills(workingDirectory: workingDirectory)
        let written: Bool
        if let existing = allSkills.first(where: { $0.baseId == draft.skillId && $0.scope != .project }) {
            written = SkillsStorage.updateSkill(
                existing, newName: draft.name,
                newDescription: draft.description, newBody: draft.body
            )
        } else if let created = SkillsStorage.createSkill(
            id: draft.skillId, name: draft.name,
            description: draft.description, scope: .global
        ) {
            written = SkillsStorage.updateSkill(
                created, newName: draft.name,
                newDescription: draft.description, newBody: draft.body
            )
        } else {
            written = false
        }
        guard written else { return false }

        // Enable it — same allowlist the Skills settings drive.
        var allowlist = SkillsSettingsStorage.loadAllowlist()
        allowlist.insert("global:\(draft.skillId)")
        SkillsSettingsStorage.saveAllowlist(allowlist)

        proposals[index].status = .approved
        save()
        return true
    }

    /// User rejected: persists so reflection never re-proposes this skill.
    func reject(id: String) {
        guard let index = proposals.firstIndex(where: { $0.id == id && $0.status == .pending }) else { return }
        proposals[index].status = .rejected
        save()
    }

    // MARK: - Persistence

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(proposals).write(to: fileURL)
        } catch {
            GRumpLogger.persistence.error("SkillProposalStore save failed: \(error.localizedDescription)")
        }
    }

    private static func load(from url: URL) -> [SkillProposal] {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([SkillProposal].self, from: data) else {
            return []
        }
        return decoded
    }
}
