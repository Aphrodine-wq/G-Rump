import SwiftUI

/// Inline card shown above the chat input on the first message of a new
/// conversation, asking which agent mode to start the session in.
/// Mirrors the SpecContextBar presentation (inline, not a sheet).
struct ModeSelectCard: View {
    @EnvironmentObject var themeManager: ThemeManager
    let currentMode: AgentMode
    let onPick: (AgentMode) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(spacing: Spacing.lg) {
                Image(systemName: "square.on.square.intersection.dashed")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(themeManager.palette.effectiveAccent)

                Text("What mode would you like to start this session in?")
                    .font(Typography.captionSmallSemibold)
                    .foregroundColor(themeManager.palette.textPrimary)

                Spacer()

                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(themeManager.palette.textMuted)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(ScaleButtonStyle())
                .help("Cancel")
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.lg)

            Rectangle()
                .fill(themeManager.palette.borderSubtle)
                .frame(height: Border.thin)

            // Mode options
            VStack(alignment: .leading, spacing: Spacing.sm) {
                ForEach(AgentMode.allCases) { mode in
                    ModeOptionRow(
                        mode: mode,
                        isSelected: mode == currentMode,
                        action: { onPick(mode) }
                    )
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.lg)

            Rectangle()
                .fill(themeManager.palette.borderSubtle)
                .frame(height: Border.thin)

            // Footer hint
            Text("Switch anytime — ⇧⇥ cycles modes, ⏎ confirms")
                .font(Typography.micro)
                .foregroundColor(themeManager.palette.textMuted)
                .padding(.horizontal, Spacing.xl)
                .padding(.vertical, Spacing.md)
        }
        .background(themeManager.palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .stroke(themeManager.palette.effectiveAccent.opacity(0.3), lineWidth: Border.thin)
        )
        .padding(.horizontal, Spacing.xxxl)
        .padding(.bottom, Spacing.md)
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .opacity
        ))
    }
}

/// A single selectable mode row: icon, name, short description, accent
/// highlight when selected. Shared by ModeSelectCard and the status-bar
/// mode popover.
struct ModeOptionRow: View {
    @EnvironmentObject var themeManager: ThemeManager
    let mode: AgentMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.lg) {
                Image(systemName: mode.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isSelected ? mode.modeAccentColor : themeManager.palette.textSecondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.displayName)
                        .font(Typography.captionSmallSemibold)
                        .foregroundColor(themeManager.palette.textPrimary)
                    Text(mode.description)
                        .font(Typography.captionSmall)
                        .foregroundColor(themeManager.palette.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(mode.modeAccentColor)
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
            .contentShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(isSelected ? mode.modeAccentColor.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .stroke(isSelected ? mode.modeAccentColor.opacity(0.5) : Color.clear, lineWidth: Border.thin)
            )
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityLabel("\(mode.displayName) mode")
        .accessibilityHint(mode.description)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
