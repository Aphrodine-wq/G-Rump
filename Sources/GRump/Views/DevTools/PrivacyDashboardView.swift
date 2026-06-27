import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - Privacy Dashboard View
//
// Shows data flow visualization, on-device status, and privacy controls.
// Designed to signal Apple's #1 differentiator: "your code never leaves your Mac."

struct PrivacyDashboardView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @AppStorage("LocalOnlyMode") private var localOnlyMode = false
    @AppStorage("ShowPrivacyBadge") private var showPrivacyBadge = true

    var currentProvider: AIProvider = .qwen
    var onDeviceAvailable: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.huge) {
            // Hero section
            privacyHero

            // Data flow visualization
            dataFlowCard

            // Privacy controls
            controlsCard

            // On-device status
            onDeviceCard

            // Privacy manifest generator
            privacyManifestCard
        }
    }

    // MARK: - Hero

    private var privacyHero: some View {
        HStack(spacing: Spacing.xl) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [themeManager.palette.effectiveAccent, .accentGreen],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Privacy & On-Device")
                    .font(Typography.heading2)
                    .foregroundColor(themeManager.palette.textPrimary)

                Text(isFullyLocal
                     ? "All inference runs on-device. Your code never leaves your Mac."
                     : "Some requests are sent to cloud providers. Enable Local Only mode for full privacy.")
                    .font(Typography.bodySmall)
                    .foregroundColor(themeManager.palette.textSecondary)
            }

            Spacer()

            // Privacy status badge
            HStack(spacing: Spacing.sm) {
                Circle()
                    .fill(isFullyLocal ? Color.accentGreen : Color.accentOrange)
                    .frame(width: 8, height: 8)
                Text(isFullyLocal ? "Fully Local" : "Cloud Active")
                    .font(Typography.captionSmallSemibold)
                    .foregroundColor(isFullyLocal ? .accentGreen : .accentOrange)
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.md)
            .background((isFullyLocal ? Color.accentGreen : Color.accentOrange).opacity(0.12))
            .clipShape(Capsule())
        }
        .padding(Spacing.huge)
        .background(themeManager.palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xxl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xxl, style: .continuous)
                .stroke(themeManager.palette.borderCrisp, lineWidth: Border.thin)
        )
    }

    // MARK: - Data Flow Card

    private var dataFlowCard: some View {
        VStack(alignment: .leading, spacing: Spacing.xxl) {
            sectionHeader("Data Flow", icon: "arrow.left.arrow.right", color: themeManager.palette.effectiveAccent)

            VStack(spacing: Spacing.lg) {
                dataFlowRow(
                    icon: "desktopcomputer",
                    label: "On-Device (Core ML)",
                    detail: "Code stays on your Mac",
                    status: .local,
                    isActive: false
                )

                dataFlowRow(
                    icon: "cloud",
                    label: "Qwen Cloud (DashScope)",
                    detail: "Encrypted in transit, not stored by the provider",
                    status: .cloud,
                    isActive: currentProvider == .qwen
                )

                dataFlowRow(
                    icon: "server.rack",
                    label: "G-Rump Backend",
                    detail: "Auth & credit tracking only — no code is sent",
                    status: .metadata,
                    isActive: true
                )
            }
        }
        .padding(Spacing.huge)
        .background(themeManager.palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xxl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xxl, style: .continuous)
                .stroke(themeManager.palette.borderCrisp, lineWidth: Border.thin)
        )
    }

    private enum DataFlowStatus {
        case local, cloud, metadata
    }

    private func dataFlowRow(icon: String, label: String, detail: String, status: DataFlowStatus, isActive: Bool) -> some View {
        HStack(spacing: Spacing.xl) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(statusColor(status))
                .frame(width: 28, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Spacing.md) {
                    Text(label)
                        .font(Typography.bodySmallMedium)
                        .foregroundColor(themeManager.palette.textPrimary)

                    if isActive {
                        Text("ACTIVE")
                            .font(Typography.micro)
                            .foregroundColor(.white)
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, 1)
                            .background(statusColor(status))
                            .clipShape(Capsule())
                    }
                }

                Text(detail)
                    .font(Typography.captionSmall)
                    .foregroundColor(themeManager.palette.textMuted)
            }

            Spacer()

            Image(systemName: statusIcon(status))
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(statusColor(status))
        }
        .padding(Spacing.lg)
        .background(isActive ? statusColor(status).opacity(0.06) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: Radius.standard, style: .continuous))
    }

    private func statusColor(_ status: DataFlowStatus) -> Color {
        switch status {
        case .local: return .accentGreen
        case .cloud: return Color(red: 0.24, green: 0.53, blue: 0.98)
        case .metadata: return .accentOrange
        }
    }

    private func statusIcon(_ status: DataFlowStatus) -> String {
        switch status {
        case .local: return "lock.fill"
        case .cloud: return "arrow.up.forward.circle"
        case .metadata: return "info.circle"
        }
    }

    // MARK: - Controls Card

    private var controlsCard: some View {
        VStack(alignment: .leading, spacing: Spacing.xxl) {
            sectionHeader("Privacy Controls", icon: "slider.horizontal.3", color: themeManager.palette.effectiveAccent)

            Toggle(isOn: $localOnlyMode) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Local Only Mode")
                        .font(Typography.bodySmallSemibold)
                        .foregroundColor(themeManager.palette.textPrimary)
                    Text("Restrict to on-device and Ollama models only. No data leaves your Mac.")
                        .font(Typography.captionSmall)
                        .foregroundColor(themeManager.palette.textMuted)
                }
            }
            .tint(.accentGreen)

            Toggle(isOn: $showPrivacyBadge) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show Privacy Badge")
                        .font(Typography.bodySmallSemibold)
                        .foregroundColor(themeManager.palette.textPrimary)
                    Text("Display a shield icon in the top bar when running fully local.")
                        .font(Typography.captionSmall)
                        .foregroundColor(themeManager.palette.textMuted)
                }
            }
            .tint(themeManager.palette.effectiveAccent)
        }
        .padding(Spacing.huge)
        .background(themeManager.palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xxl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xxl, style: .continuous)
                .stroke(themeManager.palette.borderCrisp, lineWidth: Border.thin)
        )
    }

    // MARK: - On-Device Card

    private var onDeviceCard: some View {
        VStack(alignment: .leading, spacing: Spacing.xxl) {
            sectionHeader("Apple Silicon Status", icon: "apple.logo", color: themeManager.palette.effectiveAccent)

            #if os(macOS)
            HStack(spacing: Spacing.xl) {
                Image(systemName: "cpu")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(themeManager.palette.effectiveAccent)

                VStack(alignment: .leading, spacing: 2) {
                    Text(chipName)
                        .font(Typography.bodySemibold)
                        .foregroundColor(themeManager.palette.textPrimary)

                    Text("\(ramGB) GB Unified Memory")
                        .font(Typography.captionSmall)
                        .foregroundColor(themeManager.palette.textMuted)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("Neural Engine")
                        .font(Typography.captionSmallSemibold)
                        .foregroundColor(themeManager.palette.textSecondary)
                    Text("Available")
                        .font(Typography.micro)
                        .foregroundColor(.accentGreen)
                }
            }
            .padding(Spacing.lg)
            .background(themeManager.palette.effectiveAccent.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: Radius.standard, style: .continuous))
            #endif

            if !onDeviceAvailable {
                HStack(spacing: Spacing.xl) {
                    Image(systemName: "arrow.down.circle")
                        .font(Typography.bodyMedium)
                        .foregroundColor(themeManager.palette.textMuted)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No on-device models installed")
                            .font(Typography.bodySmallMedium)
                            .foregroundColor(themeManager.palette.textPrimary)
                        Text("Download Core ML models in Settings → Providers → On-Device to enable fully local inference.")
                            .font(Typography.captionSmall)
                            .foregroundColor(themeManager.palette.textMuted)
                    }
                }
            }
        }
        .padding(Spacing.huge)
        .background(themeManager.palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xxl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xxl, style: .continuous)
                .stroke(themeManager.palette.borderCrisp, lineWidth: Border.thin)
        )
    }

    // MARK: - Privacy Manifest Card

    private var privacyManifestCard: some View {
        VStack(alignment: .leading, spacing: Spacing.xxl) {
            sectionHeader("Privacy Manifest", icon: "doc.text.fill", color: themeManager.palette.effectiveAccent)

            Text("Generate a PrivacyInfo.xcprivacy manifest for your project, documenting API usage and data collection practices for App Store compliance.")
                .font(Typography.bodySmall)
                .foregroundColor(themeManager.palette.textMuted)

            Button(action: generatePrivacyManifest) {
                HStack(spacing: Spacing.md) {
                    Image(systemName: "doc.badge.plus")
                        .font(Typography.bodyMedium)
                    Text("Generate Privacy Manifest")
                        .font(Typography.bodySmallSemibold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, Spacing.xxl)
                .padding(.vertical, Spacing.lg)
                .background(themeManager.palette.effectiveAccent)
                .clipShape(RoundedRectangle(cornerRadius: Radius.standard, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(Spacing.huge)
        .background(themeManager.palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xxl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xxl, style: .continuous)
                .stroke(themeManager.palette.borderCrisp, lineWidth: Border.thin)
        )
    }

    private func generatePrivacyManifest() {
        Task {
            do {
                try await PrivacyManifestGenerator.shared.analyzeProject(at: URL(fileURLWithPath: "."))
                let manifest = PrivacyManifestGenerator.shared.generatedManifest?.generateJSON() ?? "{}"
                #if os(macOS)
                let savePanel = NSSavePanel()
                savePanel.nameFieldStringValue = "PrivacyInfo.xcprivacy"
                savePanel.allowedContentTypes = [.xml]
                if savePanel.runModal() == .OK, let url = savePanel.url {
                    try manifest.write(to: url, atomically: true, encoding: .utf8)
                }
                #endif
            } catch {
                GRumpLogger.capture.error("Privacy manifest generation failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Helpers

    private var isFullyLocal: Bool {
        // Qwen is cloud-only; "fully local" only when the user forces Local Only mode.
        localOnlyMode
    }

    private func sectionHeader(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(Typography.captionSemibold)
                .foregroundColor(color)
            Text(title)
                .font(Typography.captionSemibold)
                .foregroundColor(themeManager.palette.textSecondary)
                .textCase(.uppercase)
                .tracking(0.4)
        }
    }

    #if os(macOS)
    private var chipName: String {
        var size: Int = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var brand = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &brand, &size, nil, 0)
        return String(cString: brand)
    }

    private var ramGB: Int {
        Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024))
    }
    #endif
}
