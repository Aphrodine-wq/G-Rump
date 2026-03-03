import SwiftUI

struct StatusBarView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject var viewModel: ChatViewModel
    @StateObject private var perfAdvisor = PerformanceAdvisor.shared
    @State private var showGitShortcuts = false
    
    var body: some View {
        HStack(spacing: Spacing.xl) {
            // Left section - connection status
            HStack(spacing: Spacing.md) {
                Circle()
                    .fill(connectionColor)
                    .frame(width: 6, height: 6)
                    .accessibilityLabel(connectionStatus)
                
                Text(connectionStatus)
                    .font(Typography.micro)
                    .foregroundColor(themeManager.palette.textMuted)
            }
            
            Spacer()
            
            // Center section - git shortcuts
            if !viewModel.workingDirectory.isEmpty {
                Button(action: { showGitShortcuts.toggle() }) {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 10))
                        Text("Git")
                            .font(Typography.micro)
                    }
                    .foregroundColor(themeManager.palette.textMuted)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.xs)
                    .background(themeManager.palette.bgElevated)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showGitShortcuts, arrowEdge: .top) {
                    GitShortcutsPopover(workingDirectory: viewModel.workingDirectory)
                        .environmentObject(themeManager)
                }
            }
            
            // Performance indicator
            if perfAdvisor.isUnderPressure || perfAdvisor.appMemoryMB > 500 {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: perfAdvisor.thermalState == .critical ? "thermometer.sun.fill" :
                            perfAdvisor.thermalState == .serious ? "thermometer.high" : "memorychip")
                        .font(.system(size: 10))
                        .foregroundColor(perfAdvisor.isUnderPressure ? .accentOrange : themeManager.palette.textMuted)
                    Text(String(format: "%.0f MB", perfAdvisor.appMemoryMB))
                        .font(Typography.micro)
                        .foregroundColor(themeManager.palette.textMuted)
                }
                .help(perfAdvisor.statusSummary)
            }

            // Confidence calibration indicator
            if let report = viewModel.confidenceCalibration.currentReport {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: report.level.icon)
                        .font(.system(size: 10))
                        .foregroundColor(confidenceColor(report.level))
                    Text("\(Int(report.overallScore * 100))%")
                        .font(Typography.micro)
                        .foregroundColor(confidenceColor(report.level))
                }
                .help("Confidence: \(report.level.label) — \(report.summary)")
            }

            // Right section - errors and info
            HStack(spacing: Spacing.md) {
                if let error = viewModel.errorMessage {
                    Button(action: { viewModel.errorMessage = nil }) {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.accentOrange)
                            Text("Error")
                                .font(Typography.micro)
                                .foregroundColor(.accentOrange)
                        }
                    }
                    .buttonStyle(.plain)
                }
                
                if viewModel.isLoading {
                    HStack(spacing: Spacing.sm) {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 12, height: 12)
                        Text("AI working...")
                            .font(Typography.micro)
                            .foregroundColor(themeManager.palette.textMuted)
                    }
                }
            }
        }
        .padding(.horizontal, Spacing.huge)
        .padding(.vertical, Spacing.sm)
        .background(themeManager.palette.bgSidebar)
        .overlay(
            Rectangle()
                .fill(themeManager.palette.borderCrisp)
                .frame(height: Border.thin),
            alignment: .top
        )
    }
    
    private func confidenceColor(_ level: ConfidenceLevel) -> Color {
        switch level {
        case .veryLow:  return .red
        case .low:      return .accentOrange
        case .moderate: return .yellow
        case .high:     return .accentGreen
        case .veryHigh: return .blue
        }
    }

    private var connectionColor: Color {
        if viewModel.isLoading { return .accentGreen }
        switch ConnectionMonitor.shared.status {
        case .connected: return .accentGreen
        case .degraded: return .accentOrange
        case .disconnected: return .red
        case .checking: return .accentOrange
        }
    }

    private var connectionStatus: String {
        if viewModel.isLoading { return "Streaming..." }
        switch ConnectionMonitor.shared.status {
        case .connected: return viewModel.platformUser != nil ? "Connected" : "Guest mode"
        case .degraded(let reason): return "Degraded: \(reason)"
        case .disconnected: return "Disconnected"
        case .checking: return "Checking..."
        }
    }
}

struct GitShortcutsPopover: View {
    @EnvironmentObject var themeManager: ThemeManager
    let workingDirectory: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Git Shortcuts")
                .font(Typography.captionSemibold)
                .foregroundColor(themeManager.palette.textPrimary)
            
            Divider()
            
            GitShortcutButton(label: "Status", shortcut: "⌘⇧G S") {
                runGitCommand(["status"])
            }
            GitShortcutButton(label: "Commit All", shortcut: "⌘⇧G C") {
                runGitCommand(["commit", "-a", "-m", "auto-commit"])
            }
            GitShortcutButton(label: "Push", shortcut: "⌘⇧G P") {
                runGitCommand(["push"])
            }
            GitShortcutButton(label: "Pull", shortcut: "⌘⇧G L") {
                runGitCommand(["pull"])
            }
            GitShortcutButton(label: "Log", shortcut: "⌘⇧G G") {
                runGitCommand(["log", "--oneline", "-10"])
            }

            if showOutput {
                Divider()
                ScrollView {
                    Text(gitOutput)
                        .font(Typography.codeMicro)
                        .foregroundColor(themeManager.palette.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 150)
            }
        }
        .padding(Spacing.lg)
        .frame(width: showOutput ? 320 : 180)
    }
    
    @State private var gitOutput: String = ""
    @State private var showOutput: Bool = false

    private func runGitCommand(_ args: [String]) {
        #if os(macOS)
        Task {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = args
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            do {
                try process.run()
                process.waitUntilExit()
                let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let stdout = String(data: outData, encoding: .utf8) ?? ""
                let stderr = String(data: errData, encoding: .utf8) ?? ""
                let output = stdout + stderr
                GRumpLogger.general.info("Git: \(args.joined(separator: " ")) -> \(output.prefix(500))")
                gitOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
                showOutput = !gitOutput.isEmpty
            } catch {
                GRumpLogger.general.error("Git command failed: \(error.localizedDescription)")
                gitOutput = "Error: \(error.localizedDescription)"
                showOutput = true
            }
        }
        #endif
    }
}

struct GitShortcutButton: View {
    @EnvironmentObject var themeManager: ThemeManager
    let label: String
    let shortcut: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .font(Typography.captionSmallMedium)
                    .foregroundColor(themeManager.palette.textPrimary)
                Spacer()
                Text(shortcut)
                    .font(Typography.micro)
                    .foregroundColor(themeManager.palette.textMuted)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, 2)
                    .background(themeManager.palette.bgElevated)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.xs))
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, Spacing.xs)
    }
}

#if swift(>=5.9) && canImport(SwiftUI)
@available(macOS 14.0, iOS 17.0, *)
private struct StatusBarPreview: PreviewProvider {
    static var previews: some View {
        StatusBarView(viewModel: ChatViewModel())
            .environmentObject(ThemeManager())
    }
}
#endif
