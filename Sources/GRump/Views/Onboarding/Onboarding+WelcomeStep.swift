// MARK: - Onboarding Step 1: Welcome + Auth
//
// Contains the welcome screen, email auth section, provider picker,
// API key input, and privacy consent toggle.

import SwiftUI

extension OnboardingView {

    // MARK: - Step 1: Welcome + Auth

    var stepWelcomeAuth: some View {
        GeometryReader { geo in
        ScrollView(.vertical, showsIndicators: false) {
        VStack(spacing: Spacing.giant) {
            FrownyFaceLogo(size: 64)
                .shadow(color: themeManager.palette.effectiveAccent.opacity(0.3), radius: 16, y: 6)

            VStack(spacing: Spacing.lg) {
                Text("Welcome to G-Rump")
                    .font(Typography.displayMedium)
                    .foregroundColor(themeManager.palette.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Your autonomous AI coding agent.\nConnect an API key to get started.")
                    .font(Typography.body)
                    .foregroundColor(themeManager.palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .frame(maxWidth: 480)
            }

            VStack(spacing: Spacing.xl) {
                // Key entry for the selected provider (Anthropic by default).
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("\(selectedOnboardingProvider.displayName) API Key")
                        .font(Typography.captionSemibold)
                        .foregroundColor(themeManager.palette.textMuted)
                    HStack(spacing: Spacing.md) {
                        SecureField(apiKeyPlaceholder(for: selectedOnboardingProvider), text: $apiKeyInput)
                            .textFieldStyle(.plain)
                            .font(Typography.bodySmall)
                            .padding(Spacing.lg)
                            .background(themeManager.palette.bgInput)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .stroke(themeManager.palette.borderCrisp, lineWidth: Border.thin))

                        Button("Save") {
                            saveProviderKey()
                        }
                        .font(Typography.bodySmallSemibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, Spacing.xl)
                        .padding(.vertical, Spacing.lg)
                        .background(themeManager.palette.effectiveAccent)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                        .buttonStyle(.plain)
                        .disabled(apiKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    }

                    KeyValidationFeedbackView(
                        state: keyValidationState,
                        providerName: selectedOnboardingProvider.displayName
                    )
                }
                .frame(maxWidth: 420)
            }

            // Privacy consent
            VStack(spacing: Spacing.md) {
                Toggle(isOn: $privacyConsentGiven) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("I understand that my messages will be sent to AI providers for processing")
                            .font(Typography.bodySmall)
                            .foregroundColor(themeManager.palette.textPrimary)
                        Text("Your data is not used for model training. See our privacy policy for details.")
                            .font(Typography.captionSmall)
                            .foregroundColor(themeManager.palette.textMuted)
                    }
                }
                .toggleStyle(.checkbox)
            }
            .frame(maxWidth: 480)
        }
        .padding(.horizontal, Spacing.huge)
        .frame(maxWidth: .infinity, minHeight: geo.size.height)
        }
        }
    }

    func onboardingProviderCard(_ provider: AIProvider, icon: String, name: String) -> some View {
        let isSelected = selectedOnboardingProvider == provider
        return Button {
            withAnimation(.easeInOut(duration: Anim.quick)) {
                selectedOnboardingProvider = provider
                apiKeyInput = ""
                keyValidationState = .idle
            }
        } label: {
            VStack(spacing: Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                Text(name)
                    .font(Typography.captionSmallSemibold)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .foregroundColor(isSelected ? themeManager.palette.effectiveAccent : themeManager.palette.textSecondary)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(isSelected ? themeManager.palette.effectiveAccent.opacity(0.12) : themeManager.palette.bgInput)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .stroke(isSelected ? themeManager.palette.effectiveAccent.opacity(0.5) : themeManager.palette.borderCrisp.opacity(0.3), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    func apiKeyPlaceholder(for provider: AIProvider) -> String {
        provider.keyPlaceholder
    }

    func saveProviderKey() {
        let key = apiKeyInput.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return }
        let provider = selectedOnboardingProvider
        let config = ProviderConfiguration(provider: provider, apiKey: key)
        AIModelRegistry.shared.setProviderConfig(config)
        viewModel.selectProvider(provider)
        viewModel.apiKey = key

        // Probe the saved key; drop the result if the user has switched
        // providers meanwhile (the feedback row is shared across cards).
        keyValidationState = .validating
        Task { @MainActor in
            let result = await AIKeyValidator.validate(provider: provider, apiKey: key)
            if selectedOnboardingProvider == provider {
                keyValidationState = .result(result)
            }
        }
    }
}
