import SwiftUI
#if os(macOS)
import AppKit
import CoreSpotlight
#else
import UIKit
import CoreSpotlight
#endif

struct ContentView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var viewModel: ChatViewModel
    @EnvironmentObject var frameLoop: FrameLoopService
    @EnvironmentObject var ambientService: AmbientCodeAwarenessService
    @StateObject var state = ContentViewState()
    @FocusState var messageFieldFocused: Bool
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var body: some View {
        bodyContent
            .onChange(of: viewModel.workingDirectory) { _, newDir in
                ambientService.setWorkingDirectory(newDir)
                if !newDir.isEmpty {
                    state.lspService.start(workspaceRoot: newDir)
                }
            }
            .onAppear {
                if !viewModel.workingDirectory.isEmpty {
                    ambientService.setWorkingDirectory(viewModel.workingDirectory)
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        state.lspService.start(workspaceRoot: viewModel.workingDirectory)
                    }
                }
                // Index all conversations in Spotlight on launch (off main thread)
                let conversations = viewModel.conversations
                Task.detached(priority: .background) {
                    await SpotlightIndexer.shared.indexAllConversations(conversations)
                }
            }
            // Handoff: advertise current conversation activity
            .userActivity(GRumpActivityType.conversation) { activity in
                if let conv = viewModel.currentConversation {
                    let handoff = HandoffActivityBuilder.makeConversationActivity(
                        conversation: conv,
                        workingDirectory: viewModel.workingDirectory
                    )
                    activity.title = handoff.title
                    activity.isEligibleForHandoff = true
                    activity.isEligibleForSearch = true
                    activity.userInfo = handoff.userInfo
                    activity.requiredUserInfoKeys = handoff.requiredUserInfoKeys
                }
            }
            // Handle Spotlight search result / Handoff continuation
            .onContinueUserActivity(CSSearchableItemActionType) { activity in
                if let convId = SpotlightIndexer.conversationId(from: activity),
                   let conv = viewModel.conversations.first(where: { $0.id == convId }) {
                    viewModel.selectConversation(conv)
                }
            }
            .onContinueUserActivity(GRumpActivityType.conversation) { activity in
                if let convId = SpotlightIndexer.conversationId(from: activity),
                   let conv = viewModel.conversations.first(where: { $0.id == convId }) {
                    viewModel.selectConversation(conv)
                }
            }
            .onChange(of: state.lspService.diagnostics) { _, newDiags in
                viewModel.lspDiagnostics = newDiags
                viewModel.lspStatusMessage = state.lspService.statusMessage
            }

            #if os(macOS)
            .onReceive(NotificationCenter.default.publisher(for: .init("GRumpToggleActivityBar"))) { _ in
                withAnimation(.easeInOut(duration: Anim.quick)) {
                    state.layoutOptions.activityBarVisible.toggle()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .init("GRumpToggleStatusBar"))) { _ in
                withAnimation(.easeInOut(duration: Anim.quick)) {
                    state.layoutOptions.statusBarVisible.toggle()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .init("GRumpToggleZenMode"))) { _ in
                withAnimation(.easeInOut(duration: Anim.quick)) {
                    state.layoutOptions.zenMode.toggle()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .init("GRumpShowLayoutCustomizer"))) { _ in
                state.showLayoutCustomizer = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .init("GRumpResetLayout"))) { _ in
                withAnimation(.easeInOut(duration: Anim.quick)) {
                    state.layoutOptions.activityBarVisible = true
                    state.layoutOptions.primarySidebarVisible = true
                    state.layoutOptions.panelVisible = true
                    state.layoutOptions.statusBarVisible = true
                    state.layoutOptions.primarySidebarPosition = .right
                    state.layoutOptions.zenMode = false
                    state.layoutOptions.fullScreenMode = false
                    state.layoutOptions.centeredLayout = false
                }
                state.restoreFocus()
            }
            .onChange(of: state.layoutOptions.activityBarVisible) { _, _ in state.restoreFocus() }
            .onChange(of: state.layoutOptions.zenMode) { _, _ in state.restoreFocus() }
            .onChange(of: state.layoutOptions.primarySidebarVisible) { _, _ in state.restoreFocus() }
            .modifier(AppleIntegrationHandlers(viewModel: viewModel, state: state))
            #endif
    }

    private var messageFieldFocusedBinding: Binding<Bool> {
        Binding(
            get: { messageFieldFocused },
            set: { messageFieldFocused = $0 }
        )
    }

    private var bodyContent: some View {
        ModalManagerView(
            showProfile: $state.showProfile,
            showThreadNavigation: $state.showThreadNavigation,
            showSettings: $state.showSettings,
            settingsInitialTab: $state.settingsInitialTab,
            messageFieldFocused: messageFieldFocusedBinding,
            viewModel: viewModel,
            content: mainLayout
        )
        .overlay {
            KeyboardShortcutOverlayView(
                showSettings: $state.showSettings,
                sidebarCollapsed: $state.sidebarCollapsed,
                selectedPanelRaw: $state.selectedPanelRaw,
                rightPanelCollapsed: $state.rightPanelCollapsed,
                messageFieldFocused: messageFieldFocusedBinding,
                onShowLayoutCustomizer: { state.showLayoutCustomizer = true }
            )
        }
        .overlay(alignment: .topTrailing) {
            if state.showFPSOverlay {
                FPSOverlayView()
                    .padding(Spacing.xl)
            }
        }
        #if os(macOS)
        .background(themeManager.palette.bgDark)
        .confirmationDialog("Allow this command?", isPresented: Binding(
            get: { viewModel.pendingSystemRunApproval != nil },
            set: { if !$0, viewModel.pendingSystemRunApproval != nil { viewModel.respondToSystemRunApproval(.deny) } }
        ), titleVisibility: .visible) {
            Button("Run Once") { viewModel.respondToSystemRunApproval(.allowOnce) }
            Button("Always Allow") { viewModel.respondToSystemRunApproval(.allowAlways) }
            Button("Deny", role: .cancel) { viewModel.respondToSystemRunApproval(.deny) }
        } message: {
            if let p = viewModel.pendingSystemRunApproval {
                Text("\(p.resolvedPath)\n\n\(p.command)")
            }
        }
        .toolbar {
            ToolbarView(viewModel: viewModel, showSettings: $state.showSettings)
        }
        #endif
    }

    private var isZenMode: Bool { state.layoutOptions.zenMode }

    private var mainLayout: some View {
        MainLayoutView(
            layoutOptions: LayoutOptions.shared,
            primarySidebarContent: AnyView(
                SidebarLayoutView(
                    layoutOptions: LayoutOptions.shared,
                    viewModel: viewModel,
                    showSettings: $state.showSettings,
                    showProfile: $state.showProfile,
                    onOpenFolder: runFolderPicker
                )
            ),
            chatArea: AnyView(
                PanelLayoutView(
                    layoutOptions: LayoutOptions.shared,
                    showSettings: $state.showSettings,
                    chatDetailView: AnyView(chatDetailView)
                )
            ),
            onShowLayoutCustomizer: { state.showLayoutCustomizer = true }
        )
        .sheet(isPresented: $state.showLayoutCustomizer, onDismiss: {
            state.restoreFocus()
        }) {
            LayoutCustomizerView()
        }
    }

    private func runFolderPicker() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select your project's root directory"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        viewModel.setWorkingDirectory(url.path)
        #endif
    }

    // MARK: - Empty States

    var onboardingEmptyState: some View {
        EmptyStateViews.onboardingEmptyState(
            themeManager: themeManager,
            showSettings: $state.showSettings,
            settingsInitialTab: $state.settingsInitialTab
        )
    }

    var noSelectionEmptyState: some View {
        EmptyStateViews.noSelectionEmptyState(
            viewModel: viewModel,
            themeManager: themeManager
        )
    }

    var emptyStateView: some View {
        EmptyStateViews.emptyStateView(
            themeManager: themeManager,
            showQuestionSuggestions: $state.showQuestionSuggestions,
            suggestedQuestions: $state.suggestedQuestions,
            onPromptSelected: { prompt in
                viewModel.userInput = prompt
                messageFieldFocused = true
            }
        )
    }

    // Chat detail views, input, mode buttons, error banners, and tool call bars
    // are in ContentView+ChatDetail.swift
}

