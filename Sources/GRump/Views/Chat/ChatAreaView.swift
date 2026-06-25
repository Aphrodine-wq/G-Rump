import SwiftUI

// MARK: - Chat Area View
struct ChatAreaView: View {
    @EnvironmentObject var viewModel: ChatViewModel
    @EnvironmentObject var themeManager: ThemeManager
    @Binding var showTimeline: Bool
    @Binding var showQuestionSuggestions: Bool
    @Binding var suggestedQuestions: [String]
    @Binding var showSettings: Bool
    @Binding var settingsInitialTab: SettingsTab?
    var onPromptSelected: (String) -> Void = { _ in }

    var body: some View {
        chatContentArea
    }

    // MARK: - Chat Content Area

    @ViewBuilder
    private var chatContentArea: some View {
        if !viewModel.canUseAI {
            onboardingEmptyState
        } else if viewModel.currentConversation == nil {
            noSelectionEmptyState
        } else if viewModel.messages.isEmpty && viewModel.streamingContent.isEmpty {
            emptyStateView
        } else if showTimeline {
            AgentTimelineView(
                toolCalls: viewModel.activeToolCalls,
                messages: viewModel.filteredMessages,
                onSelectMessage: { _ in
                    showTimeline = false
                }
            )
        } else {
            MessageListView()
        }
    }

    // MARK: - Empty States

    private var onboardingEmptyState: some View {
        EmptyStateViews.onboardingEmptyState(
            themeManager: themeManager,
            showSettings: $showSettings,
            settingsInitialTab: $settingsInitialTab
        )
    }

    private var noSelectionEmptyState: some View {
        EmptyStateViews.noSelectionEmptyState(
            viewModel: viewModel,
            themeManager: themeManager
        )
    }

    private var emptyStateView: some View {
        EmptyStateViews.emptyStateView(
            themeManager: themeManager,
            showQuestionSuggestions: $showQuestionSuggestions,
            suggestedQuestions: $suggestedQuestions,
            onPromptSelected: onPromptSelected
        )
    }
}
