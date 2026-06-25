import SwiftUI

// MARK: - Sidebar Layout View
struct SidebarLayoutView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject var layoutOptions: LayoutOptions
    @AppStorage("SidebarCollapsed") private var sidebarCollapsed = false

    let viewModel: ChatViewModel
    @Binding var showSettings: Bool
    @Binding var showProfile: Bool
    let onOpenFolder: () -> Void

    private var isZenMode: Bool { layoutOptions.zenMode }

    var body: some View {
        Group {
            if !layoutOptions.primarySidebarVisible || isZenMode {
                EmptyView()
            } else if sidebarCollapsed {
                collapsedSidebarStrip
            } else {
                ConversationSidebar(viewModel: viewModel, showSettings: $showSettings, showProfile: $showProfile, onOpenFolder: onOpenFolder)
                    .frame(minWidth: 180, idealWidth: 220, maxWidth: 260)
            }
        }
    }

    // MARK: - Collapsed Sidebar Icon Strip

    private var collapsedSidebarStrip: some View {
        VStack(spacing: 0) {
            // Logo / expand button
            Button(action: {
                withAnimation(.easeInOut(duration: Anim.quick)) {
                    sidebarCollapsed = false
                }
            }) {
                FrownyFaceLogo(size: 26)
            }
            .buttonStyle(.plain)
            .help("Expand sidebar (⌘\\)")
            .padding(.vertical, Spacing.xxl)

            Rectangle()
                .fill(themeManager.palette.borderSubtle)
                .frame(height: Border.thin)

            // New Chat
            Button(action: { viewModel.createNewConversation() }) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(themeManager.palette.effectiveAccent)
                    .frame(width: 36, height: 36)
                    .background(themeManager.palette.bgInput)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.standard, style: .continuous))
            }
            .buttonStyle(ScaleButtonStyle())
            .help("New Chat (⌘N)")
            .padding(.top, Spacing.xl)

            // Settings
            Button(action: {
                showSettings = true
            }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(themeManager.palette.textMuted)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(ScaleButtonStyle())
            .help("Settings (⌘,)")
            .padding(.top, Spacing.lg)

            Spacer()

            // Open Folder
            Button(action: onOpenFolder) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(themeManager.palette.textMuted)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(ScaleButtonStyle())
            .help("Open folder")

            // Profile
            Button(action: { showProfile = true }) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(themeManager.palette.textMuted)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(ScaleButtonStyle())
            .help("Profile")
            .padding(.bottom, Spacing.xxl)
        }
        .frame(width: 52)
        .background(themeManager.palette.bgSidebar)
    }
}
