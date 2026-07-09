// MARK: - Onboarding Step 2: Provider + API Key
//
// Provider card grid (all four providers), API key entry with inline
// validation, and an explicit "add a key later" deferral — the only
// honest way past this step without a key.

import SwiftUI

extension OnboardingView {

    // MARK: - Step 2: Provider + Key

    var stepProviderKey: some View {
        VStack(spacing: Spacing.giant) {
            VStack(spacing: Spacing.lg) {
                Image(systemName: "key.horizontal")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(themeManager.palette.effectiveAccent)

                Text("Connect a provider")
                    .font(Typography.displayMedium)
                    .foregroundColor(themeManager.palette.textPrimary)

                Text("Bring your own key. It's stored in the Keychain and never leaves this Mac except to call the provider.")
                    .font(Typography.bodySmall)
                    .foregroundColor(themeManager.palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.md) {
                ForEach(AIProvider.allCases) { provider in
                    onboardingProviderCard(provider)
                }
            }
            .frame(maxWidth: 440)

            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack {
                    Text("\(selectedOnboardingProvider.displayName) API Key")
                        .font(Typography.captionSemibold)
                        .foregroundColor(themeManager.palette.textMuted)
                    Spacer()
                    if let url = selectedOnboardingProvider.keyConsoleURL {
                        Link("Get a key", destination: url)
                            .font(Typography.captionSmallMedium)
                            .foregroundColor(themeManager.palette.effectiveAccent)
                    }
                }

                HStack(spacing: Spacing.md) {
                    SecureField(selectedOnboardingProvider.keyPlaceholder, text: $apiKeyInput)
                        .textFieldStyle(.plain)
                        .font(Typography.bodySmall)
                        .padding(Spacing.lg)
                        .background(themeManager.palette.bgInput)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .stroke(themeManager.palette.borderCrisp, lineWidth: Border.thin))
                        .onSubmit { saveProviderKey() }

                    Button("Validate") {
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

                if hasSavedKey && keyValidationState == .idle {
                    Text("A provider is already configured. You're set — or save a new key above.")
                        .font(Typography.captionSmall)
                        .foregroundColor(themeManager.palette.textMuted)
                }
            }
            .frame(maxWidth: 440)

            // The only honest skip: an explicit deferral, not a silent "Skip for now".
            if !hasSavedKey {
                if keyEntryDeferred {
                    Text("No key yet — add one anytime in Settings → AI. G-Rump can't chat until you do.")
                        .font(Typography.captionSmall)
                        .foregroundColor(themeManager.palette.textMuted)
                        .frame(maxWidth: 440)
                } else {
                    Button("I'll add a key later") {
                        keyEntryDeferred = true
                    }
                    .font(Typography.bodySmallMedium)
                    .foregroundColor(themeManager.palette.textMuted)
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, Spacing.huge)
    }

    // MARK: - Provider Card

    func onboardingProviderCard(_ provider: AIProvider) -> some View {
        let isSelected = selectedOnboardingProvider == provider
        return Button {
            withAnimation(.easeInOut(duration: Anim.quick)) {
                selectedOnboardingProvider = provider
                apiKeyInput = ""
                keyValidationState = .idle
            }
        } label: {
            VStack(spacing: Spacing.md) {
                Image(systemName: provider.iconName)
                    .font(.system(size: 20, weight: .semibold))
                Text(provider.displayName)
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
        .accessibilityLabel("\(provider.displayName) provider")
        .accessibilityHint(provider.description)
    }

    // MARK: - Key Save + Probe

    func saveProviderKey() {
        let key = apiKeyInput.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return }
        let provider = selectedOnboardingProvider
        let config = ProviderConfiguration(provider: provider, apiKey: key)
        AIModelRegistry.shared.setProviderConfig(config)
        viewModel.selectProvider(provider)
        viewModel.apiKey = key
        hasSavedKey = true

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
