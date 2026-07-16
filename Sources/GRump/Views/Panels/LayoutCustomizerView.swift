import SwiftUI

// MARK: - Layout Options (persisted)

class LayoutOptions: ObservableObject {
    static let shared = LayoutOptions()

    @Published var activityBarVisible: Bool {
        didSet { UserDefaults.standard.set(activityBarVisible, forKey: "LayoutActivityBarVisible") }
    }
    @Published var primarySidebarVisible: Bool {
        didSet { UserDefaults.standard.set(primarySidebarVisible, forKey: "LayoutPrimarySidebarVisible") }
    }
    @Published var panelVisible: Bool {
        didSet { UserDefaults.standard.set(panelVisible, forKey: "LayoutPanelVisible") }
    }
    @Published var statusBarVisible: Bool {
        didSet { UserDefaults.standard.set(statusBarVisible, forKey: "LayoutStatusBarVisible") }
    }

    @Published var primarySidebarPosition: SidebarPosition {
        didSet { UserDefaults.standard.set(primarySidebarPosition.rawValue, forKey: "LayoutPrimarySidebarPosition") }
    }

    @Published var fullScreenMode: Bool {
        didSet { UserDefaults.standard.set(fullScreenMode, forKey: "LayoutFullScreenMode") }
    }
    @Published var zenMode: Bool {
        didSet { UserDefaults.standard.set(zenMode, forKey: "LayoutZenMode") }
    }
    @Published var centeredLayout: Bool {
        didSet { UserDefaults.standard.set(centeredLayout, forKey: "LayoutCenteredLayout") }
    }

    enum SidebarPosition: String, CaseIterable {
        case left, right
        var displayName: String { rawValue.capitalized }
    }

    init() {
        self.activityBarVisible = UserDefaults.standard.object(forKey: "LayoutActivityBarVisible") as? Bool ?? true
        self.primarySidebarVisible = UserDefaults.standard.object(forKey: "LayoutPrimarySidebarVisible") as? Bool ?? true
        self.panelVisible = UserDefaults.standard.object(forKey: "LayoutPanelVisible") as? Bool ?? true
        self.statusBarVisible = UserDefaults.standard.object(forKey: "LayoutStatusBarVisible") as? Bool ?? true

        let sidebarPos = UserDefaults.standard.string(forKey: "LayoutPrimarySidebarPosition") ?? "right"
        self.primarySidebarPosition = SidebarPosition(rawValue: sidebarPos) ?? .right

        self.fullScreenMode = UserDefaults.standard.object(forKey: "LayoutFullScreenMode") as? Bool ?? false
        self.zenMode = UserDefaults.standard.object(forKey: "LayoutZenMode") as? Bool ?? false
        self.centeredLayout = UserDefaults.standard.object(forKey: "LayoutCenteredLayout") as? Bool ?? false
    }
}

// MARK: - Layout Customizer View

