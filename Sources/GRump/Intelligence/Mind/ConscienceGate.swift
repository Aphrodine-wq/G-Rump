import Foundation

/// The result of a Conscience evaluation.
struct ConscienceVerdict: Sendable, Equatable {
    let approved: Bool
    let reason: String
    let surface: Surface
    let evidence: [String]

    static let approvedNeutral = ConscienceVerdict(approved: true, reason: "approved", surface: .neutral, evidence: [])
}

/// Deterministic, fail-closed gate that runs BEFORE a mutating/sensitive tool executes.
/// It refuses when a sensitive surface is on screen, when an action targets a protected
/// branch / secret path, or when a roster value would be violated. Pure logic → reproducible.
actor ConscienceGate {
    static let shared = ConscienceGate()

    func evaluate(
        toolName: String,
        arguments: String,
        surface: Surface,
        surfaceEvidence: [String],
        roster: ValuesRoster
    ) -> ConscienceVerdict {
        // 1. Sensitive surface on screen — only mutating/shell tools reach this gate, so
        //    acting while a payment/login/secret is visible is refused with evidence.
        if surface != .neutral {
            return ConscienceVerdict(
                approved: false,
                reason: "a \(surface.rawValue) surface is on screen — refusing \(toolName) so the agent can't act on sensitive context",
                surface: surface,
                evidence: surfaceEvidence
            )
        }

        let args = arguments.lowercased()

        // 2. Protected-branch / force push.
        if toolName == "git_push" || args.contains("git push") {
            let protectedHit = roster.protectedBranches.contains { args.contains($0.lowercased()) }
            if protectedHit || args.contains("--force") || args.contains(" -f") {
                return ConscienceVerdict(approved: false, reason: "refusing a push to a protected branch / force push", surface: surface, evidence: [])
            }
        }

        // 3. Destructive shell.
        if args.contains("rm -rf /") || args.contains(":(){ :|:& };:") || args.contains("mkfs") {
            return ConscienceVerdict(approved: false, reason: "refusing a destructive command", surface: surface, evidence: [])
        }

        // 4. Writing to a credentials/secret path.
        if roster.secretPathFragments.contains(where: { args.contains($0.lowercased()) }) {
            return ConscienceVerdict(approved: false, reason: "refusing to write to a credentials/secret path", surface: surface, evidence: [])
        }

        // 5. Money action involving a protected counterparty (generic roster → empty by default).
        if !roster.protectedCounterparties.isEmpty {
            let counterpartyHit = roster.protectedCounterparties.contains { args.contains($0.lowercased()) }
            let moneyContext = args.contains("price") || args.contains("charge") || args.contains("invoice") || args.contains("$")
            if counterpartyHit && moneyContext {
                return ConscienceVerdict(approved: false, reason: "refusing a money action involving a protected counterparty", surface: surface, evidence: [])
            }
        }

        return ConscienceVerdict(approved: true, reason: "approved", surface: surface, evidence: [])
    }
}
