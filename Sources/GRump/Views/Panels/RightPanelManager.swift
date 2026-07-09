import SwiftUI

struct RightPanelManager: View {
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject private var layoutOptions = LayoutOptions.shared

    @AppStorage("SelectedPanel") private var selectedPanelRaw: String = PanelTab.chat.rawValue
    @AppStorage("RightPanelCollapsed") private var rightPanelCollapsed = true

    private var selectedPanel: PanelTab {
        PanelTab(rawValue: selectedPanelRaw) ?? .chat
    }

    private var showRightPanel: Bool {
        layoutOptions.panelVisible && !layoutOptions.zenMode && !rightPanelCollapsed && selectedPanel != .chat
    }

    var body: some View {
        Group {
            if showRightPanel {
                #if os(macOS)
                HSplitView {
                    EmptyView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    rightPanelContent
                        .frame(minWidth: 280, idealWidth: 340, maxWidth: 500)
                }
                #else
                rightPanelContent
                    .frame(minWidth: 280, idealWidth: 340, maxWidth: 500)
                #endif
            } else {
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var rightPanelContent: some View {
        switch selectedPanel {
        case .chat:
            EmptyView()
        case .files:
            ProjectNavigatorView()
        case .preview:
            SwiftUIPreviewPanel()
        case .simulator:
            #if os(macOS)
            SimulatorDashboardView()
            #else
            Text("Simulator not available on iOS")
                .foregroundColor(themeManager.palette.textMuted)
            #endif
        case .git:
            GitPanelView()
        case .tests:
            TestExplorerView()
        case .build:
            BuildConsolePanel(lspService: nil)
        case .assets:
            AssetManagerPanel()
        case .localization:
            LocalizationPanel()
        case .schema:
            SchemaEditorPanel()
        case .profiling:
            ProfilingPanel()
        case .logs:
            #if os(macOS)
            LogViewerPanel()
            #else
            Text("Log viewer not available on iOS")
                .foregroundColor(themeManager.palette.textMuted)
            #endif
        case .spm:
            SPMDashboardView()
        case .xcode:
            XcodeProjectView()
        case .docs:
            AppleDocSearchPanel()
        case .terminal:
            #if os(macOS)
            InlineTerminalView()
            #else
            Text("Terminal not available on iOS")
                .foregroundColor(themeManager.palette.textMuted)
            #endif
        case .appstore:
            AppStoreToolsView()
        case .accessibility:
            AccessibilityAuditView()
        case .memory:
            MemoryPanel()
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
}
