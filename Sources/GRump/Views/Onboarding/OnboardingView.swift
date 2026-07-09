// MARK: - OnboardingView
//
// Six-step onboarding flow shown before the main app.
// Each step's UI lives in a focused extension file:
//   • Onboarding+WelcomeStep.swift     – auth, provider picker, API key
//   • Onboarding+ModelStep.swift       – model selection cards
//   • Onboarding+AppearanceStep.swift  – theme / accent picker
//   • Onboarding+WorkspaceStep.swift   – folder picker, tool detection
//   • Onboarding+SecurityStep.swift    – exec-approval presets
//   • Onboarding+SkillsStep.swift      – skill-pack toggle grid

import SwiftUI
import OSLog
#if os(macOS)
import AppKit
#endif

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var viewModel: ChatViewModel

    // MARK: - State (internal so extensions can access)

    @State var currentStep = 0
    @State var signInInProgress = false
    @State var signInError: String?
    @State var apiKeyInput = ""
    @State var showAPIKeyField = false
    @State var direction: Edge = .trailing
    @State var selectedOnboardingProvider: AIProvider = .anthropic

    let totalSteps = 6
    @State var selectedSecurityPreset: ExecSecurityPreset = .balanced
    @State var selectedSkillPacks: Set<String> = []
    @AppStorage("PrivacyConsentGiven") var privacyConsentGiven = false

    // Workspace step state
    @State var detectedTools: [(name: String, icon: String, found: Bool)] = []
    @State var toolDetectionDone = false
    @State var isInstallingTools = false
    @State var installToolsMessage: String?

    // MARK: - Body

    var body: some View {
        ZStack {
            themeManager.palette.bgDark
                .ignoresSafeArea()

            LinearGradient(
                colors: [
                    themeManager.palette.effectiveAccent.opacity(0.06),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                stepIndicator
                    .padding(.top, 64)

                Spacer(minLength: Spacing.huge)

                Group {
                    switch currentStep {
                    case 0: stepWelcomeAuth
                    case 1: stepModelSelection
                    case 2: stepThemeAppearance
                    case 3: stepWorkspace
                    case 4: stepSecurityPermissions
                    case 5: stepSkillsQuickStart
                    default: stepWelcomeAuth
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: direction).combined(with: .opacity),
                    removal: .move(edge: direction == .trailing ? .leading : .trailing).combined(with: .opacity)
                ))
                .id(currentStep)

                Spacer(minLength: Spacing.huge)

                navigationButtons
                    .padding(.horizontal, Spacing.colossal)
                    .padding(.bottom, Spacing.colossal)
            }
        }
        .animation(.easeInOut(duration: Anim.smooth), value: currentStep)
    }

    // MARK: - Step Indicator

    private var stepIndicator: some View {
        HStack(spacing: Spacing.lg) {
            ForEach(0..<totalSteps, id: \.self) { step in
                Capsule()
                    .fill(step <= currentStep
                          ? themeManager.palette.effectiveAccent
                          : themeManager.palette.borderCrisp.opacity(0.3))
                    .frame(width: step == currentStep ? 28 : 8, height: 8)
                    .animation(.easeInOut(duration: Anim.quick), value: currentStep)
            }
        }
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        HStack {
            if currentStep > 0 {
                Button {
                    direction = .leading
                    withAnimation { currentStep -= 1 }
                } label: {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Back")
                            .font(Typography.bodySemibold)
                    }
                    .foregroundColor(themeManager.palette.textSecondary)
                    .padding(.horizontal, Spacing.huge)
                    .padding(.vertical, Spacing.xl)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            if currentStep == 0 {
                Button {
                    direction = .trailing
                    withAnimation { currentStep += 1 }
                } label: {
                    Text("Skip for now")
                        .font(Typography.bodySmallMedium)
                        .foregroundColor(themeManager.palette.textMuted)
                }
                .buttonStyle(.plain)
                .padding(.trailing, Spacing.xl)
            }

            Button {
                if currentStep < totalSteps - 1 {
                    direction = .trailing
                    withAnimation { currentStep += 1 }
                } else {
                    hasCompletedOnboarding = true
                }
            } label: {
                Text(currentStep == totalSteps - 1 ? "Get started" : "Next")
                    .font(Typography.bodySemibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, Spacing.colossal)
                    .padding(.vertical, Spacing.xl)
                    .background(themeManager.palette.effectiveAccent)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    #if os(macOS)
    func runFolderPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select your project's root directory"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        viewModel.setWorkingDirectory(url.path)
    }
    #endif
}
