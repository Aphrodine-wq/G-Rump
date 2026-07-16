import SwiftUI

/// Vertical icon-only sidebar on the right edge for switching between panels.
struct RightPanelSidebar: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Binding var selectedPanel: PanelTab
    @Binding var panelCollapsed: Bool
    @State private var hoveredTab: PanelTab?
    @State private var hoverDebounce: DispatchWorkItem?
    @ObservedObject private var proposalStore = SkillProposalStore.shared
    var onShowLayoutCustomizer: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            // Panel groups from the single source of truth (PanelTab.dockGroups),
            // separated by thin dividers.
            ForEach(Array(PanelTab.dockGroups.enumerated()), id: \.offset) { index, group in
                if index > 0 {
                    Rectangle()
                        .fill(themeManager.palette.borderSubtle)
                        .frame(height: Border.thin)
                        .padding(.horizontal, Spacing.lg)
                        .padding(.vertical, Spacing.lg)
                }
                VStack(spacing: Spacing.xs) {
                    ForEach(group, id: \.self) { tab in
                        panelButton(tab)
                    }
                }
                .padding(.top, index == 0 ? Spacing.xl : 0)
            }

            Spacer()

            // Customize Layout button
            Button(action: onShowLayoutCustomizer) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(themeManager.palette.textMuted)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(ScaleButtonStyle())
            .help("Customize Layout")

            // Collapse/expand toggle
            Button(action: {
                withAnimation(.easeInOut(duration: Anim.quick)) {
                    panelCollapsed.toggle()
                }
            }) {
                Image(systemName: panelCollapsed ? "sidebar.leading" : "sidebar.trailing")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(themeManager.palette.textMuted)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(ScaleButtonStyle())
            .help(panelCollapsed ? "Show panel" : "Hide panel")
            .padding(.bottom, Spacing.xl)
        }
        .frame(width: 44)
        .background(themeManager.palette.bgSidebar)
    }

    @ViewBuilder
    private func panelButton(_ tab: PanelTab) -> some View {
        let isSelected = selectedPanel == tab && !panelCollapsed

        Button(action: {
            withAnimation(.easeInOut(duration: Anim.quick)) {
                if selectedPanel == tab {
                    panelCollapsed.toggle()
                } else {
                    selectedPanel = tab
                    panelCollapsed = false
                }
            }
        }) {
            Image(systemName: tab.icon)
                .font(.system(size: 15, weight: isSelected ? .semibold : .medium))
                .foregroundColor(isSelected ? themeManager.palette.effectiveAccent : themeManager.palette.textMuted)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(isSelected ? themeManager.palette.effectiveAccent.opacity(0.12) : Color.clear)
                )
                .overlay(alignment: .topTrailing) {
                    // Pending skill proposals wait on the user — badge the rail.
                    if tab == .learning && proposalStore.pendingCount > 0 {
                        Circle()
                            .fill(themeManager.palette.effectiveAccent)
                            .frame(width: 7, height: 7)
                            .offset(x: -3, y: 3)
                    }
                }
        }
        .buttonStyle(ScaleButtonStyle())
        .onHover { isHovered in
            hoverDebounce?.cancel()
            if isHovered {
                let work = DispatchWorkItem {
                    withAnimation(.easeOut(duration: 0.15)) {
                        hoveredTab = tab
                    }
                }
                hoverDebounce = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
            } else {
                withAnimation(.easeOut(duration: 0.1)) {
                    hoveredTab = nil
                }
            }
        }
        .overlay(alignment: .leading) {
            if hoveredTab == tab {
                PanelTooltip(tab: tab)
                    .offset(x: -228)
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .trailing)))
                    .zIndex(100)
            }
        }
    }
}
