import SwiftUI

/// A collapsible/expandable section for markdown `<details>` blocks.
/// Renders with a disclosure triangle, summary text, and animated expand/collapse.
struct CollapsibleSectionView: View {
    @EnvironmentObject var themeManager: ThemeManager
    let summary: String
    let content: String

    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header — clickable toggle
            Button(action: {
                withAnimation(Anim.spring) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: Spacing.md) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(themeManager.palette.effectiveAccent)
                        .frame(width: 14)

                    Text(summary)
                        .font(Typography.bodySmallSemibold)
                        .foregroundColor(themeManager.palette.textPrimary)

                    Spacer()
                }
                .padding(.horizontal, Spacing.xxl)
                .padding(.vertical, Spacing.lg)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Collapse \(summary)" : "Expand \(summary)")

            // Expandable content
            if isExpanded {
                Divider()
                    .padding(.horizontal, Spacing.lg)

                MarkdownTextView(text: content, onCodeBlockTap: nil)
                    .padding(.horizontal, Spacing.xxl)
                    .padding(.vertical, Spacing.lg)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity
                    ))
            }
        }
        .background(themeManager.palette.bgCard.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: Radius.standard, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.standard, style: .continuous)
                .stroke(themeManager.palette.borderCrisp.opacity(0.3), lineWidth: Border.thin)
        )
    }
}
