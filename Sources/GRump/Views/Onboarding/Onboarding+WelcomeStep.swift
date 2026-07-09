// MARK: - Onboarding Step 1: Welcome
//
// Pure brand + privacy consent. Key entry lives in the provider step.

import SwiftUI

extension OnboardingView {

    // MARK: - Step 1: Welcome

    var stepWelcome: some View {
        VStack(spacing: Spacing.giant) {
            FrownyFaceLogo(size: 64)
                .shadow(color: themeManager.palette.effectiveAccent.opacity(0.3), radius: 16, y: 6)

            VStack(spacing: Spacing.lg) {
                Text("Welcome to G-Rump")
                    .font(Typography.displayMedium)
                    .foregroundColor(themeManager.palette.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Your autonomous AI coding agent.\nGrumpy by design.")
                    .font(Typography.body)
                    .foregroundColor(themeManager.palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .frame(maxWidth: 480)
            }

            // Privacy consent — gates the Next button (see OnboardingStep.canAdvance).
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
    }
}
