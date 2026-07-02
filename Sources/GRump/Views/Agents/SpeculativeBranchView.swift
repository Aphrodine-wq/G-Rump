import SwiftUI

// MARK: - Speculative Branch View
//
// Shows side-by-side branches with live streaming and a "winner" badge.
// Used in the Explore agent mode to display competing solution approaches.

struct SpeculativeBranchView: View {
    let branches: [SpeculativeBranchState]
    let winnerIndex: Int?

    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Header
            HStack(spacing: Spacing.sm) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(themeManager.palette.effectiveAccent)
                Text("Speculative Branches")
                    .font(Typography.captionSemibold)
                    .foregroundColor(themeManager.palette.textPrimary)
                Spacer()
                if branches.allSatisfy({ $0.status == .completed || $0.status == .failed }) {
                    if winnerIndex != nil {
                        Label("Evaluated", systemImage: "checkmark.circle.fill")
                            .font(Typography.captionSmall)
                            .foregroundColor(.green)
                    }
                } else {
                    ProgressView()
                        .scaleEffect(0.6)
                }
            }

            // Branches
            ForEach(branches) { branch in
                branchCard(branch)
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(themeManager.palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .stroke(themeManager.palette.borderSubtle, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func branchCard(_ branch: SpeculativeBranchState) -> some View {
        let bgFill: Color = branch.isWinner ? themeManager.palette.effectiveAccent.opacity(0.06) : Color.clear
        let strokeColor: Color = branch.isWinner ? themeManager.palette.effectiveAccent.opacity(0.3) : themeManager.palette.borderSubtle.opacity(0.5)
        let strokeWidth: CGFloat = branch.isWinner ? 1.5 : 0.5

        VStack(alignment: .leading, spacing: Spacing.sm) {
            branchHeader(branch)
            branchContent(branch)
        }
        .padding(Spacing.sm)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(bgFill))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(strokeColor, lineWidth: strokeWidth))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Branch \(branch.branchIndex + 1): \(branch.strategyName). Status: \(branch.status.rawValue)")
    }

    @ViewBuilder
    private func branchHeader(_ branch: SpeculativeBranchState) -> some View {
        HStack(spacing: Spacing.sm) {
            Circle()
                .fill(statusColor(branch.status))
                .frame(width: 8, height: 8)

            Text("Approach \(branch.branchIndex + 1): \(branch.strategyName)")
                .font(Typography.captionSemibold)
                .foregroundColor(themeManager.palette.textPrimary)

            if branch.isWinner {
                Label("Winner", systemImage: "trophy.fill")
                    .font(Typography.captionSmall)
                    .foregroundColor(.yellow)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.yellow.opacity(0.15)))
            }

            Spacer()

            if let score = branch.evaluationScore {
                Text("\(Int(score * 100))%")
                    .font(Typography.codeSmall)
                    .foregroundColor(scoreColor(score))
            }

            if !branch.modelName.isEmpty {
                Text(branch.modelName)
                    .font(Typography.captionSmall)
                    .foregroundColor(themeManager.palette.textMuted)
            }

            statusBadge(branch.status)
        }
    }

    @ViewBuilder
    private func branchContent(_ branch: SpeculativeBranchState) -> some View {
        if branch.status == .running, !branch.streamingText.isEmpty {
            Text(String(branch.streamingText.suffix(300)))
                .font(Typography.codeSmall)
                .foregroundColor(themeManager.palette.textSecondary)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.sm)
                .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(themeManager.palette.bgInput))
        } else if let result = branch.result {
            let preview = result.count > 200 ? String(result.prefix(200)) + "..." : result
            Text(preview)
                .font(Typography.captionSmall)
                .foregroundColor(themeManager.palette.textSecondary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.sm)
                .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(themeManager.palette.bgInput))
        }
    }

    private func statusColor(_ status: SpeculativeBranchState.Status) -> Color {
        switch status {
        case .pending:    return .gray
        case .running:    return .blue
        case .completed:  return .green
        case .failed:     return .red
        case .evaluating: return .orange
        }
    }

    private func scoreColor(_ score: Double) -> Color {
        if score >= 0.8 { return .green }
        if score >= 0.6 { return .yellow }
        return .orange
    }

    @ViewBuilder
    private func statusBadge(_ status: SpeculativeBranchState.Status) -> some View {
        switch status {
        case .pending:
            Text("Pending")
                .font(Typography.captionSmall)
                .foregroundColor(.gray)
        case .running:
            HStack(spacing: 4) {
                ProgressView().scaleEffect(0.5)
                Text("Running")
                    .font(Typography.captionSmall)
                    .foregroundColor(.blue)
            }
        case .completed:
            Text("Done")
                .font(Typography.captionSmall)
                .foregroundColor(.green)
        case .failed:
            Text("Failed")
                .font(Typography.captionSmall)
                .foregroundColor(.red)
        case .evaluating:
            HStack(spacing: 4) {
                ProgressView().scaleEffect(0.5)
                Text("Evaluating")
                    .font(Typography.captionSmall)
                    .foregroundColor(.orange)
            }
        }
    }
}
