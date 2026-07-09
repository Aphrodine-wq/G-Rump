// MARK: - ProfileView
//
// You | Your Agent. "You" is the developer profile that feeds the system
// prompt (DeveloperProfile, ~/.grump/profile.json) plus usage/workspace info;
// "Your Agent" embeds the SOUL editor verbatim.

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

    private enum ProfileTab: String, CaseIterable {
        case you = "You"
        case yourAgent = "Your Agent"
    }

    @State private var selectedTab: ProfileTab = .you
    @State private var profile = DeveloperProfile()
    @State private var showSavedConfirmation = false

    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.palette.bgDark.ignoresSafeArea()

                VStack(spacing: 0) {
                    Picker("", selection: $selectedTab) {
                        ForEach(ProfileTab.allCases, id: \.self) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 320)
                    .padding(.top, Spacing.lg)
                    .padding(.bottom, Spacing.md)

                    switch selectedTab {
                    case .you:
                        youTab
                    case .yourAgent:
                        SoulSettingsView(workingDirectory: workingDirectory)
                            .padding(.horizontal, Spacing.lg)
                    }
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
            .frame(minWidth: 780, minHeight: 640)
            #endif
        }
        .onAppear {
            profile = DeveloperProfile.load()
        }
    }

    // MARK: - You Tab

    private var youTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.huge) {
                aboutYouCard
                howYouWorkCard
                saveRow
                usageCard
            }
            .padding(Spacing.huge)
        }
    }

    private var aboutYouCard: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                sectionTitle("About you", icon: "person.fill")
                labeledField("Name", placeholder: "How G-Rump should address you", text: $profile.name)
                labeledField("Role", placeholder: "e.g. iOS developer, full-stack, founder", text: $profile.role)
            }
        }
    }

    private var howYouWorkCard: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                sectionTitle("How you work", icon: "hammer.fill")
                labeledField("Preferred stack", placeholder: "e.g. Swift/SwiftUI, Next.js, Python", text: $profile.preferredStack)
                labeledEditor("Coding style", placeholder: "e.g. small functions, no force unwraps, tests first", text: $profile.codingStyle)
                labeledEditor("Conventions", placeholder: "Team or project rules G-Rump should respect", text: $profile.conventions)
            }
        }
    }

    private var saveRow: some View {
        HStack(spacing: Spacing.xl) {
            Button {
                profile.save()
                withAnimation(.easeInOut(duration: Anim.quick)) { showSavedConfirmation = true }
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2))
                    withAnimation(.easeInOut(duration: Anim.quick)) { showSavedConfirmation = false }
                }
            } label: {
                Text("Save Profile")
                    .font(Typography.bodySmallSemibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, Spacing.xl)
                    .padding(.vertical, Spacing.lg)
                    .background(themeManager.palette.effectiveAccent)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)

            if showSavedConfirmation {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.accentGreen)
                    Text("Saved")
                        .font(Typography.captionSmall)
                        .foregroundColor(themeManager.palette.textSecondary)
                }
                .transition(.opacity)
            }

            Spacer()

            Text("Included in G-Rump's system prompt.")
                .font(Typography.captionSmall)
                .foregroundColor(themeManager.palette.textMuted)
        }
    }

    private var usageCard: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                sectionTitle("Usage & workspace", icon: "chart.bar.fill")
                HStack(spacing: Spacing.colossal) {
                    statBlock(value: totalConversations, label: "Conversations")
                    statBlock(value: totalMessages, label: "Messages")
                }
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

    // MARK: - Building Blocks

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

    private func labeledField(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(label)
                .font(Typography.captionSmall)
                .foregroundColor(.textMuted)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(Typography.bodySmall)
                .padding(Spacing.lg)
                .background(themeManager.palette.bgInput)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .stroke(themeManager.palette.borderCrisp, lineWidth: Border.thin))
        }
    }

    private func labeledEditor(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(label)
                .font(Typography.captionSmall)
                .foregroundColor(.textMuted)
            ZStack(alignment: .topLeading) {
                if text.wrappedValue.isEmpty {
                    Text(placeholder)
                        .font(Typography.bodySmall)
                        .foregroundColor(.textMuted)
                        .padding(.horizontal, Spacing.lg + 4)
                        .padding(.vertical, Spacing.lg)
                        .allowsHitTesting(false)
                }
                TextEditor(text: text)
                    .font(Typography.bodySmall)
                    .scrollContentBackground(.hidden)
                    .padding(Spacing.md)
                    .frame(height: 72)
            }
            .background(themeManager.palette.bgInput)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .stroke(themeManager.palette.borderCrisp, lineWidth: Border.thin))
        }
    }

    private func statBlock(value: Int, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(Typography.displayMedium)
                .foregroundColor(.textPrimary)
            Text(label)
                .font(Typography.captionSmall)
                .foregroundColor(.textMuted)
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