struct LayoutCustomizerView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject var options = LayoutOptions.shared
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text("Customize Layout")
                    .font(Typography.heading2)
                    .foregroundColor(themeManager.palette.textPrimary)

                Spacer()

                // Reset button
                Button(action: resetToDefaults) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 14))
                        .foregroundColor(themeManager.palette.textMuted)
                }
                .buttonStyle(.plain)
                .help("Reset to defaults")

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(themeManager.palette.textMuted)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Spacing.huge)
            .padding(.vertical, Spacing.xl)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Visibility Section
                    visibilitySection

                    Divider()
                        .padding(.vertical, Spacing.lg)

                    // Position Section
                    positionSection

                    Divider()
                        .padding(.vertical, Spacing.lg)

                    // Modes Section
                    modesSection
                }
                .padding(.horizontal, Spacing.huge)
                .padding(.vertical, Spacing.lg)
            }
        }
        .frame(minWidth: 480, minHeight: 520)
        .background(themeManager.palette.bgDark)
    }

    // MARK: - Visibility Section

    private var visibilitySection: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            HStack {
                Text("Visibility")
                    .font(Typography.captionSemibold)
                    .foregroundColor(themeManager.palette.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.4)

                Spacer()
            }

            VStack(spacing: 0) {
                visibilityRow(
                    icon: "sidebar.leading",
                    title: "Activity Bar",
                    isOn: $options.activityBarVisible
                )

                if !options.activityBarVisible {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(themeManager.palette.effectiveAccent)
                        Text("Re-enable via View → Show Activity Bar or ⌘⌥A")
                            .font(Typography.micro)
                            .foregroundColor(themeManager.palette.textMuted)
                    }
                    .padding(.leading, Spacing.xxxl)
                    .padding(.bottom, Spacing.sm)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                visibilityRow(
                    icon: "sidebar.left",
                    title: "Primary Side Bar",
                    isOn: $options.primarySidebarVisible
                )

                visibilityRow(
                    icon: "window.ceiling",
                    title: "Panel",
                    isOn: $options.panelVisible
                )

                visibilityRow(
                    icon: "arrow.down.to.line",
                    title: "Status Bar",
                    isOn: $options.statusBarVisible
                )
            }
        }
    }

    private func visibilityRow(icon: String, title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: Spacing.lg) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(themeManager.palette.textSecondary)
                .frame(width: 24)

            Toggle(title, isOn: isOn)
                #if os(macOS)
                .toggleStyle(.checkbox)
                #endif
                .font(Typography.bodySmall)
                .foregroundColor(themeManager.palette.textPrimary)

            Spacer()
        }
        .padding(.vertical, Spacing.sm)
    }

    // MARK: - Position Section

    private var positionSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            // Primary Side Bar Position
            HStack {
                Text("Primary Side Bar Position")
                    .font(Typography.captionSemibold)
                    .foregroundColor(themeManager.palette.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.4)

                Spacer()

                HStack(spacing: Spacing.md) {
                    positionButton(title: "Left", isSelected: options.primarySidebarPosition == .left) {
                        options.primarySidebarPosition = .left
                    }

                    positionButton(title: "Right", isSelected: options.primarySidebarPosition == .right) {
                        options.primarySidebarPosition = .right
                    }
                }
            }
        }
    }

    private func positionButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                }
                Text(title)
                    .font(Typography.captionSmallMedium)
            }
            .foregroundColor(isSelected ? themeManager.palette.effectiveAccent : themeManager.palette.textSecondary)
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.sm)
            .background(isSelected ? themeManager.palette.effectiveAccent.opacity(0.12) : themeManager.palette.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .stroke(isSelected ? themeManager.palette.effectiveAccent.opacity(0.5) : themeManager.palette.borderSubtle, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Modes Section

    private var modesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            HStack {
                Text("Modes")
                    .font(Typography.captionSemibold)
                    .foregroundColor(themeManager.palette.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.4)

                Spacer()
            }

            VStack(spacing: Spacing.md) {
                modeRow(
                    icon: "arrow.up.left.and.arrow.down.right",
                    title: "Full Screen",
                    isOn: $options.fullScreenMode
                )

                modeRow(
                    icon: "eye.slash",
                    title: "Zen Mode",
                    isOn: $options.zenMode
                )

                modeRow(
                    icon: "arrow.left.and.line.vertical.and.arrow.right",
                    title: "Centered Layout",
                    isOn: $options.centeredLayout
                )
            }
        }
    }

    private func modeRow(icon: String, title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: Spacing.lg) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(themeManager.palette.textSecondary)
                .frame(width: 24)

            Toggle(title, isOn: isOn)
                #if os(macOS)
                .toggleStyle(.checkbox)
                #endif
                .font(Typography.bodySmall)
                .foregroundColor(themeManager.palette.textPrimary)

            Spacer()
        }
        .padding(.vertical, Spacing.sm)
    }

    private func resetToDefaults() {
        options.activityBarVisible = true
        options.primarySidebarVisible = true
        options.panelVisible = true
        options.statusBarVisible = true
        options.primarySidebarPosition = .right
        options.fullScreenMode = false
        options.zenMode = false
        options.centeredLayout = false
    }
}

// MARK: - Preview

#if swift(>=5.9) && canImport(SwiftUI)
@available(macOS 14.0, iOS 17.0, *)
private struct LayoutCustomizerPreview: PreviewProvider {
    static var previews: some View {
        LayoutCustomizerView()
            .environmentObject(ThemeManager())
            .frame(width: 500, height: 600)
    }
}
#endif
