import Foundation

/// Approve-every-write coordinator for the daemon. Surfaces a system notification with
/// Approve/Deny actions and awaits the user's choice (timeout → deny). Also exposes
/// `resolve` so the in-app UI or tests can settle a request programmatically.
@MainActor
final class DaemonApprovalCoordinator {
    static let shared = DaemonApprovalCoordinator()

    private var pending: [String: CheckedContinuation<Bool, Never>] = [:]
    private var observersInstalled = false

    private init() {}

    /// Request approval for an autonomous write/commit. Returns true if approved.
    func requestApproval(action: String, timeout: TimeInterval = 120) async -> Bool {
        installObservers()
        let approvalId = UUID().uuidString
        GRumpNotificationService.shared.notifyApprovalNeeded(
            conversationId: UUID(),
            conversationTitle: "Autonomous Daemon",
            command: action,
            approvalId: approvalId
        )
        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            pending[approvalId] = cont
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(timeout))
                self.resolve(approvalId: approvalId, approved: false)
            }
        }
    }

    /// Settle a pending approval. Called by notification actions or tests.
    func resolve(approvalId: String, approved: Bool) {
        guard let cont = pending.removeValue(forKey: approvalId) else { return }
        cont.resume(returning: approved)
    }

    private func installObservers() {
        guard !observersInstalled else { return }
        observersInstalled = true
        NotificationCenter.default.addObserver(forName: .init("GRumpApproveAction"), object: nil, queue: .main) { note in
            let id = note.userInfo?["approvalId"] as? String
            MainActor.assumeIsolated {
                if let id { DaemonApprovalCoordinator.shared.resolve(approvalId: id, approved: true) }
            }
        }
        NotificationCenter.default.addObserver(forName: .init("GRumpDenyAction"), object: nil, queue: .main) { note in
            let id = note.userInfo?["approvalId"] as? String
            MainActor.assumeIsolated {
                if let id { DaemonApprovalCoordinator.shared.resolve(approvalId: id, approved: false) }
            }
        }
    }
}
