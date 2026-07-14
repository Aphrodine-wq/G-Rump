import SwiftUI
import Combine

// MARK: - Content View State
@MainActor
class ContentViewState: ObservableObject {
    // MARK: - Modal State
    @Published var showSettings = false
    @Published var showProfile = false
    @Published var settingsInitialTab: SettingsTab?
    @Published var showThreadNavigation = false
    @Published var showSpecQuestionsModal = false
    @Published var showModeSelectModal = false
    @Published var showLayoutCustomizer = false

    /// Conversations already offered the first-message mode prompt this launch.
    /// Not persisted: after relaunch, any conversation with user messages never
    /// re-prompts (the gate checks message history), so inference covers it.
    var modePromptedConversationIds: Set<UUID> = []

    // MARK: - Focus State
    @Published var messageFieldFocused = false

    // MARK: - UI State
    @Published var toolCallsBarExpanded = false
    @Published var lastScrollTime: Date = .distantPast
    @Published var showTimeline = false
    @Published var modeToastText: String?
    @Published var modeToastWorkItem: DispatchWorkItem?
    @Published var lastStreamingLength: Int = 0
    @Published var expandedMessageIds: Set<UUID> = []

    // MARK: - Overlay State
    @AppStorage("ShowFPSOverlay") var showFPSOverlay = false
    @AppStorage("SidebarCollapsed") var sidebarCollapsed = false
    @AppStorage("SelectedPanel") var selectedPanelRaw: String = PanelTab.chat.rawValue
    @AppStorage("RightPanelCollapsed") var rightPanelCollapsed = true

    // MARK: - Services
    @ObservedObject var lspService = LSPService()
    @ObservedObject var layoutOptions = LayoutOptions.shared

    // MARK: - Computed Properties
    var selectedPanel: PanelTab {
        PanelTab(rawValue: selectedPanelRaw) ?? .chat
    }

    var isZenMode: Bool { layoutOptions.zenMode }

    var showRightPanel: Bool {
        layoutOptions.panelVisible && !isZenMode && !rightPanelCollapsed && selectedPanel != .chat
    }

    // MARK: - Actions
    func showSettingsTab(_ tab: SettingsTab? = nil) {
        settingsInitialTab = tab
        showSettings = true
    }

    func showProfileSheet() {
        showProfile = true
    }

    func focusMessageField() {
        messageFieldFocused = true
    }

    func unfocusMessageField() {
        messageFieldFocused = false
    }

    /// Restore focus to the message input after a sheet dismiss or layout change.
    /// Uses a short delay to let SwiftUI finish the dismiss animation first.
    func restoreFocus() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.messageFieldFocused = true
        }
    }

    func toggleSidebar() {
        withAnimation(.easeInOut(duration: Anim.quick)) {
            sidebarCollapsed.toggle()
        }
    }

    func switchPanel(_ tab: PanelTab) {
        withAnimation(.easeInOut(duration: Anim.quick)) {
            if selectedPanelRaw == tab.rawValue && !rightPanelCollapsed {
                rightPanelCollapsed = true
            } else {
                selectedPanelRaw = tab.rawValue
                rightPanelCollapsed = false
            }
        }
    }

    func showModeToast(_ mode: AgentMode) {
        modeToastWorkItem?.cancel()
        modeToastText = mode.toastMessage

        let workItem = DispatchWorkItem { [weak self] in
            withAnimation(.easeInOut(duration: Anim.quick)) {
                self?.modeToastText = nil
            }
        }
        modeToastWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: workItem)
    }

    // MARK: - Cleanup
    func cancelToastWorkItem() {
        modeToastWorkItem?.cancel()
    }
}
