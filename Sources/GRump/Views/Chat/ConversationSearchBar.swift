import SwiftUI

/// Inline search bar for finding text within the current conversation.
/// Activated by Cmd+F. Shows match count and prev/next navigation.
struct ConversationSearchBar: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var viewModel: ChatViewModel
    @FocusState private var isFocused: Bool

    var body: some View {
        if viewModel.conversationSearchVisible {
            HStack(spacing: Spacing.md) {
                // Search icon
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(themeManager.palette.textMuted)

                // Text field
                TextField("Search conversation...", text: $viewModel.conversationSearchText)
                    .font(Typography.captionSmallMedium)
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .onSubmit {
                        // Could navigate to next match
                    }

                // Match count
                if !viewModel.conversationSearchText.isEmpty {
                    let count = matchCount
                    Text("\(count) match\(count == 1 ? "" : "es")")
                        .font(Typography.micro)
                        .foregroundColor(count > 0 ? themeManager.palette.textMuted : .red.opacity(0.7))
                }

                Spacer()

                // Close button
                Button(action: {
                    viewModel.conversationSearchVisible = false
                    viewModel.conversationSearchText = ""
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(themeManager.palette.textMuted)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, Spacing.xxl)
            .padding(.vertical, Spacing.md)
            .background(themeManager.palette.bgElevated)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(themeManager.palette.borderSubtle)
                    .frame(height: Border.thin)
            }
            .transition(.asymmetric(
                insertion: .move(edge: .top).combined(with: .opacity),
                removal: .opacity
            ))
            .onAppear { isFocused = true }
            .onReceive(NotificationCenter.default.publisher(for: .init("GRumpToggleConversationSearch"))) { _ in
                withAnimation(.easeInOut(duration: Anim.quick)) {
                    if viewModel.conversationSearchVisible {
                        viewModel.conversationSearchVisible = false
                        viewModel.conversationSearchText = ""
                    } else {
                        viewModel.conversationSearchVisible = true
                    }
                }
            }
        }
    }

    private var matchCount: Int {
        let query = viewModel.conversationSearchText.lowercased()
        guard !query.isEmpty else { return 0 }
        return viewModel.filteredMessages.reduce(0) { count, msg in
            count + msg.content.lowercased().components(separatedBy: query).count - 1
        }
    }
}
