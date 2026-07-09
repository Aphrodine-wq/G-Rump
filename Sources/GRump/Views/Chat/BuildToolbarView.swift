// MARK: - Build Toolbar
//
// Xcode-style run bar above the chat top bar (macOS, project open, not zen):
// [▶ Run | ■ Stop] [Project ⌄] [Scheme ⌄] [Destination ⌄] … [status pill].
// ⌘R / ⌘⇧. live in KeyboardShortcutHandler so they work app-wide.

#if os(macOS)
import SwiftUI
import AppKit

struct BuildToolbarView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var viewModel: ChatViewModel
    @ObservedObject private var projectStore = ProjectStore.shared
    @ObservedObject private var buildService = BuildService.shared

    private var isXcodeProject: Bool {
        projectStore.current?.kind == .xcworkspace || projectStore.current?.kind == .xcodeproj
    }

    private var canBuild: Bool {
        guard let project = projectStore.current, !buildService.phase.isActive else { return false }
        switch project.kind {
        case .plainFolder: return false
        case .spmPackage: return true
        case .xcworkspace, .xcodeproj: return buildService.selectedScheme != nil
        }
    }

    var body: some View {
        Group {
            if let project = projectStore.current {
                HStack(spacing: Spacing.xl) {
                    runStopControls

                    projectMenu(project)

                    if isXcodeProject {
                        schemeMenu
                        destinationMenu
                    }

                    Spacer()

                    statusPill
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.vertical, Spacing.md)
                .background(themeManager.palette.bgSidebar.opacity(0.6))
                .onAppear {
                    if buildService.currentProject?.rootPath != project.rootPath {
                        buildService.refresh(for: project)
                    }
                }
            }
        }
        .onChange(of: projectStore.current) { _, newProject in
            buildService.refresh(for: newProject)
        }
    }

    // MARK: - Run / Stop

    private var runStopControls: some View {
        HStack(spacing: Spacing.sm) {
            Button {
                buildService.run()
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(canBuild ? themeManager.palette.effectiveAccent : themeManager.palette.textMuted.opacity(0.5))
                    .frame(width: 26, height: 24)
            }
            .buttonStyle(ScaleButtonStyle())
            .disabled(!canBuild)
            .help("Run (⌘R)")

            Button {
                buildService.stop()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(buildService.phase.isActive ? themeManager.palette.textPrimary : themeManager.palette.textMuted.opacity(0.5))
                    .frame(width: 26, height: 24)
            }
            .buttonStyle(ScaleButtonStyle())
            .disabled(!buildService.phase.isActive)
            .help("Stop (⌘⇧.)")
        }
        .background(themeManager.palette.bgInput)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .stroke(themeManager.palette.borderCrisp.opacity(0.5), lineWidth: Border.thin))
    }

    // MARK: - Project Menu

    private func projectMenu(_ project: Project) -> some View {
        Menu {
            if !projectStore.recents.isEmpty {
                Section("Recents") {
                    ForEach(projectStore.recents.prefix(8)) { recent in
                        Button(recent.name) {
                            viewModel.setWorkingDirectory(recent.rootPath)
                        }
                        .disabled(recent.rootPath == project.rootPath)
                    }
                }
                Divider()
            }
            Button("Open Project…") { runOpenPanel() }
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: project.rootPath)])
            }
            Divider()
            Button("Close Project") {
                viewModel.setWorkingDirectory("")
            }
        } label: {
            chipLabel(icon: kindIcon(project.kind), text: project.name)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Project")
    }

    private func kindIcon(_ kind: ProjectKind) -> String {
        switch kind {
        case .xcworkspace: return "square.stack.3d.up"
        case .xcodeproj: return "hammer"
        case .spmPackage: return "shippingbox"
        case .plainFolder: return "folder"
        }
    }

    private func runOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select your project's root directory"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        viewModel.setWorkingDirectory(url.path)
    }

    // MARK: - Scheme Menu

    private var schemeMenu: some View {
        Menu {
            if buildService.schemes.isEmpty {
                Text("No schemes found")
            }
            ForEach(buildService.schemes, id: \.self) { scheme in
                Button {
                    buildService.selectedScheme = scheme
                } label: {
                    if scheme == buildService.selectedScheme {
                        Label(scheme, systemImage: "checkmark")
                    } else {
                        Text(scheme)
                    }
                }
            }
        } label: {
            chipLabel(icon: "gearshape", text: buildService.selectedScheme ?? "No Scheme")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Scheme")
    }

    // MARK: - Destination Menu

    private var bootedSimulators: [BuildDestination] {
        buildService.destinations.filter {
            if case .simulator(_, _, true) = $0 { return true } else { return false }
        }
    }

    private var shutdownSimulators: [BuildDestination] {
        buildService.destinations.filter {
            if case .simulator(_, _, false) = $0 { return true } else { return false }
        }
    }

    private var destinationMenu: some View {
        Menu {
            if !bootedSimulators.isEmpty {
                Section("Booted") {
                    ForEach(bootedSimulators) { destination in
                        destinationButton(destination)
                    }
                }
            }
            if !shutdownSimulators.isEmpty {
                Section("iOS Simulators") {
                    ForEach(shutdownSimulators) { destination in
                        destinationButton(destination)
                    }
                }
            }
            Section {
                destinationButton(.mac)
            }
            Divider()
            Button("Refresh Destinations") { buildService.refreshDestinations() }
        } label: {
            chipLabel(
                icon: buildService.selectedDestination == .mac ? "desktopcomputer" : "iphone",
                text: buildService.selectedDestination?.label ?? "No Destination"
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Destination")
    }

    private func destinationButton(_ destination: BuildDestination) -> some View {
        Button {
            buildService.selectedDestination = destination
        } label: {
            if destination == buildService.selectedDestination {
                Label(destination.label, systemImage: "checkmark")
            } else {
                Text(destination.label)
            }
        }
    }

    // MARK: - Status Pill

    @ViewBuilder
    private var statusPill: some View {
        switch buildService.phase {
        case .idle:
            EmptyView()
        case .building, .installing, .launching:
            HStack(spacing: Spacing.md) {
                ProgressView()
                    .controlSize(.small)
                Text(phaseLabel)
                    .font(Typography.captionSmallMedium)
                    .foregroundColor(themeManager.palette.textSecondary)
            }
        case .running(let app):
            pill(icon: "play.circle.fill", color: .accentGreen, text: "Running \(app)")
        case .succeeded(let duration, let warnings):
            pill(
                icon: "checkmark.circle.fill",
                color: .accentGreen,
                text: warnings > 0
                    ? String(format: "Succeeded in %.1fs · %d warnings", duration, warnings)
                    : String(format: "Succeeded in %.1fs", duration)
            )
        case .failed(let errors, let warnings):
            pill(
                icon: "xmark.circle.fill",
                color: .red,
                text: failedText(errors: errors, warnings: warnings)
            )
        case .cancelled:
            pill(icon: "minus.circle.fill", color: themeManager.palette.textMuted, text: "Cancelled")
        }
    }

    private var phaseLabel: String {
        switch buildService.phase {
        case .installing: return "Installing…"
        case .launching: return "Launching…"
        default: return "Building…"
        }
    }

    private func failedText(errors: Int, warnings: Int) -> String {
        guard errors > 0 else { return "Failed" }   // pipeline failures parse no source errors
        return warnings > 0 ? "\(errors) errors · \(warnings) warnings" : "\(errors) errors"
    }

    private func pill(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(color)
            Text(text)
                .font(Typography.captionSmallMedium)
                .foregroundColor(themeManager.palette.textSecondary)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        .background(color.opacity(0.1))
        .clipShape(Capsule())
    }

    // MARK: - Shared chip label

    private func chipLabel(icon: String, text: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
            Text(text)
                .font(Typography.captionSmallMedium)
                .lineLimit(1)
        }
        .foregroundColor(themeManager.palette.textSecondary)
    }
}
#endif
