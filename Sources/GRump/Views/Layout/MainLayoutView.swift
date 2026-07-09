import SwiftUI

// MARK: - Main Layout View
struct MainLayoutView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject var layoutOptions: LayoutOptions
    @AppStorage("SelectedPanel") private var selectedPanelRaw: String = PanelTab.chat.rawValue
    @AppStorage("RightPanelCollapsed") private var rightPanelCollapsed = true
    @AppStorage("SidebarCollapsed") private var sidebarCollapsed = false
    #if os(macOS)
    @AppStorage("NavigatorPaneVisible") private var navigatorPaneVisible = false
    @AppStorage("NavigatorAutoCollapsedSidebarOnce") private var navigatorAutoCollapsedSidebarOnce = false
    #endif

    let primarySidebarContent: AnyView
    let chatArea: AnyView
    var onShowLayoutCustomizer: () -> Void = {}

    private var selectedPanel: PanelTab {
        PanelTab(rawValue: selectedPanelRaw) ?? .chat
    }

    private var isZenMode: Bool { layoutOptions.zenMode }

    var body: some View {
        HStack(spacing: 0) {
            #if os(macOS)
            // Project navigator (leftmost fixed pane, ⌘0)
            if navigatorPaneVisible && !isZenMode {
                ProjectNavigatorView()
                    .frame(width: 240)
                Rectangle()
                    .fill(themeManager.palette.borderCrisp)
                    .frame(width: 1)
            }
            #endif

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
        .onReceive(NotificationCenter.default.publisher(for: .init("GRumpToggleNavigator"))) { _ in
            withAnimation(.easeInOut(duration: Anim.quick)) {
                navigatorPaneVisible.toggle()
                // First enable trades the conversation sidebar for the navigator
                // so the chat column doesn't get crushed. Once only.
                if navigatorPaneVisible && !navigatorAutoCollapsedSidebarOnce {
                    layoutOptions.primarySidebarVisible = false
                    navigatorAutoCollapsedSidebarOnce = true
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("GRumpRevealFile"))) { _ in
            // Revealing a file only makes sense with the navigator on screen.
            withAnimation(.easeInOut(duration: Anim.quick)) {
                navigatorPaneVisible = true
            }
        }
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
