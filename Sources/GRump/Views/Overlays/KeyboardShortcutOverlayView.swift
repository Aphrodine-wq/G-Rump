import SwiftUI

// MARK: - Keyboard Shortcut Overlay View
struct KeyboardShortcutOverlayView: View {
    @EnvironmentObject var viewModel: ChatViewModel
    @ObservedObject private var layoutOptions = LayoutOptions.shared
    @Binding var showSettings: Bool
    @Binding var sidebarCollapsed: Bool
    @Binding var selectedPanelRaw: String
    @Binding var rightPanelCollapsed: Bool
    @Binding var messageFieldFocused: Bool
    var onShowLayoutCustomizer: () -> Void = {}

    var body: some View {
        Group {
            Button(action: { viewModel.createNewConversation() }) { EmptyView() }
                .keyboardShortcut("n", modifiers: .command)
            Button(action: { showSettings = true }) { EmptyView() }
                .keyboardShortcut(",", modifiers: .command)
            Button(action: { if viewModel.isLoading { viewModel.stopGeneration() } }) { EmptyView() }
                .keyboardShortcut(".", modifiers: .command)
            Button(action: { messageFieldFocused = true }) { EmptyView() }
                .keyboardShortcut("l", modifiers: .command)
            #if os(macOS)
            Button(action: {
                withAnimation(.easeInOut(duration: Anim.quick)) {
                    sidebarCollapsed.toggle()
                }
            }) { EmptyView() }
                .keyboardShortcut("\\", modifiers: .command)
            Button(action: { if viewModel.currentConversation != nil { viewModel.runExportMarkdownPanel(onlyCurrent: true) } }) { EmptyView() }
                .keyboardShortcut("e", modifiers: .command)

            // Zen Mode toggle (⌘⇧Z) — escape hatch
            Button(action: {
                withAnimation(.easeInOut(duration: Anim.quick)) {
                    layoutOptions.zenMode.toggle()
                }
            }) { EmptyView() }
                .keyboardShortcut("z", modifiers: [.command, .shift])

            // Escape exits Zen Mode
            Button(action: {
                if layoutOptions.zenMode {
                    withAnimation(.easeInOut(duration: Anim.quick)) {
                        layoutOptions.zenMode = false
                    }
                }
            }) { EmptyView() }
                .keyboardShortcut(.escape, modifiers: [])

            // Toggle Activity Bar (⌘⌥A)
            Button(action: {
                withAnimation(.easeInOut(duration: Anim.quick)) {
                    layoutOptions.activityBarVisible.toggle()
                }
            }) { EmptyView() }
                .keyboardShortcut("a", modifiers: [.command, .option])

            // Customize Layout (⌘⇧L)
            Button(action: onShowLayoutCustomizer) { EmptyView() }
                .keyboardShortcut("l", modifiers: [.command, .shift])

            // Panel tab shortcuts (Ctrl+number)
            Button(action: { switchPanel(.chat) }) { EmptyView() }
                .keyboardShortcut("1", modifiers: .control)
            Button(action: { switchPanel(.files) }) { EmptyView() }
                .keyboardShortcut("2", modifiers: .control)
            Button(action: { switchPanel(.preview) }) { EmptyView() }
                .keyboardShortcut("3", modifiers: .control)
            Button(action: { switchPanel(.simulator) }) { EmptyView() }
                .keyboardShortcut("4", modifiers: .control)
            Button(action: { switchPanel(.git) }) { EmptyView() }
                .keyboardShortcut("5", modifiers: .control)
            Button(action: { switchPanel(.tests) }) { EmptyView() }
                .keyboardShortcut("6", modifiers: .control)
            Button(action: { switchPanel(.terminal) }) { EmptyView() }
                .keyboardShortcut("7", modifiers: .control)
            Button(action: { switchPanel(.spm) }) { EmptyView() }
                .keyboardShortcut("8", modifiers: .control)
            Button(action: { switchPanel(.docs) }) { EmptyView() }
                .keyboardShortcut("9", modifiers: .control)
            #endif
        }
        .frame(width: 0, height: 0)
        .opacity(0)
    }

    private func switchPanel(_ tab: PanelTab) {
        withAnimation(.easeInOut(duration: Anim.quick)) {
            if selectedPanelRaw == tab.rawValue && !rightPanelCollapsed {
                rightPanelCollapsed = true
            } else {
                selectedPanelRaw = tab.rawValue
                rightPanelCollapsed = false
            }
        }
    }
}
