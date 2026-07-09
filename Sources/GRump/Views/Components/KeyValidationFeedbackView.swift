import SwiftUI

/// Inline result row for an API-key probe, shared by Settings and onboarding.
/// The key is always saved before the probe runs, so every message reflects
/// that: invalid and indeterminate outcomes warn, they never un-save.
struct KeyValidationFeedbackView: View {
    let state: KeyValidationState
    let providerName: String

    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case .validating:
            HStack(spacing: Spacing.md) {
                ProgressView()
                    .controlSize(.small)
                Text("Checking key with \(providerName)…")
                    .font(Typography.captionSmall)
                    .foregroundColor(.textMuted)
            }
        case .result(.valid):
            feedbackRow(icon: "checkmark.circle.fill", color: .accentGreen,
                        text: "Key verified with \(providerName).")
        case .result(.invalid):
            feedbackRow(icon: "xmark.circle.fill", color: .red,
                        text: "\(providerName) rejected this key. It was saved — double-check it and save again.")
        case .result(.indeterminate(let reason)):
            feedbackRow(icon: "exclamationmark.triangle.fill", color: .accentOrange,
                        text: "Key saved, but it couldn't be verified: \(reason).")
        }
    }

    private func feedbackRow(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(color)
            Text(text)
                .font(Typography.captionSmall)
                .foregroundColor(.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
