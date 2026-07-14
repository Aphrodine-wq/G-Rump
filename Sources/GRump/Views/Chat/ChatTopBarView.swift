import SwiftUI

struct ChatTopBarView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var ambientService: AmbientCodeAwarenessService
    @ObservedObject var viewModel: ChatViewModel
    @ObservedObject var lspService: LSPService
    @Binding var showSettings: Bool
    @Binding var settingsInitialTab: SettingsTab?
    @Binding var showTimeline: Bool
    @AppStorage("ShowPrivacyBadge") private var showPrivacyBadge = true
    @State private var isEditingTitle = false
    @State private var editedTitle = ""
    @State private var showInsightsPopover = false

    // True when the selected model runs on this machine (Ollama).
    private var isLocalProvider: Bool {
        viewModel.currentEnhancedModel?.provider.isLocal ?? false
    }

    var body: some View {
        HStack(spacing: Spacing.xxl) {
            // Inline click-to-rename title
            if isEditingTitle {
                TextField("Title", text: $editedTitle, onCommit: {
                    let trimmed = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty, let conv = viewModel.currentConversation {
                        viewModel.renameConversation(conv, to: trimmed)
                    }
                    isEditingTitle = false
                })
                .font(Typography.bodySemibold)
                .textFieldStyle(.plain)
                .frame(maxWidth: 300)
                #if os(macOS)
                .onExitCommand { isEditingTitle = false }
                #endif
            } else {
                Text(viewModel.currentConversation?.title ?? "New Chat")
                    .font(Typography.bodySemibold)
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
                    .onTapGesture {
                        editedTitle = viewModel.currentConversation?.title ?? ""
                        isEditingTitle = true
                    }
                    .help("Click to rename")
            }

            // Privacy badge for on-device inference
            if showPrivacyBadge && isLocalProvider {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text("On-Device")
                        .font(Typography.micro)
                }
                .foregroundColor(.accentGreen)
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, 3)
                .background(Color.accentGreen.opacity(0.12))
                .clipShape(Capsule())
            }

            // Connection status indicator
            ConnectionStatusDot(viewModel: viewModel)

            // LSP diagnostics badge → opens the build console's Issues tab
            if lspService.isRunning && (lspService.errorCount > 0 || lspService.warningCount > 0) {
                Button {
                    UserDefaults.standard.set("issues", forKey: "BuildConsoleTab")
                    UserDefaults.standard.set(PanelTab.build.rawValue, forKey: "SelectedPanel")
                    UserDefaults.standard.set(false, forKey: "RightPanelCollapsed")
                } label: {
                    HStack(spacing: Spacing.sm) {
                        if lspService.errorCount > 0 {
                            Label("\(lspService.errorCount)", systemImage: "xmark.circle.fill")
                                .font(Typography.micro)
                                .foregroundColor(.red)
                        }
                        if lspService.warningCount > 0 {
                            Label("\(lspService.warningCount)", systemImage: "exclamationmark.triangle.fill")
                                .font(Typography.micro)
                                .foregroundColor(.orange)
                        }
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, 3)
                    .background(lspService.errorCount > 0 ? Color.red.opacity(0.1) : Color.orange.opacity(0.1))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("SourceKit-LSP: \(lspService.errorCount) errors, \(lspService.warningCount) warnings — open Issues")
            }

            Spacer()

            if viewModel.isLoading {
                loadingControls
            } else if viewModel.isPaused {
                pausedControls
            }

            // Ambient Insights badge
            if ambientService.isEnabled && ambientService.activeInsightCount > 0 {
                Button(action: { showInsightsPopover.toggle() }) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.orange)

                        Text("\(ambientService.activeInsightCount)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.orange)
                            .clipShape(Capsule())
                            .offset(x: 8, y: -6)
                    }
                }
                .buttonStyle(.plain)
                .help("\(ambientService.activeInsightCount) ambient insight\(ambientService.activeInsightCount == 1 ? "" : "s")")
                .popover(isPresented: $showInsightsPopover) {
                    AmbientInsightsPopover(ambientService: ambientService, onAskGRump: { prompt in
                        showInsightsPopover = false
                        viewModel.userInput = prompt
                    })
                }
            } else if ambientService.isAnalyzing {
                ProgressView()
                    .controlSize(.small)
                    .help("Analyzing project…")
            }

            // Timeline toggle
            if !viewModel.activeToolCalls.isEmpty || showTimeline {
                Button(action: { withAnimation(.easeInOut(duration: Anim.quick)) { showTimeline.toggle() } }) {
                    Image(systemName: showTimeline ? "list.bullet" : "chart.bar.xaxis")
                        .font(Typography.bodySmall)
                        .foregroundColor(showTimeline ? themeManager.palette.effectiveAccent : themeManager.palette.textMuted)
                }
                .buttonStyle(.plain)
                .help(showTimeline ? "Show messages" : "Show timeline")
            }

            modelPickerMenu
        }
        .padding(.horizontal, Spacing.massive)
        .padding(.vertical, Spacing.xxl)
        .background(themeManager.palette.bgCard)
        .overlay(Rectangle().frame(height: Border.thin).foregroundColor(themeManager.palette.borderCrisp), alignment: .bottom)
    }

    private var loadingControls: some View {
        AgentProgressRing(
            step: viewModel.currentAgentStep,
            maxStep: viewModel.currentAgentStepMax
        )
        .help({
            if let step = viewModel.currentAgentStep, let max = viewModel.currentAgentStepMax, max > 1 {
                return "Step \(step) of \(max)"
            }
            return "Thinking\u{2026}"
        }())
    }

    private var pausedControls: some View {
        HStack(spacing: Spacing.lg) {
            Text("Paused")
                .font(Typography.captionSmallMedium)
                .foregroundColor(.textMuted)

            Button(action: { viewModel.resumeAgent() }) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "play.fill")
                        .font(Typography.captionSmallSemibold)
                    Text("Resume")
                        .font(Typography.captionSmallSemibold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, 5)
                .background(themeManager.palette.effectiveAccent)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Resume agent")
        }
    }

    private var modelPickerMenu: some View {
        Menu {
            // One section per provider that has models in the catalog.
            ForEach(AIProvider.allCases) { provider in
                providerSection(provider: provider, icon: provider.iconName)
            }

            Divider()
            Button {
                settingsInitialTab = .providers
                showSettings = true
            } label: {
                Label("All models & settings\u{2026}", systemImage: "gearshape")
            }
        } label: {
            modelPickerLabel
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Switch model")
    }

    @ViewBuilder
    private func providerSection(provider: AIProvider, icon: String) -> some View {
        let models = viewModel.modelsForProvider(provider)
        if !models.isEmpty {
            Section(provider.displayName) {
                ForEach(models) { model in
                    Button {
                        viewModel.selectProviderAndModel(provider: provider, model: model)
                    } label: {
                        HStack {
                            Text(model.displayName)
                            if model.id == viewModel.currentEnhancedModel?.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        }
    }

    // Connection status dot color
    private var connectionStatusColor: Color {
        if viewModel.isLoading { return .orange }
        if viewModel.errorMessage != nil { return .red }
        return .accentGreen
    }

    private var modelPickerLabel: some View {
        HStack(spacing: 5) {
            Image(systemName: isLocalProvider ? "desktopcomputer" : "sparkles")
                .font(Typography.sparkleIcon)
                .foregroundColor(themeManager.palette.effectiveAccentLightVariant)
            Text(viewModel.currentEnhancedModel?.displayName ?? viewModel.effectiveModel.displayName)
                .font(Typography.captionSmallSemibold)
                .foregroundColor(.textSecondary)
            if isLocalProvider {
                Text("LOCAL")
                    .font(Typography.micro)
                    .foregroundColor(.accentGreen)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.accentGreen.opacity(0.15))
                    .clipShape(Capsule())
            }
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.textMuted)
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, 6)
        .background(themeManager.palette.bgElevated)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(themeManager.palette.borderCrisp, lineWidth: Border.thin))
    }

    // MARK: - Model Mode Picker

}

// MARK: - Connection Status Dot

struct ConnectionStatusDot: View {
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject var viewModel: ChatViewModel
    @ObservedObject private var connectionMonitor = ConnectionMonitor.shared

    private var statusColor: Color {
        if !connectionMonitor.isConnected { return .red }
        if case .degraded = connectionMonitor.status { return .orange }
        if viewModel.isLoading { return .orange }
        if viewModel.errorMessage != nil { return .red }
        return .accentGreen
    }

    private var statusLabel: String {
        if !connectionMonitor.isConnected { return "Offline" }
        if case .degraded(let reason) = connectionMonitor.status { return "Degraded: \(reason)" }
        if viewModel.isLoading { return "Active" }
        if viewModel.errorMessage != nil { return "Error" }
        return "Connected"
    }

    private var latencyText: String? {
        guard let latency = connectionMonitor.lastLatency else { return nil }
        return "\(Int(latency * 1000))ms"
    }

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            Text(statusLabel)
                .font(Typography.micro)
                .foregroundColor(themeManager.palette.textMuted)
            if let latency = latencyText, connectionMonitor.isConnected {
                Text(latency)
                    .font(Typography.micro)
                    .foregroundColor(themeManager.palette.textMuted.opacity(0.7))
            }
        }
        .help("Connection status: \(statusLabel)")
        .onAppear { connectionMonitor.start() }
    }
}
