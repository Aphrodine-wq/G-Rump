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

    static func emptyStateView(themeManager: ThemeManager) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer(minLength: 80)

                VStack(spacing: Spacing.massive) {
                    FrownyFaceLogo(size: 56)
                        .shadow(color: themeManager.palette.effectiveAccent.opacity(0.3), radius: 20, y: 8)
                        .modifier(FloatingAnimation())

                    Text("What can G-Rump help with?")
                        .font(Typography.displayMedium)
                        .foregroundColor(.textPrimary)
                }
                Spacer(minLength: 80)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(themeManager.palette.bgDark)
    }
}
