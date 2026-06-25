import SwiftUI

// MARK: - Main Layout View
struct MainLayoutView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject var layoutOptions: LayoutOptions
    @AppStorage("SelectedPanel") private var selectedPanelRaw: String = PanelTab.chat.rawValue
    @AppStorage("RightPanelCollapsed") private var rightPanelCollapsed = true
    @AppStorage("SidebarCollapsed") private var sidebarCollapsed = false

    let primarySidebarContent: AnyView
    let chatArea: AnyView
    var onShowLayoutCustomizer: () -> Void = {}

    private var selectedPanel: PanelTab {
        PanelTab(rawValue: selectedPanelRaw) ?? .chat
    }

    private var isZenMode: Bool { layoutOptions.zenMode }

    var body: some View {
        HStack(spacing: 0) {
            // Left sidebar (if position == .left)
            if layoutOptions.primarySidebarPosition == .left {
                primarySidebarContent
                if layoutOptions.primarySidebarVisible && !isZenMode {
                    Rectangle()
                        .fill(themeManager.palette.borderCrisp)
                        .frame(width: 1)
                }
            }

            // Main chat area (centered if layout option set)
            if layoutOptions.centeredLayout {
                HStack {
                    Spacer(minLength: 0)
                    chatArea
                        .frame(maxWidth: 960)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                chatArea
            }

            // Right sidebar (if position == .right)
            if layoutOptions.primarySidebarPosition == .right {
                if layoutOptions.primarySidebarVisible && !isZenMode {
                    Rectangle()
                        .fill(themeManager.palette.borderCrisp)
                        .frame(width: 1)
                }
                primarySidebarContent
            }

            // Activity bar (right panel icon sidebar)
            if layoutOptions.activityBarVisible && !isZenMode {
                Rectangle()
                    .fill(themeManager.palette.borderCrisp)
                    .frame(width: 1)

                RightPanelSidebar(
                    selectedPanel: Binding(
                        get: { selectedPanel },
                        set: { selectedPanelRaw = $0.rawValue }
                    ),
                    panelCollapsed: $rightPanelCollapsed,
                    onShowLayoutCustomizer: onShowLayoutCustomizer
                )
            }
        }
        #if os(macOS)
        .onChange(of: layoutOptions.fullScreenMode) { _, isFullScreen in
            if let window = NSApplication.shared.windows.first {
                if isFullScreen && !window.styleMask.contains(.fullScreen) {
                    window.toggleFullScreen(nil)
                } else if !isFullScreen && window.styleMask.contains(.fullScreen) {
                    window.toggleFullScreen(nil)
                }
            }
        }
        .onChange(of: layoutOptions.zenMode) { _, zen in
            if zen {
                sidebarCollapsed = true
            }
        }
        #endif
    }
}
