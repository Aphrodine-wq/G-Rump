import SwiftUI
#if os(iOS)
import UIKit
#endif

struct ProfileView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) var dismiss

    var modelName: String
    var workingDirectory: String
    var appliedPresetName: String?
    var totalConversations: Int
    var totalMessages: Int
    var onOpenSettings: () -> Void

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(Spacing.huge)
        .background(themeManager.palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xxl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.xxl, style: .continuous)
            .stroke(themeManager.palette.borderCrisp, lineWidth: Border.thin))
    }

    private func sectionTitle(_ title: String, icon: String) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(Typography.captionSemibold)
                .foregroundColor(themeManager.palette.effectiveAccent)
            Text(title)
                .font(Typography.captionSemibold)
                .foregroundColor(.textSecondary)
                .textCase(.uppercase)
                .tracking(0.4)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.palette.bgDark.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.huge) {
                        preferencesSection
                    }
                    .padding(Spacing.huge)
                }
            }
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundColor(themeManager.palette.effectiveAccent)
                }
            }
            #if os(macOS)
            .frame(minWidth: 440, minHeight: 480)
            #endif
        }
    }

    private var preferencesSection: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                sectionTitle("Preferences", icon: "gearshape.fill")
                VStack(alignment: .leading, spacing: Spacing.md) {
                    prefRow("Model", value: modelName)
                    prefRow("Working directory", value: workingDirectory.isEmpty ? "Not set" : workingDirectory)
                    if let preset = appliedPresetName, !preset.isEmpty {
                        prefRow("Preset", value: preset)
                    }
                }
                Button(action: onOpenSettings) {
                    HStack(spacing: Spacing.md) {
                        Image(systemName: "arrow.right.circle")
                        Text("Open Settings")
                            .font(Typography.captionSmallSemibold)
                    }
                    .foregroundColor(themeManager.palette.effectiveAccent)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func prefRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Text(label)
                .font(Typography.captionSmall)
                .foregroundColor(.textMuted)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .font(Typography.captionSmall)
                .foregroundColor(.textPrimary)
                .lineLimit(2)
            Spacer()
        }
    }

}
