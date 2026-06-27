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

    @StateObject private var openClaw = OpenClawService.shared
    @StateObject private var costControl = OpenClawCostControl.shared

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
                        openClawSection
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

    private func usageRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(Typography.captionSmall)
                .foregroundColor(.textMuted)
            Spacer()
            Text(value)
                .font(Typography.captionSmallSemibold)
                .foregroundColor(.textPrimary)
        }
    }

    // MARK: - OpenClaw Integration

    private var openClawSection: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                sectionTitle("OpenClaw", icon: "network")

                // Connection status
                HStack(spacing: Spacing.lg) {
                    Circle()
                        .fill(openClawStatusColor)
                        .frame(width: 8, height: 8)
                    Text(openClawStatusText)
                        .font(Typography.bodySmall)
                        .foregroundColor(.textPrimary)
                    Spacer()
                    if openClaw.isEnabled {
                        Text(openClaw.connectionState.displayName)
                            .font(Typography.captionSmall)
                            .foregroundColor(.textMuted)
                    }
                }

                if openClaw.isEnabled {
                    // Active sessions
                    if !openClaw.activeSessions.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.md) {
                            usageRow("Active sessions", value: "\(openClaw.activeSessions.count)")
                            ForEach(openClaw.activeSessions) { session in
                                HStack(spacing: Spacing.md) {
                                    Image(systemName: "bubble.left.fill")
                                        .font(Typography.micro)
                                        .foregroundColor(themeManager.palette.effectiveAccent)
                                    Text(session.channel)
                                        .font(Typography.captionSmall)
                                        .foregroundColor(.textSecondary)
                                    Spacer()
                                    Text("\(session.messageCount) msgs")
                                        .font(Typography.micro)
                                        .foregroundColor(.textMuted)
                                }
                            }
                        }
                    } else {
                        usageRow("Active sessions", value: "0")
                    }

                    // Daily credit usage
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        usageRow("Credits today", value: costControl.usageSummary)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: Radius.xs)
                                    .fill(themeManager.palette.bgInput)
                                    .frame(height: 6)
                                RoundedRectangle(cornerRadius: Radius.xs)
                                    .fill(costControl.dailyUsagePercent > 0.8 ? Color.orange : themeManager.palette.effectiveAccent)
                                    .frame(width: geo.size.width * costControl.dailyUsagePercent, height: 6)
                            }
                        }
                        .frame(height: 6)
                    }

                    // Gateway URL
                    prefRow("Gateway", value: openClaw.gatewayURL)

                    // Quick actions
                    HStack(spacing: Spacing.lg) {
                        if openClaw.connectionState != .connected {
                            Button(action: { openClaw.connect() }) {
                                HStack(spacing: Spacing.md) {
                                    Image(systemName: "bolt.fill")
                                    Text("Connect")
                                        .font(Typography.captionSmallSemibold)
                                }
                                .foregroundColor(themeManager.palette.effectiveAccent)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Button(action: { openClaw.disconnect() }) {
                                HStack(spacing: Spacing.md) {
                                    Image(systemName: "bolt.slash.fill")
                                    Text("Disconnect")
                                        .font(Typography.captionSmallSemibold)
                                }
                                .foregroundColor(.orange)
                            }
                            .buttonStyle(.plain)
                        }

                        Spacer()

                        Button(action: onOpenSettings) {
                            HStack(spacing: Spacing.md) {
                                Image(systemName: "gearshape")
                                Text("Settings")
                                    .font(Typography.captionSmallSemibold)
                            }
                            .foregroundColor(themeManager.palette.effectiveAccent)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Text("OpenClaw is disabled. Enable it in Settings to receive coding tasks from Slack, Discord, iMessage, and other channels.")
                        .font(Typography.captionSmall)
                        .foregroundColor(.textMuted)
                    Button(action: onOpenSettings) {
                        HStack(spacing: Spacing.md) {
                            Image(systemName: "arrow.right.circle")
                            Text("Enable in Settings")
                                .font(Typography.captionSmallSemibold)
                        }
                        .foregroundColor(themeManager.palette.effectiveAccent)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var openClawStatusColor: Color {
        guard openClaw.isEnabled else { return .gray }
        switch openClaw.connectionState {
        case .connected: return .green
        case .connecting: return .orange
        case .disconnected: return .red
        default: return .gray
        }
    }

    private var openClawStatusText: String {
        guard openClaw.isEnabled else { return "OpenClaw Disabled" }
        switch openClaw.connectionState {
        case .connected: return "Connected to Gateway"
        case .connecting: return "Connecting…"
        case .disconnected: return "Disconnected"
        default: return "Unknown"
        }
    }

}
