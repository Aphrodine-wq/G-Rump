import Foundation

// MARK: - User Correction Detector

/// Pure classifier: was the user's follow-up message a correction of the
/// previous run? Combines message keywords with hard UI signals (rejected
/// code blocks, denied approvals). Deliberately conservative — a false
/// "correction" poisons outcome data more than a miss does.
enum UserCorrectionDetector {

    private static let phrases: [String] = [
        "that's wrong", "thats wrong", "that is wrong", "not what i asked",
        "not what i wanted", "not what i meant", "that broke", "you broke",
        "didn't work", "didnt work", "doesn't work", "doesnt work",
        "still broken", "still fails", "still failing", "undo that",
        "revert that", "roll that back", "wrong file", "wrong place",
        "that's not right", "thats not right", "try again", "start over",
        "fix what you", "you deleted", "you removed my"
    ]

    private static let leadingNegations = ["no,", "no.", "nope", "wrong,", "wrong."]

    /// Reasons this message counts as a correction; empty = not a correction.
    static func reasons(
        message: String,
        rejectedCodeBlocks: Int = 0,
        approvalDenials: Int = 0
    ) -> [String] {
        var reasons: [String] = []
        let lower = message.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        if let phrase = phrases.first(where: { lower.contains($0) }) {
            reasons.append("message: \"\(phrase)\"")
        } else if let negation = leadingNegations.first(where: { lower.hasPrefix($0) }) {
            reasons.append("message opens with \"\(negation)\"")
        }

        if rejectedCodeBlocks > 0 {
            reasons.append("\(rejectedCodeBlocks) code block(s) rejected")
        }
        if approvalDenials > 0 {
            reasons.append("\(approvalDenials) command approval(s) denied")
        }
        return reasons
    }
}
