// MARK: - WelcomeWindowView
//
// Xcode-style welcome window (macOS only): brand + project actions on the
// left, recent projects from ProjectStore on the right. Every action lands
// in ChatViewModel.setWorkingDirectory, which feeds ProjectStore.

#if os(macOS)
import SwiftUI
import AppKit

struct WelcomeWindowView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var viewModel: ChatViewModel
    @ObservedObject private var projectStore = ProjectStore.shared
    @Environment(\.dismissWindow) private var dismissWindow
    @AppStorage("ShowWelcomeWindowOnLaunch") private var showOnLaunch = true

    @State private var showCloneSheet = false
    @State private var showNewProjectSheet = false

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        HStack(spacing: 0) {
            leftPane
                .frame(width: 360)
                .background(themeManager.palette.bgDark)

            rightPane
                .frame(width: 420)
                .background(themeManager.palette.bgCard)
        }
        .frame(width: 780, height: 480)
        .sheet(isPresented: $showCloneSheet) {
            CloneRepositorySheet(onCloned: openProject)
        }
        .sheet(isPresented: $showNewProjectSheet) {
            NewProjectSheet(onCreated: openProject)
        }
    }

    private func openProject(_ path: String) {
        viewModel.setWorkingDirectory(path)
        dismissWindow(id: "welcome")
    }

    // MARK: - Left Pane

    private var leftPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: Spacing.lg) {
                FrownyFaceLogo(size: 72)
                    .shadow(color: themeManager.palette.effectiveAccent.opacity(0.3), radius: 16, y: 6)

                Text("G-Rump")
                    .font(Typography.displayMedium)
                    .foregroundColor(themeManager.palette.textPrimary)

                Text("Version \(appVersion)")
                    .font(Typography.captionSmall)
                    .foregroundColor(themeManager.palette.textMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, Spacing.colossal)

            Spacer(minLength: Spacing.huge)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                welcomeAction(icon: "folder", title: "Open Project…") {
                    runOpenPanel()
                }
                welcomeAction(icon: "square.and.arrow.down.on.square", title: "Clone Repository…") {
                    showCloneSheet = true
                }
                welcomeAction(icon: "plus.square", title: "New Project…") {
                    showNewProjectSheet = true
                }
            }
            .padding(.horizontal, Spacing.colossal)

            Spacer(minLength: Spacing.huge)

            Toggle("Show this window on launch", isOn: $showOnLaunch)
                .toggleStyle(.checkbox)
                .font(Typography.captionSmall)
                .foregroundColor(themeManager.palette.textMuted)
                .padding(.horizontal, Spacing.colossal)
                .padding(.bottom, Spacing.colossal)
        }
    }

    private func welcomeAction(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.xl) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(themeManager.palette.effectiveAccent)
                    .frame(width: 24)
                Text(title)
                    .font(Typography.bodySmallSemibold)
                    .foregroundColor(themeManager.palette.textPrimary)
                Spacer()
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func runOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select your project's root directory"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openProject(url.path)
    }

    // MARK: - Right Pane (Recents)

    private var rightPane: some View {
        Group {
            if projectStore.recents.isEmpty {
                VStack(spacing: Spacing.lg) {
                    Image(systemName: "clock")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundColor(themeManager.palette.textMuted.opacity(0.6))
                    Text("No Recent Projects")
                        .font(Typography.bodySmallMedium)
                        .foregroundColor(themeManager.palette.textMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 2) {
                        ForEach(projectStore.recents) { project in
                            RecentProjectRow(project: project, onOpen: openProject)
                        }
                    }
                    .padding(Spacing.lg)
                }
            }
        }
    }
}

// MARK: - Recent Project Row

private struct RecentProjectRow: View {
    let project: Project
    let onOpen: (String) -> Void
    @EnvironmentObject var themeManager: ThemeManager
    @State private var isHovered = false

    private var pathExists: Bool {
        FileManager.default.fileExists(atPath: project.rootPath)
    }

    private var kindIcon: String {
        switch project.kind {
        case .xcworkspace: return "square.stack.3d.up"
        case .xcodeproj: return "hammer"
        case .spmPackage: return "shippingbox"
        case .plainFolder: return "folder"
        }
    }

    var body: some View {
        Button {
            guard pathExists else { return }
            onOpen(project.rootPath)
        } label: {
            HStack(spacing: Spacing.xl) {
                Image(systemName: kindIcon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(themeManager.palette.effectiveAccent)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .font(Typography.bodySmallSemibold)
                        .foregroundColor(themeManager.palette.textPrimary)
                        .lineLimit(1)
                    Text((project.rootPath as NSString).abbreviatingWithTildeInPath)
                        .font(Typography.captionSmall)
                        .foregroundColor(themeManager.palette.textMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                if project.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10))
                        .foregroundColor(themeManager.palette.textMuted)
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(isHovered && pathExists
                          ? themeManager.palette.effectiveAccent.opacity(0.08)
                          : Color.clear)
            )
            .contentShape(Rectangle())
            .opacity(pathExists ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Open") { onOpen(project.rootPath) }
                .disabled(!pathExists)
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: project.rootPath)])
            }
            .disabled(!pathExists)
            Divider()
            Button(project.isPinned ? "Unpin" : "Pin") {
                ProjectStore.shared.togglePin(rootPath: project.rootPath)
            }
            Button("Remove from Recents") {
                ProjectStore.shared.removeRecent(rootPath: project.rootPath)
            }
        }
        .accessibilityLabel("\(project.name), \(pathExists ? "recent project" : "missing project")")
    }
}
#endif
