// MARK: - OnboardingView
//
// Six-step onboarding flow shown before the main app.
// Each step's UI lives in a focused extension file:
//   • Onboarding+WelcomeStep.swift     – brand + privacy consent
//   • Onboarding+ProviderStep.swift    – provider picker, API key entry + validation
//   • Onboarding+ModelStep.swift       – model selection cards
//   • Onboarding+SkillsStep.swift      – skill-pack toggle grid
//   • Onboarding+AppearanceStep.swift  – theme / accent picker
//   • Onboarding+SecurityStep.swift    – exec-approval presets

import SwiftUI

// MARK: - Onboarding Steps

enum OnboardingStep: Int, CaseIterable, Equatable {
    case welcome
    case provider
    case model
    case skills
    case appearance
    case security

    var isLast: Bool { self == Self.allCases.last }
    var next: OnboardingStep? { OnboardingStep(rawValue: rawValue + 1) }
    var previous: OnboardingStep? { OnboardingStep(rawValue: rawValue - 1) }

    /// Pure gating rule: can the user move past `step`?
    /// - welcome requires the privacy consent checkbox.
    /// - provider requires a saved key OR an explicit "add a key later" deferral —
    ///   probe outcome never gates (keys save first; invalid/indeterminate warn).
    /// - every later step is informational and always passable.
    static func canAdvance(
        from step: OnboardingStep,
        consentGiven: Bool,
        hasSavedKey: Bool,
        keyEntryDeferred: Bool
    ) -> Bool {
        switch step {
        case .welcome: return consentGiven
        case .provider: return hasSavedKey || keyEntryDeferred
        case .model, .skills, .appearance, .security: return true
        }
    }
}

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var viewModel: ChatViewModel

    // MARK: - State (internal so extensions can access)

    @State var currentStep: OnboardingStep = .welcome
    @State var direction: Edge = .trailing

    // Provider step
    @State var selectedOnboardingProvider: AIProvider = .anthropic
    @State var apiKeyInput = ""
    @State var keyValidationState: KeyValidationState = .idle
    @State var hasSavedKey = false
    @State var keyEntryDeferred = false

    // Skills step — ios-dev + code-quality preselected; applied ONCE at completion.
    @State var selectedSkillPacks: Set<String> = ["ios-dev", "code-quality"]
    @State var showAllSkillPacks = false

    @State var selectedSecurityPreset: ExecSecurityPreset = .balanced
    @AppStorage("PrivacyConsentGiven") var privacyConsentGiven = false

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
                    case .welcome: stepWelcome
                    case .provider: stepProviderKey
                    case .model: stepModelSelection
                    case .skills: stepSkillsQuickStart
                    case .appearance: stepThemeAppearance
                    case .security: stepSecurityPermissions
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
        .onAppear {
            // Restart-onboarding round trip: an already-configured provider counts
            // as a saved key so the provider step doesn't demand re-entry.
            if viewModel.isAIProviderConfigured {
                hasSavedKey = true
            }
        }
    }

    // MARK: - Step Indicator

    private var stepIndicator: some View {
        HStack(spacing: Spacing.lg) {
            ForEach(OnboardingStep.allCases, id: \.self) { step in
                Capsule()
                    .fill(step.rawValue <= currentStep.rawValue
                          ? themeManager.palette.effectiveAccent
                          : themeManager.palette.borderCrisp.opacity(0.3))
                    .frame(width: step == currentStep ? 28 : 8, height: 8)
                    .animation(.easeInOut(duration: Anim.quick), value: currentStep)
            }
        }
    }

    // MARK: - Navigation Buttons

    private var canAdvanceFromCurrentStep: Bool {
        OnboardingStep.canAdvance(
            from: currentStep,
            consentGiven: privacyConsentGiven,
            hasSavedKey: hasSavedKey,
            keyEntryDeferred: keyEntryDeferred
        )
    }

    private var navigationButtons: some View {
        HStack {
            if let previous = currentStep.previous {
                Button {
                    direction = .leading
                    withAnimation { currentStep = previous }
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

            Button {
                if let next = currentStep.next {
                    direction = .trailing
                    withAnimation { currentStep = next }
                } else {
                    completeOnboarding()
                }
            } label: {
                Text(currentStep.isLast ? "Get started" : "Next")
                    .font(Typography.bodySemibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, Spacing.colossal)
                    .padding(.vertical, Spacing.xl)
                    .background(themeManager.palette.effectiveAccent
                        .opacity(canAdvanceFromCurrentStep ? 1 : 0.35))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!canAdvanceFromCurrentStep)
        }
    }

    // MARK: - Completion

    /// Applies the selected skill packs exactly once, as a UNION into whatever
    /// allowlist already exists — selecting nothing changes nothing. Onboarding
    /// must never wipe a returning user's allowlist.
    func completeOnboarding() {
        let existing = SkillsSettingsStorage.loadAllowlist()
        let merged = SkillPack.mergedAllowlist(
            selecting: selectedSkillPacks,
            into: existing,
            packs: SkillPack.builtInPacks
        )
        if merged != existing {
            SkillsSettingsStorage.saveAllowlist(merged)
        }
        hasCompletedOnboarding = true
    }
}
