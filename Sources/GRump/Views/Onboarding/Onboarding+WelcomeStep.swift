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

                Text("Your autonomous AI coding agent.\nSign in or connect a provider to get started.")
                    .font(Typography.body)
                    .foregroundColor(themeManager.palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .frame(maxWidth: 480)
            }

            // MARK: Sign In / Sign Up section
            if !authSuccess {
                emailAuthSection
            } else {
                HStack(spacing: Spacing.md) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentGreen)
                    Text("Signed in successfully")
                        .font(Typography.bodySemibold)
                        .foregroundColor(.accentGreen)
                }
                .padding(Spacing.lg)
                .frame(maxWidth: 420)
                .background(Color.accentGreen.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }

            // Divider with "or continue as guest"
            if !authSuccess {
                HStack(spacing: Spacing.lg) {
                    Rectangle()
                        .fill(themeManager.palette.borderCrisp.opacity(0.3))
                        .frame(height: 1)
                    Text("or continue as guest")
                        .font(Typography.captionSmall)
                        .foregroundColor(themeManager.palette.textMuted)
                        .layoutPriority(1)
                    Rectangle()
                        .fill(themeManager.palette.borderCrisp.opacity(0.3))
                        .frame(height: 1)
                }
                .frame(maxWidth: 420)
            }

            VStack(spacing: Spacing.xl) {
                // Qwen-only: enter the Qwen (DashScope) API key.
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("Qwen / DashScope API Key")
                        .font(Typography.captionSemibold)
                        .foregroundColor(themeManager.palette.textMuted)
                    HStack(spacing: Spacing.md) {
                        SecureField(apiKeyPlaceholder(for: .qwen), text: $apiKeyInput)
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

    // MARK: - Email Auth Section

    var emailAuthSection: some View {
        VStack(spacing: Spacing.xl) {
            // Sign In / Sign Up toggle
            HStack(spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: Anim.quick)) {
                        isSignUpMode = true
                        authError = nil
                    }
                } label: {
                    Text("Sign Up")
                        .font(Typography.bodySmallSemibold)
                        .foregroundColor(isSignUpMode ? themeManager.palette.effectiveAccent : themeManager.palette.textMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.lg)
                        .background(isSignUpMode ? themeManager.palette.effectiveAccent.opacity(0.12) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.easeInOut(duration: Anim.quick)) {
                        isSignUpMode = false
                        authError = nil
                    }
                } label: {
                    Text("Sign In")
                        .font(Typography.bodySmallSemibold)
                        .foregroundColor(!isSignUpMode ? themeManager.palette.effectiveAccent : themeManager.palette.textMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.lg)
                        .background(!isSignUpMode ? themeManager.palette.effectiveAccent.opacity(0.12) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .background(themeManager.palette.bgInput)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .stroke(themeManager.palette.borderCrisp.opacity(0.3), lineWidth: Border.thin))

            // Display name field (sign up only)
            if isSignUpMode {
                TextField("Display name (optional)", text: $authDisplayName)
                    .textFieldStyle(.plain)
                    .font(Typography.bodySmall)
                    .padding(Spacing.lg)
                    .background(themeManager.palette.bgInput)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .stroke(themeManager.palette.borderCrisp, lineWidth: Border.thin))
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Email field
            TextField("Email", text: $authEmail)
                .textFieldStyle(.plain)
                .font(Typography.bodySmall)
                .textContentType(.emailAddress)
                #if os(macOS)
                .disableAutocorrection(true)
                #else
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                #endif
                .padding(Spacing.lg)
                .background(themeManager.palette.bgInput)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .stroke(themeManager.palette.borderCrisp, lineWidth: Border.thin))

            // Password field
            SecureField("Password (8+ characters)", text: $authPassword)
                .textFieldStyle(.plain)
                .font(Typography.bodySmall)
                .textContentType(isSignUpMode ? .newPassword : .password)
                .padding(Spacing.lg)
                .background(themeManager.palette.bgInput)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .stroke(themeManager.palette.borderCrisp, lineWidth: Border.thin))

            // Error message
            if let error = authError {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .font(.system(size: 12))
                    Text(error)
                        .font(Typography.captionSmall)
                        .foregroundColor(.red)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
            }

            // Submit button
            Button {
                performEmailAuth()
            } label: {
                HStack(spacing: Spacing.md) {
                    if authInProgress {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    }
                    Text(isSignUpMode ? "Create Account" : "Sign In")
                        .font(Typography.bodySemibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.lg)
                .background(emailAuthButtonDisabled ? themeManager.palette.effectiveAccent.opacity(0.4) : themeManager.palette.effectiveAccent)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(emailAuthButtonDisabled)
        }
        .frame(maxWidth: 420)
        .animation(.easeInOut(duration: Anim.quick), value: isSignUpMode)
        .animation(.easeInOut(duration: Anim.quick), value: authError != nil)
    }

    var emailAuthButtonDisabled: Bool {
        authInProgress
        || authEmail.trimmingCharacters(in: .whitespaces).isEmpty
        || authPassword.isEmpty
        || authPassword.count < 8
    }

    func performEmailAuth() {
        let email = authEmail.trimmingCharacters(in: .whitespaces)
        let password = authPassword
        guard !email.isEmpty, password.count >= 8 else { return }

        authInProgress = true
        authError = nil

        Task {
            do {
                if isSignUpMode {
                    let displayName = authDisplayName.trimmingCharacters(in: .whitespaces)
                    let user = try await PlatformService.signUp(
                        email: email,
                        password: password,
                        displayName: displayName.isEmpty ? nil : displayName
                    )
                    await MainActor.run {
                        viewModel.platformUser = user
                        authSuccess = true
                        authInProgress = false
                        GRumpLogger.general.info("Onboarding sign-up completed")
                    }
                } else {
                    let user = try await PlatformService.signIn(email: email, password: password)
                    await MainActor.run {
                        viewModel.platformUser = user
                        authSuccess = true
                        authInProgress = false
                        GRumpLogger.general.info("Onboarding sign-in completed")
                    }
                }
            } catch {
                await MainActor.run {
                    authError = error.localizedDescription
                    authInProgress = false
                    GRumpLogger.general.error("Onboarding auth failed: \(error.localizedDescription)")
                }
            }
        }
    }

    func onboardingProviderCard(_ provider: AIProvider, icon: String, name: String) -> some View {
        let isSelected = selectedOnboardingProvider == provider
        return Button {
            withAnimation(.easeInOut(duration: Anim.quick)) {
                selectedOnboardingProvider = provider
                apiKeyInput = ""
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
        switch provider {
        case .qwen: return "sk-..."
        }
    }

    func saveProviderKey() {
        let key = apiKeyInput.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return }
        let config = ProviderConfiguration(provider: .qwen, apiKey: key)
        AIModelRegistry.shared.setProviderConfig(config)
        viewModel.selectProvider(.qwen)
        viewModel.apiKey = key
    }
}
