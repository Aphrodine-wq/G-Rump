import SwiftUI

// MARK: - Empty State Views
@MainActor
struct EmptyStateViews {

    // MARK: - No Selection Empty State

    static func noSelectionEmptyState(
        viewModel: ChatViewModel,
        themeManager: ThemeManager
    ) -> some View {
        let hasConversations = !viewModel.conversations.isEmpty
        return ScrollView {
            VStack(spacing: 0) {
                Spacer(minLength: 80)
                VStack(spacing: Spacing.giant) {
                    Image(systemName: hasConversations ? "bubble.left.and.bubble.right" : "square.and.pencil")
                        .font(Typography.emptyStateIcon)
                        .foregroundColor(themeManager.palette.effectiveAccent)
                    VStack(spacing: Spacing.md) {
                        Text(hasConversations ? "Select a conversation or start a new one" : "No conversations yet")
                            .font(Typography.displayMedium)
                            .foregroundColor(.textPrimary)
                            .multilineTextAlignment(.center)
                        Text("Press ⌘N to start a new chat.")
                            .font(Typography.body)
                            .foregroundColor(.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    Button(action: { viewModel.createNewConversation() }) {
                        HStack(spacing: Spacing.md) {
                            Image(systemName: "square.and.pencil")
                            Text("New Chat")
                                .font(Typography.bodySmallSemibold)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, Spacing.xxxl)
                        .padding(.vertical, Spacing.xl)
                        .background(
                            LinearGradient(
                                colors: [themeManager.palette.effectiveAccent, themeManager.palette.effectiveAccentDarkVariant],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("New chat")
                    .keyboardShortcut("n", modifiers: .command)
                }
                Spacer(minLength: 80)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(themeManager.palette.bgDark)
    }

    // MARK: - Onboarding Empty State

    static func onboardingEmptyState(
        themeManager: ThemeManager,
        showSettings: Binding<Bool>,
        settingsInitialTab: Binding<SettingsTab?>
    ) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer(minLength: 80)
                VStack(spacing: Spacing.giant) {
                    Image(systemName: "cpu")
                        .font(Typography.emptyStateIcon)
                        .foregroundColor(themeManager.palette.effectiveAccent)
                    VStack(spacing: Spacing.md) {
                        Text("Connect a provider")
                            .font(Typography.displayMedium)
                            .foregroundColor(.textPrimary)
                            .multilineTextAlignment(.center)
                        Text("Add an API key in Settings to get started.")
                            .font(Typography.body)
                            .foregroundColor(.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    Button(action: {
                        settingsInitialTab.wrappedValue = .providers
                        showSettings.wrappedValue = true
                    }) {
                        HStack(spacing: Spacing.md) {
                            Image(systemName: "gearshape")
                            Text("Open Providers")
                                .font(Typography.bodySmallSemibold)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, Spacing.xxxl)
                        .padding(.vertical, Spacing.xl)
                        .background(
                            LinearGradient(
                                colors: [themeManager.palette.effectiveAccent, themeManager.palette.effectiveAccentDarkVariant],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open provider settings")
                }
                Spacer(minLength: 80)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(themeManager.palette.bgDark)
    }

    // MARK: - Empty State View

    static func emptyStateView(
        themeManager: ThemeManager,
        showQuestionSuggestions: Binding<Bool>,
        suggestedQuestions: Binding<[String]>,
        onPromptSelected: @escaping (String) -> Void = { _ in }
    ) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer(minLength: 80)

                VStack(spacing: Spacing.massive) {
                    FrownyFaceLogo(size: 56)
                        .shadow(color: themeManager.palette.effectiveAccent.opacity(0.3), radius: 20, y: 8)
                        .modifier(FloatingAnimation())

                    VStack(spacing: Spacing.lg) {
                        Text("What can G-Rump help with?")
                            .font(Typography.displayMedium)
                            .foregroundColor(.textPrimary)

                        Text("Build features, debug code, refactor projects, and search the web — all autonomously.")
                            .font(Typography.body)
                            .foregroundColor(.textSecondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 420)
                    }

                    VStack(spacing: Spacing.lg) {
                        HStack(spacing: Spacing.lg) {
                            promptChip(icon: "hammer.fill", text: "Build a feature end-to-end", color: themeManager.palette.effectiveAccent, onTap: onPromptSelected)
                            promptChip(icon: "ant.fill", text: "Debug this error\u{2026}", color: Color(red: 1.0, green: 0.4, blue: 0.4), onTap: onPromptSelected)
                        }
                        HStack(spacing: Spacing.lg) {
                            promptChip(icon: "doc.text.fill", text: "Explain this code", color: Color(red: 0.2, green: 0.8, blue: 1.0), onTap: onPromptSelected)
                            promptChip(icon: "wand.and.stars", text: "Refactor this function", color: Color(red: 0.6, green: 0.4, blue: 1.0), onTap: onPromptSelected)
                        }
                    }

                    Button(action: {
                        showQuestionSuggestions.wrappedValue = true
                        suggestedQuestions.wrappedValue = [
                            "Build a SwiftUI view with...",
                            "Debug this error: ...",
                            "Explain how this code works...",
                            "Refactor this function to be more readable...",
                            "Add unit tests for this class...",
                            "Help me optimize this algorithm..."
                        ]
                    }) {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Suggest questions")
                                .font(Typography.bodySmallSemibold)
                        }
                        .foregroundColor(themeManager.palette.effectiveAccent)
                        .padding(.horizontal, Spacing.lg)
                        .padding(.vertical, Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .fill(themeManager.palette.effectiveAccent.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .stroke(themeManager.palette.effectiveAccent.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
                Spacer(minLength: 80)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(themeManager.palette.bgDark)
    }

    // MARK: - Helper Views

    @ViewBuilder
    private static func promptChip(icon: String, text: String, color: Color, onTap: @escaping (String) -> Void = { _ in }) -> some View {
        Button(action: {
            onTap(text)
        }) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(text)
                    .font(Typography.captionSmallMedium)
            }
            .foregroundColor(color)
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(color.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .stroke(color.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
}
