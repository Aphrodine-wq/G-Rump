import SwiftUI

/// Settings → Brain. Generic, user-owned configuration for the cognitive brain
/// subsystems fused into G-Rump. Feature flags persist to `~/.grump/brain.json`.
struct BrainSettingsView: View {
    @EnvironmentObject var themeManager: ThemeManager
    let workingDirectory: String

    @StateObject private var model = BrainConfigModel()
    @State private var elevenLabsKey: String = ""
    @State private var keyStatus: String?
    @State private var eyesStatus: String?
    @State private var daemonStatus: String?
    @State private var mindContent: String = ""
    @State private var mindStatus: String?
    @ObservedObject private var awareness = AwarenessMonitor.shared

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.huge) {
            headerCard
            memoryCard
            voiceCard
            advancedCard
            mindCard
            vaultLocationCard
        }
        .onAppear {
            if mindContent.isEmpty {
                mindContent = MindStorage.rawContent(scope: .global) ?? MindStorage.defaultMindContent
            }
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(spacing: Spacing.lg) {
                Image(systemName: "brain.filled.head.profile")
                    .font(.system(size: 28))
                    .foregroundColor(themeManager.palette.effectiveAccent)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Brain")
                        .font(Typography.heading2)
                        .foregroundColor(.textPrimary)
                    Text("Persistent memory, voice, and autonomy — the agent's long-term brain.")
                        .font(Typography.bodySmall)
                        .foregroundColor(.textMuted)
                }
            }
            Text("These features give G-Rump a readable, linked memory vault, a voice, and (later) screen awareness and supervised autonomy. Anything that touches your screen or acts on its own is off by default and fully under your control.")
                .font(Typography.captionSmall)
                .foregroundColor(.textMuted)
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(themeManager.palette.bgInput)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - Memory

    private var memoryCard: some View {
        card(title: "Memory") {
            flagToggle(
                "Vault brain",
                subtitle: "Keep a readable markdown vault — daily notes, decisions, and linked notes — and recall it across sessions.",
                isOn: $model.config.vaultEnabled,
                available: true
            )
        }
    }

    // MARK: - Voice

    private var voiceCard: some View {
        card(title: "Voice") {
            flagToggle(
                "Text-to-speech",
                subtitle: "Speak assistant replies aloud using the native macOS voice (or ElevenLabs when configured).",
                isOn: $model.config.ttsEnabled,
                available: true
            )

            if model.config.ttsEnabled {
                Divider().background(themeManager.palette.borderCrisp)
                Toggle(isOn: $model.config.useElevenLabs) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Prefer ElevenLabs")
                            .font(Typography.bodySmallSemibold)
                            .foregroundColor(.textPrimary)
                        Text("Use ElevenLabs when an API key is stored in the Keychain. Falls back to the system voice automatically.")
                            .font(Typography.captionSmall)
                            .foregroundColor(.textMuted)
                    }
                }
                .toggleStyle(.switch)

                if model.config.useElevenLabs {
                    HStack(spacing: Spacing.md) {
                        SecureField("ElevenLabs API key", text: $elevenLabsKey)
                            .textFieldStyle(.roundedBorder)
                        Button("Save Key") { saveElevenLabsKey() }
                            .buttonStyle(.bordered)
                            .disabled(elevenLabsKey.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if let keyStatus {
                        Text(keyStatus)
                            .font(Typography.captionSmall)
                            .foregroundColor(.textMuted)
                    }
                }
            }
        }
        .onAppear {
            if KeychainStorage.get(account: model.config.elevenLabsKeychainKey)?.isEmpty == false {
                keyStatus = "A key is stored in the Keychain."
            }
        }
    }

    private func openScreenRecordingSettings() {
        #if os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }

    private func saveElevenLabsKey() {
        let trimmed = elevenLabsKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        KeychainStorage.set(account: model.config.elevenLabsKeychainKey, value: trimmed)
        elevenLabsKey = ""
        keyStatus = "Saved to Keychain."
    }

    // MARK: - Advanced (deferred phases)

    private var advancedCard: some View {
        card(title: "Perception & Autonomy") {
            flagToggle(
                "Screen awareness (Eyes)",
                subtitle: "Periodically perceive your screen to maintain context. Sensitive apps are skipped and secrets are redacted before anything is stored. Requires Screen Recording permission.",
                isOn: $model.config.eyesEnabled,
                available: true
            )
            .onChange(of: model.config.eyesEnabled) { _, on in
                Task { @MainActor in
                    if on {
                        if await EyesEngine.shared.permissionGranted() {
                            EyesEngine.shared.start()
                            eyesStatus = "Screen awareness active."
                        } else {
                            eyesStatus = "Screen Recording permission needed."
                        }
                    } else {
                        EyesEngine.shared.stop()
                        eyesStatus = nil
                    }
                }
            }
            if let eyesStatus {
                HStack(spacing: Spacing.md) {
                    Text(eyesStatus)
                        .font(Typography.captionSmall)
                        .foregroundColor(.textMuted)
                    if eyesStatus.contains("permission") {
                        Button("Open System Settings") { openScreenRecordingSettings() }
                            .font(Typography.captionSmall)
                    }
                }
            }
            Divider().background(themeManager.palette.borderCrisp)
            flagToggle(
                "Conscience gate",
                subtitle: "Run a deterministic, fail-closed safety check before mutating tools — refuses when a sensitive surface is on screen or an action targets a protected branch / secret path.",
                isOn: $model.config.conscienceEnabled,
                available: true
            )
            Divider().background(themeManager.palette.borderCrisp)
            flagToggle(
                "Autonomous daemon",
                subtitle: "Let G-Rump work on pending goals on its own — on a scratch branch, one at a time, when idle. Every write needs your approval. Requires the Conscience gate; toggle off to stop instantly.",
                isOn: $model.config.daemonEnabled,
                available: true
            )
            .onChange(of: model.config.daemonEnabled) { _, on in
                if on && !model.config.conscienceEnabled {
                    daemonStatus = "Enable the Conscience gate — the daemon stays read-only without it."
                } else {
                    daemonStatus = on ? "Daemon active: working pending goals when idle." : nil
                }
            }
            if let daemonStatus {
                Text(daemonStatus)
                    .font(Typography.captionSmall)
                    .foregroundColor(.textMuted)
            }
        }
    }

    // MARK: - Mind (MIND.md identity + Awareness)

    private var mindCard: some View {
        card(title: "Mind") {
            Text("MIND.md is your agent's persistent identity, values, and self-awareness — injected into every conversation, before the Soul. Global lives at ~/.grump/MIND.md.")
                .font(Typography.captionSmall)
                .foregroundColor(.textMuted)

            TextEditor(text: $mindContent)
                .font(Typography.code)
                .frame(minHeight: 200)
                .padding(Spacing.sm)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.standard, style: .continuous)
                        .stroke(themeManager.palette.borderCrisp, lineWidth: Border.thin)
                )
                .scrollContentBackground(.hidden)

            HStack(spacing: Spacing.lg) {
                Button("Save MIND.md") {
                    if MindStorage.saveMind(content: mindContent, scope: .global) {
                        mindStatus = "Saved."
                    } else {
                        mindStatus = "Save failed."
                    }
                }
                .buttonStyle(.borderedProminent)
                Button("Reset to Default") { mindContent = MindStorage.defaultMindContent }
                    .buttonStyle(.bordered)
                if let mindStatus {
                    Text(mindStatus).font(Typography.captionSmall).foregroundColor(.textMuted)
                }
            }

            Divider().background(themeManager.palette.borderCrisp)
            Text(awareness.summary)
                .font(Typography.captionSmall)
                .foregroundColor(.textMuted)
        }
    }

    // MARK: - Vault Location

    private var vaultLocationCard: some View {
        card(title: "Vault Location") {
            let root = BrainPaths.vaultRoot(workingDirectory: workingDirectory)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(root.path)
                    .font(Typography.code)
                    .foregroundColor(.textSecondary)
                    .textSelection(.enabled)
                Text("A project vault (\u{2039}project\u{203a}/.grump/vault) is used when present; otherwise the global vault above.")
                    .font(Typography.captionSmall)
                    .foregroundColor(.textMuted)
            }
        }
    }

    // MARK: - Reusable card + toggle

    @ViewBuilder
    private func card<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text(title)
                .font(Typography.captionSemibold)
                .foregroundColor(.textSecondary)
            content()
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(themeManager.palette.bgInput)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    @ViewBuilder
    private func flagToggle(_ title: String, subtitle: String, isOn: Binding<Bool>, available: Bool) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.sm) {
                    Text(title)
                        .font(Typography.bodySmallSemibold)
                        .foregroundColor(.textPrimary)
                    if !available {
                        Text("Coming soon")
                            .font(Typography.micro)
                            .foregroundColor(.textMuted)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, 2)
                            .background(themeManager.palette.bgDark)
                            .clipShape(Capsule())
                    }
                }
                Text(subtitle)
                    .font(Typography.captionSmall)
                    .foregroundColor(.textMuted)
            }
        }
        .toggleStyle(.switch)
        .disabled(!available)
    }
}