// MARK: - Apple Integration Notification Handlers (extracted to fix type-checker timeout)

#if os(macOS)
private struct AppleIntegrationHandlers: ViewModifier {
    @ObservedObject var viewModel: ChatViewModel
    @ObservedObject var state: ContentViewState

    func body(content: Content) -> some View {
        content
            // Services menu: "Ask G-Rump" with selected text
            .onReceive(NotificationCenter.default.publisher(for: .init("GRumpServiceAsk"))) { note in
                if let text = note.userInfo?["text"] as? String, !text.isEmpty {
                    viewModel.createNewConversation()
                    viewModel.userInput = text
                    viewModel.sendMessage()
                }
            }
            // Services menu / Finder: "Ask About File"
            .onReceive(NotificationCenter.default.publisher(for: .init("GRumpServiceFile"))) { note in
                if let paths = note.userInfo?["paths"] as? [String], !paths.isEmpty {
                    viewModel.createNewConversation()
                    let fileList = paths.map { "- `\($0)`" }.joined(separator: "\n")
                    viewModel.userInput = "Please analyze the following file(s):\n\(fileList)"
                    viewModel.sendMessage()
                }
            }
            // Notification action / URL scheme: open conversation by UUID
            .onReceive(NotificationCenter.default.publisher(for: .init("GRumpOpenConversation"))) { note in
                if let idString = note.userInfo?["conversationId"] as? String,
                   let uuid = UUID(uuidString: idString),
                   let conv = viewModel.conversations.first(where: { $0.id == uuid }) {
                    viewModel.selectConversation(conv)
                }
            }
            // Notification action: re-run last message in conversation
            .onReceive(NotificationCenter.default.publisher(for: .init("GRumpRunAgain"))) { note in
                if let idString = note.userInfo?["conversationId"] as? String,
                   let uuid = UUID(uuidString: idString),
                   let conv = viewModel.conversations.first(where: { $0.id == uuid }) {
                    viewModel.selectConversation(conv)
                    if let lastUserMsg = conv.messages.last(where: { $0.role == .user }) {
                        viewModel.userInput = lastUserMsg.content
                        viewModel.sendMessage()
                    }
                }
            }
            // Notification action: approve pending system_run
            .onReceive(NotificationCenter.default.publisher(for: .init("GRumpApproveAction"))) { note in
                if note.userInfo?["approvalId"] is String {
                    viewModel.respondToSystemRunApproval(.allowOnce)
                }
            }
            // Notification action: deny pending system_run
            .onReceive(NotificationCenter.default.publisher(for: .init("GRumpDenyAction"))) { note in
                if note.userInfo?["approvalId"] is String {
                    viewModel.respondToSystemRunApproval(.deny)
                }
            }
            // Dock menu / keyboard shortcut: new chat
            .onReceive(NotificationCenter.default.publisher(for: .init("GRumpNewChat"))) { _ in
                viewModel.createNewConversation()
            }
            // Dock menu: toggle sidebar
            .onReceive(NotificationCenter.default.publisher(for: .init("GRumpToggleSidebar"))) { _ in
                withAnimation(.easeInOut(duration: Anim.quick)) {
                    state.layoutOptions.primarySidebarVisible.toggle()
                }
            }
    }
}
#endif
