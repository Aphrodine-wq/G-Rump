import SwiftUI
import Foundation

// MARK: - Xcode Project Models

struct XcodeTarget: Identifiable, Hashable {
    let id: String
    let name: String
    let type: TargetType
    let bundleId: String?
    let deploymentTarget: String?

    enum TargetType: String, Hashable {
        case app = "Application"
        case framework = "Framework"
        case staticLibrary = "Static Library"
        case unitTest = "Unit Tests"
        case uiTest = "UI Tests"
        case appExtension = "App Extension"
        case watchApp = "Watch App"
        case widgetExtension = "Widget Extension"
        case unknown = "Unknown"

        var icon: String {
            switch self {
            case .app: return "app.fill"
            case .framework: return "shippingbox.fill"
            case .staticLibrary: return "building.columns.fill"
            case .unitTest: return "checkmark.diamond.fill"
            case .uiTest: return "iphone.badge.play"
            case .appExtension: return "puzzlepiece.extension.fill"
            case .watchApp: return "applewatch"
            case .widgetExtension: return "rectangle.3.group.fill"
            case .unknown: return "questionmark.square"
            }
        }

        var color: Color {
            switch self {
            case .app: return Color(red: 0.3, green: 0.6, blue: 1.0)
            case .framework: return Color(red: 1.0, green: 0.6, blue: 0.2)
            case .staticLibrary: return Color(red: 0.6, green: 0.6, blue: 0.7)
            case .unitTest, .uiTest: return .accentGreen
            case .appExtension, .widgetExtension: return Color(red: 0.8, green: 0.4, blue: 0.9)
            case .watchApp: return Color(red: 0.9, green: 0.4, blue: 0.5)
            case .unknown: return Color(red: 0.5, green: 0.5, blue: 0.6)
            }
        }
    }
}

struct XcodeScheme: Identifiable, Hashable {
    let id: String
    let name: String
    let isShared: Bool
}

struct XcodeBuildConfig: Identifiable, Hashable {
    let id: String
    let name: String
}

struct XcodeSigningInfo: Identifiable {
    let id = UUID()
    let teamId: String?
    let signingStyle: String
    let provisioningProfile: String?
    let isValid: Bool
}

// MARK: - Xcode Project Service

@MainActor
final class XcodeProjectService: ObservableObject {
    @Published var projectName: String = ""
    @Published var projectPath: String = ""
    @Published var targets: [XcodeTarget] = []
    @Published var schemes: [XcodeScheme] = []
    @Published var buildConfigs: [XcodeBuildConfig] = []
    @Published var signingInfo: XcodeSigningInfo?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedScheme: String = ""
    @Published var selectedConfig: String = "Debug"

    func setDirectory(_ path: String) {
        guard !path.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        let dir = path

        Task { @MainActor in
            let result = await Task.detached(priority: .userInitiated) {
                XcodeProjectInspector.parse(dir: dir)
            }.value
            self.projectName = result.name
            self.projectPath = result.path
            self.targets = result.targets
            self.schemes = result.schemes
            self.buildConfigs = result.configs
            self.selectedScheme = result.schemes.first?.name ?? ""
            self.isLoading = false
            if result.targets.isEmpty && result.path.isEmpty {
                self.errorMessage = "No Xcode project found"
            }
        }
    }

    func build() {
        #if os(macOS)
        guard !projectPath.isEmpty, !selectedScheme.isEmpty else { return }
        let dir = (projectPath as NSString).deletingLastPathComponent
        let scheme = selectedScheme
        let config = selectedConfig

        Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
            process.arguments = [
                "-scheme", scheme,
                "-configuration", config,
                "build"
            ]
            process.currentDirectoryURL = URL(fileURLWithPath: dir)
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            try? process.run()
            process.waitUntilExit()
        }
        #endif
    }

    func openInXcode() {
        #if os(macOS)
        guard !projectPath.isEmpty else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: projectPath))
        #endif
    }

}

// MARK: - Xcode Project View

