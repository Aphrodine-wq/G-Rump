// MARK: - Onboarding Step 3: Model Selection
//
// Model picker with enhanced model cards and provider section headers,
// driven by the provider chosen on the previous step.

import SwiftUI

extension OnboardingView {

    // MARK: - Step 2: Model Selection

    var stepModelSelection: some View {
        VStack(spacing: Spacing.giant) {
            VStack(spacing: Spacing.lg) {
                Image(systemName: "cpu")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(themeManager.palette.effectiveAccent)

                Text("Choose your model")
                    .font(Typography.displayMedium)
                    .foregroundColor(themeManager.palette.textPrimary)

                Text("Pick a default model. You can change this anytime.")
                    .font(Typography.bodySmall)
                    .foregroundColor(themeManager.palette.textSecondary)
                    .multilineTextAlignment(.center)
            }

            ScrollView {
                LazyVStack(spacing: Spacing.md) {
                    // Models for the provider chosen on the welcome step.
                    let providerModels = AIModelRegistry.shared.getModels(for: selectedOnboardingProvider)

                    if !providerModels.isEmpty {
                        providerSectionHeader(selectedOnboardingProvider.displayName,
                                              icon: providerIconName(selectedOnboardingProvider))
                        ForEach(providerModels, id: \.id) { model in
                            enhancedModelCard(model)
                        }
                    }
                }
                .padding(.horizontal, Spacing.huge)
            }
            .frame(maxHeight: 380)
        }
        .padding(.horizontal, Spacing.huge)
    }

    func providerIconName(_ provider: AIProvider) -> String {
        provider.iconName
    }

    func enhancedModelCard(_ model: EnhancedAIModel) -> some View {
        let isSelected = viewModel.currentEnhancedModel?.id == model.id
        return Button {
            viewModel.selectProviderAndModel(provider: model.provider, model: model)
        } label: {
            HStack(spacing: Spacing.xl) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(model.displayName)
                        .font(Typography.bodySemibold)
                        .foregroundColor(themeManager.palette.textPrimary)
                    Text(model.description)
                        .font(Typography.captionSmall)
                        .foregroundColor(themeManager.palette.textMuted)
                        .lineLimit(1)
                }
                Spacer()
                Text("\(model.contextWindow / 1000)K")
                    .font(Typography.captionSmallSemibold)
                    .foregroundColor(themeManager.palette.textMuted)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(themeManager.palette.effectiveAccent)
                }
            }
            .padding(Spacing.xl)
            .background(isSelected
                        ? themeManager.palette.effectiveAccent.opacity(0.1)
                        : themeManager.palette.bgCard.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .stroke(isSelected ? themeManager.palette.effectiveAccent.opacity(0.5) : themeManager.palette.borderCrisp.opacity(0.3), lineWidth: isSelected ? 2 : 1))
        }
        .buttonStyle(.plain)
    }

    func providerSectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(themeManager.palette.effectiveAccent)
            Text(title)
                .font(Typography.captionSemibold)
                .foregroundColor(themeManager.palette.textSecondary)
                .textCase(.uppercase)
                .tracking(0.4)
            Spacer()
        }
        .padding(.top, Spacing.lg)
    }

}
