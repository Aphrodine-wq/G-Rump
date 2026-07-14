import SwiftUI

// MARK: - Provider Tab Views
// Extracted from SettingsView.swift for maintainability.

extension SettingsView {

    // MARK: - Providers Section

    var providersSection: some View {
        let registry = AIModelRegistry.shared

        return HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                ForEach(AIProvider.allCases, id: \.rawValue) { provider in
                    providerListItem(provider, registry: registry)
                }
            }
            .frame(width: 180)
            .padding(.vertical, Spacing.lg)

            Rectangle()
                .fill(themeManager.palette.borderSubtle)
                .frame(width: 1)

            ScrollView {
                settingsCard {
                    // Detail pane for whichever provider is selected in the sidebar.
                    providerBlock(
                        provider: selectedProvider,
                        subtitle: selectedProvider.description,
                        registry: registry
                    ) {
                        ForEach(registry.getModels(for: selectedProvider), id: \.id) { model in
                            enhancedModelRow(model)
                        }
                    }
                }
                .padding(Spacing.lg)
            }
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            for provider in AIProvider.allCases {
                let config = registry.getProviderConfig(for: provider)
                providerAPIKeys[provider.rawValue] = config?.apiKey ?? ""
                providerBaseURLs[provider.rawValue] = config?.baseURL ?? provider.defaultBaseURL
            }
        }
    }

    func providerListItem(_ provider: AIProvider, registry: AIModelRegistry) -> some View {
        let isSelected = selectedProvider == provider
        let isConfigured = registry.isProviderConfigured(provider)

        return Button(action: { selectedProvider = provider }) {
            HStack(spacing: Spacing.lg) {
                Image(systemName: providerIcon(provider))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isSelected ? themeManager.palette.effectiveAccent : themeManager.palette.textMuted)
                    .frame(width: 22)

                Text(provider.displayName)
                    .font(isSelected ? Typography.bodySmallSemibold : Typography.bodySmall)
                    .foregroundColor(isSelected ? themeManager.palette.textPrimary : themeManager.palette.textSecondary)

                Spacer()

                if isConfigured {
                    Circle()
                        .fill(Color.accentGreen)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(isSelected ? themeManager.palette.effectiveAccent.opacity(0.10) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    func providerBlock<Content: View>(
        provider: AIProvider,
        subtitle: String,
        registry: AIModelRegistry,
        @ViewBuilder models: @escaping () -> Content
    ) -> some View {
        let isConfigured = registry.isProviderConfigured(provider)

        VStack(alignment: .leading, spacing: Spacing.xl) {
            HStack(spacing: Spacing.lg) {
                Image(systemName: providerIcon(provider))
                    .font(Typography.bodyMedium)
                    .foregroundColor(themeManager.palette.effectiveAccent)
                    .frame(width: 28, alignment: .center)

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack(spacing: Spacing.md) {
                        Text(provider.displayName)
                            .font(Typography.bodySemibold)
                            .foregroundColor(.textPrimary)
                        if isConfigured {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.accentGreen)
                        } else if provider.requiresAPIKey {
                            Text("Not configured")
                                .font(Typography.micro)
                                .foregroundColor(.textMuted)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(themeManager.palette.bgInput)
                                .clipShape(Capsule())
                        }
                    }
                    Text(subtitle)
                        .font(Typography.captionSmall)
                        .foregroundColor(.textMuted)
                }

                Spacer()
            }

            if provider.requiresAPIKey {
                Divider()
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("\(provider.displayName) API Key")
                        .font(Typography.captionSemibold)
                        .foregroundColor(.textSecondary)
                    HStack(spacing: Spacing.md) {
                        SecureField("Enter API key…", text: Binding(
                            get: { providerAPIKeys[provider.rawValue] ?? "" },
                            set: { providerAPIKeys[provider.rawValue] = $0 }
                        ))
                        .font(Typography.bodySmall)
                        .fontDesign(.monospaced)
                        .padding(Spacing.lg)
                        .background(themeManager.palette.bgInput)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .stroke(themeManager.palette.borderCrisp, lineWidth: Border.thin))

                        Button("Save") {
                            let key = providerAPIKeys[provider.rawValue] ?? ""
                            let baseURL = providerBaseURLs[provider.rawValue]
                            var config = ProviderConfiguration(provider: provider, apiKey: key, baseURL: baseURL)
                            config.isEnabled = true
                            registry.setProviderConfig(config)
                            validateSavedKey(for: provider, key: key, baseURL: baseURL)
                        }
                        .font(Typography.captionSmallSemibold)
                        .buttonStyle(.borderedProminent)
                        .tint(themeManager.palette.effectiveAccent)
                    }

                    KeyValidationFeedbackView(
                        state: providerKeyValidation[provider.rawValue] ?? .idle,
                        providerName: provider.displayName
                    )
                }
            } else if provider == .ollama {
                Divider()
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("Local Server")
                        .font(Typography.captionSemibold)
                        .foregroundColor(.textSecondary)
                    HStack(spacing: Spacing.md) {
                        ollamaStatusLabel(providerKeyValidation[provider.rawValue] ?? .idle)
                        Spacer()
                        Button("Refresh") { probeOllamaServer() }
                            .font(Typography.captionSmallSemibold)
                            .buttonStyle(.bordered)
                    }
                }
                .onAppear { probeOllamaServer() }
            }

            Divider()

            Text("Models")
                .font(Typography.captionSemibold)
                .foregroundColor(.textSecondary)

            models()
        }
    }

    func providerIcon(_ provider: AIProvider) -> String {
        provider.iconName
    }

    // MARK: - Ollama Reachability

    /// Probes the local Ollama server and refreshes its model list. Reuses the
    /// key-validation state slot — Ollama has no key, so the slot is free.
    func probeOllamaServer() {
        providerKeyValidation[AIProvider.ollama.rawValue] = .validating
        Task { @MainActor in
            if await MultiProviderAIService.shared.refreshOllamaModels() != nil {
                providerKeyValidation[AIProvider.ollama.rawValue] = .result(.valid)
            } else {
                providerKeyValidation[AIProvider.ollama.rawValue] = .result(.indeterminate("Not reachable"))
            }
        }
    }

    @ViewBuilder
    func ollamaStatusLabel(_ state: KeyValidationState) -> some View {
        switch state {
        case .idle, .validating:
            HStack(spacing: Spacing.sm) {
                ProgressView().scaleEffect(0.5).frame(width: 12, height: 12)
                Text("Checking for Ollama…")
                    .font(Typography.captionSmall)
                    .foregroundColor(.textMuted)
            }
        case .result(.valid):
            let count = AIModelRegistry.shared.getModels(for: .ollama).count
            HStack(spacing: Spacing.sm) {
                Circle().fill(Color.accentGreen).frame(width: 6, height: 6)
                Text(count == 1 ? "Ollama running — 1 model installed"
                                : "Ollama running — \(count) models installed")
                    .font(Typography.captionSmall)
                    .foregroundColor(.textSecondary)
            }
        case .result:
            HStack(spacing: Spacing.sm) {
                Circle().fill(Color.accentOrange).frame(width: 6, height: 6)
                Text("Not reachable — install Ollama or run `ollama serve`")
                    .font(Typography.captionSmall)
                    .foregroundColor(.textSecondary)
            }
        }
    }

    /// Probes the just-saved key and posts the outcome inline. The save has
    /// already happened — a failed probe warns, it never blocks or un-saves.
    func validateSavedKey(for provider: AIProvider, key: String, baseURL: String?) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            providerKeyValidation[provider.rawValue] = .idle
            return
        }
        providerKeyValidation[provider.rawValue] = .validating
        Task { @MainActor in
            let result = await AIKeyValidator.validate(provider: provider, apiKey: trimmed, baseURL: baseURL)
            providerKeyValidation[provider.rawValue] = .result(result)
        }
    }

    func enhancedModelRow(_ model: EnhancedAIModel) -> some View {
        HStack(spacing: Spacing.xxl) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.displayName)
                    .font(Typography.bodySmallMedium)
                    .foregroundColor(.textPrimary)
                HStack(spacing: Spacing.md) {
                    Text(model.description)
                        .font(Typography.captionSmall)
                        .foregroundColor(.textMuted)
                    Text("·")
                        .font(Typography.captionSmall)
                        .foregroundColor(.textMuted)
                    Text(formatContextWindow(model.contextWindow))
                        .font(Typography.captionSmall)
                        .foregroundColor(.textMuted)
                }
            }
            Spacer()
            if let pricing = model.pricing {
                Text("$\(String(format: "%.4f", pricing.inputPricePer1K))/1K")
                    .font(Typography.micro)
                    .foregroundColor(.textMuted)
            } else {
                Text("—")
                    .font(Typography.micro)
                    .foregroundColor(.textMuted)
            }
        }
        .padding(Spacing.lg)
        .background(themeManager.palette.bgInput)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .stroke(themeManager.palette.borderCrisp.opacity(0.3), lineWidth: Border.thin))
    }

}
