import SwiftUI

// MARK: - Behavior Settings Tab View
// Contains: behaviorSection (System Prompt, Agent, Input)
// Extracted from Settings+TabViews.swift for maintainability.

extension SettingsView {

    // MARK: - Behavior (System Prompt + Agent)

    var behaviorSection: some View {
        VStack(alignment: .leading, spacing: Spacing.huge) {
            settingsCard {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    HStack {
                        sectionTitle("System Prompt", icon: "text.bubble.fill", accent: themeManager.accentColor)
                        Spacer()
                        Button("Reset to Default") {
                            systemPrompt = GRumpDefaults.defaultSystemPrompt
                        }
                        .font(Typography.captionSmall)
                        .foregroundColor(themeManager.palette.effectiveAccentLightVariant)
                    }

                    TextEditor(text: $systemPrompt)
                    .font(Typography.code)
                    .frame(minHeight: 160)
                    .foregroundColor(.textPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(Spacing.xl)
                    .background(themeManager.palette.bgInput)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .stroke(themeManager.palette.borderCrisp, lineWidth: Border.thin))
                }
            }
            settingsCard {
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    sectionTitle("Agent", icon: "gearshape.2.fill", accent: themeManager.accentColor)
                    Text("Maximum number of agent steps (tool + reply cycles) per turn. Higher values allow longer autonomous runs.")
                        .font(Typography.bodySmall)
                        .foregroundColor(.textMuted)
                    HStack(spacing: Spacing.xl) {
                        Text("Max agent steps")
                            .font(Typography.bodySmallMedium)
                            .foregroundColor(.textPrimary)
                        Stepper(value: $maxAgentStepsStorage, in: 5...1000, step: 5) {
                            Text("\(maxAgentStepsStorage)")
                                .font(Typography.bodySmall)
                                .foregroundColor(.textSecondary)
                                .frame(minWidth: 28, alignment: .trailing)
                        }
                        .onChange(of: maxAgentStepsStorage) { _, v in
                            maxAgentStepsStorage = min(1000, max(5, v))
                        }
                        .onAppear {
                            if maxAgentStepsStorage < 5 || maxAgentStepsStorage > 1000 {
                                maxAgentStepsStorage = 200
                            }
                        }
                    }
                }
            }
            settingsCard {
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    sectionTitle("Verification", icon: "checkmark.shield.fill", accent: themeManager.accentColor)
                    Toggle("Auto-verify after edits", isOn: $autoVerifyEnabledSetting)
                    Text("When the agent finishes a run that changed code, build the project automatically and send failures back for fixing (max 3 cycles). Per-project override: autoVerify in .grump/config.json.")
                        .font(Typography.bodySmall)
                        .foregroundColor(.textMuted)
                    Toggle("Run tests during auto-verify", isOn: $autoVerifyRunTestsSetting)
                        .disabled(!autoVerifyEnabledSetting)
                    Text("Only runs when the project sets testCommand in .grump/config.json — large suites stay your call.")
                        .font(Typography.bodySmall)
                        .foregroundColor(.textMuted)
                    Toggle("Completion check", isOn: $completionGateEnabledSetting)
                    Text("Before accepting a run as done, a fast model checks the original request was fully satisfied (open plan steps block completion). Fails open — it never traps a finished run.")
                        .font(Typography.bodySmall)
                        .foregroundColor(.textMuted)
                }
            }
            settingsCard {
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    sectionTitle("Input", icon: "keyboard", accent: themeManager.accentColor)
                    Toggle("Return to send", isOn: $returnToSendSetting)
                    Text(returnToSendSetting
                         ? "Press Return to send a message. Shift+Return for a new line."
                         : "Press ⌘Return to send a message. Return for a new line.")
                        .font(Typography.captionSmall)
                        .foregroundColor(.textMuted)
                }
            }
        }
    }
}