struct XcodeProjectView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var viewModel: ChatViewModel
    @StateObject private var service = XcodeProjectService()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: Spacing.lg) {
                Image(systemName: "hammer.fill")
                    .font(Typography.bodySmall)
                    .foregroundColor(Color(red: 0.3, green: 0.6, blue: 1.0))

                Text(service.projectName.isEmpty ? "No Project" : service.projectName)
                    .font(Typography.captionSmallSemibold)
                    .foregroundColor(themeManager.palette.textPrimary)
                    .lineLimit(1)

                Spacer()

                #if os(macOS)
                Button(action: { service.openInXcode() }) {
                    Image(systemName: "arrow.up.forward.app")
                        .font(Typography.captionSmall)
                        .foregroundColor(themeManager.palette.textMuted)
                }
                .buttonStyle(ScaleButtonStyle())
                .help("Open in Xcode")
                .disabled(service.projectPath.isEmpty)
                #endif

                Button(action: { service.setDirectory(viewModel.workingDirectory) }) {
                    Image(systemName: "arrow.clockwise")
                        .font(Typography.captionSmall)
                        .foregroundColor(themeManager.palette.textMuted)
                }
                .buttonStyle(ScaleButtonStyle())
                .help("Refresh")
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.lg)

            Rectangle()
                .fill(themeManager.palette.borderSubtle)
                .frame(height: Border.thin)

            if service.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = service.errorMessage {
                VStack(spacing: Spacing.xxl) {
                    Spacer()
                    Image(systemName: "hammer")
                        .font(.system(size: 36, weight: .light))
                        .foregroundColor(themeManager.palette.textMuted)
                    Text(error)
                        .font(Typography.bodySmallMedium)
                        .foregroundColor(themeManager.palette.textSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.xl) {
                        // Scheme & Config pickers
                        if !service.schemes.isEmpty {
                            VStack(alignment: .leading, spacing: Spacing.md) {
                                Text("Scheme")
                                    .font(Typography.captionSmallSemibold)
                                    .foregroundColor(themeManager.palette.textSecondary)

                                Picker("Scheme", selection: $service.selectedScheme) {
                                    ForEach(service.schemes) { scheme in
                                        Text(scheme.name).tag(scheme.name)
                                    }
                                }
                                .pickerStyle(.menu)
                            }
                            .padding(.horizontal, Spacing.xl)
                        }

                        if !service.buildConfigs.isEmpty {
                            VStack(alignment: .leading, spacing: Spacing.md) {
                                Text("Configuration")
                                    .font(Typography.captionSmallSemibold)
                                    .foregroundColor(themeManager.palette.textSecondary)

                                Picker("Config", selection: $service.selectedConfig) {
                                    ForEach(service.buildConfigs) { config in
                                        Text(config.name).tag(config.name)
                                    }
                                }
                                .pickerStyle(.segmented)
                            }
                            .padding(.horizontal, Spacing.xl)
                        }

                        // Build button
                        Button(action: { service.build() }) {
                            HStack(spacing: Spacing.md) {
                                Image(systemName: "hammer.fill")
                                    .font(.system(size: 12))
                                Text("Build")
                                    .font(Typography.bodySmallSemibold)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.lg)
                            .background(themeManager.palette.effectiveAccent)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                        }
                        .buttonStyle(ScaleButtonStyle())
                        .disabled(service.selectedScheme.isEmpty)
                        .padding(.horizontal, Spacing.xl)

                        // Targets
                        if !service.targets.isEmpty {
                            VStack(alignment: .leading, spacing: Spacing.md) {
                                Text("Targets")
                                    .font(Typography.captionSmallSemibold)
                                    .foregroundColor(themeManager.palette.textSecondary)
                                    .padding(.horizontal, Spacing.xl)

                                ForEach(service.targets) { target in
                                    HStack(spacing: Spacing.lg) {
                                        Image(systemName: target.type.icon)
                                            .font(Typography.bodySmall)
                                            .foregroundColor(target.type.color)
                                            .frame(width: 24)

                                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                                            Text(target.name)
                                                .font(Typography.bodySmallMedium)
                                                .foregroundColor(themeManager.palette.textPrimary)
                                            Text(target.type.rawValue)
                                                .font(Typography.micro)
                                                .foregroundColor(themeManager.palette.textMuted)
                                        }

                                        Spacer()
                                    }
                                    .padding(.horizontal, Spacing.xl)
                                    .padding(.vertical, Spacing.md)
                                }
                            }
                        }
                    }
                    .padding(.vertical, Spacing.xl)
                }
            }
        }
        .background(themeManager.palette.bgDark)
        .onAppear { service.setDirectory(viewModel.workingDirectory) }
        .onChange(of: viewModel.workingDirectory) { _, newDir in
            service.setDirectory(newDir)
        }
    }
}
