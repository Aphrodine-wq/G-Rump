// MARK: - Onboarding Step 4: Workspace
//
// Workspace directory picker, detected-tools grid, and
// "Install All Missing" via Homebrew.

import SwiftUI
#if os(macOS)
import AppKit
#endif

extension OnboardingView {

    // MARK: - Step 4: Workspace

    var stepWorkspace: some View {
        VStack(spacing: Spacing.giant) {
            VStack(spacing: Spacing.lg) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(themeManager.palette.effectiveAccent)

                Text("Set your workspace")
                    .font(Typography.displayMedium)
                    .foregroundColor(themeManager.palette.textPrimary)

                Text("Point G-Rump at your project's root directory so it can read files, run commands, and understand your codebase.")
                    .font(Typography.bodySmall)
                    .foregroundColor(themeManager.palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }

            VStack(spacing: Spacing.xl) {
                #if os(macOS)
                Button(action: runFolderPicker) {
                    HStack(spacing: Spacing.md) {
                        Image(systemName: "folder.badge.plus")
                            .font(Typography.bodyMedium)
                        Text(viewModel.workingDirectory.isEmpty ? "Choose folder..." : viewModel.workingDirectory)
                            .font(Typography.bodySmallSemibold)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .frame(maxWidth: 400)
                    .padding(.vertical, Spacing.xl)
                    .padding(.horizontal, Spacing.huge)
                    .background(themeManager.palette.bgInput)
                    .foregroundColor(themeManager.palette.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .stroke(themeManager.palette.borderCrisp, lineWidth: Border.thin))
                }
                .buttonStyle(.plain)
                #endif

                if !viewModel.workingDirectory.isEmpty {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.accentGreen)
                        Text("Workspace set")
                            .font(Typography.bodySmallSemibold)
                            .foregroundColor(.accentGreen)
                    }
                }

                // Auto-detected tools
                if toolDetectionDone && !detectedTools.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        Text("Detected Tools")
                            .font(Typography.captionSemibold)
                            .foregroundColor(themeManager.palette.textMuted)
                            .textCase(.uppercase)
                            .tracking(0.5)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: Spacing.md) {
                            ForEach(Array(detectedTools.enumerated()), id: \.offset) { _, tool in
                                HStack(spacing: Spacing.sm) {
                                    Image(systemName: tool.found ? "checkmark.circle.fill" : "xmark.circle")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(tool.found ? .accentGreen : themeManager.palette.textMuted.opacity(0.5))
                                    Text(tool.name)
                                        .font(Typography.captionSmallMedium)
                                        .foregroundColor(tool.found ? themeManager.palette.textPrimary : themeManager.palette.textMuted)
                                }
                                .padding(.horizontal, Spacing.lg)
                                .padding(.vertical, Spacing.sm)
                                .background(tool.found ? Color.accentGreen.opacity(0.08) : themeManager.palette.bgInput.opacity(0.5))
                                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                            }
                        }
                    }
                    .frame(maxWidth: 400)
                    .padding(Spacing.xl)
                    .background(themeManager.palette.bgCard.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                    .transition(.opacity)

                    // Install All Missing button
                    let missingTools = detectedTools.filter { !$0.found }
                    if !missingTools.isEmpty {
                        Button(action: { installMissingTools() }) {
                            HStack(spacing: Spacing.md) {
                                if isInstallingTools {
                                    ProgressView()
                                        .controlSize(.small)
                                        .tint(themeManager.palette.effectiveAccent)
                                } else {
                                    Image(systemName: "arrow.down.circle.fill")
                                        .font(Typography.bodySmall)
                                }
                                Text("Install All Missing (\(missingTools.count))")
                                    .font(Typography.bodySmallSemibold)
                            }
                            .frame(maxWidth: 400)
                            .padding(.vertical, Spacing.lg)
                            .foregroundColor(themeManager.palette.effectiveAccent)
                            .background(themeManager.palette.effectiveAccent.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                                .stroke(themeManager.palette.effectiveAccent.opacity(0.3), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .disabled(isInstallingTools)
                    }

                    if let msg = installToolsMessage {
                        Text(msg)
                            .font(Typography.captionSmall)
                            .foregroundColor(themeManager.palette.textMuted)
                            .frame(maxWidth: 400, alignment: .leading)
                    }
                }
            }
        }
        .padding(.horizontal, Spacing.huge)
        .onAppear { detectTools() }
    }

    // MARK: - Tool Detection

    func detectTools() {
        #if os(macOS)
        let tools: [(String, String, String)] = [
            ("git", "arrow.triangle.branch", "git"),
            ("node", "curlybraces", "node"),
            ("python3", "chevron.left.forwardslash.chevron.right", "python3"),
            ("swift", "swift", "swift"),
            ("cargo", "gearshape", "cargo"),
            ("go", "gearshape.2", "go"),
            ("docker", "shippingbox", "docker"),
            ("brew", "cup.and.saucer", "brew")
        ]
        var results: [(name: String, icon: String, found: Bool)] = []
        for (name, icon, cmd) in tools {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
            process.arguments = [cmd]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
                results.append((name: name, icon: icon, found: process.terminationStatus == 0))
            } catch {
                results.append((name: name, icon: icon, found: false))
            }
        }
        detectedTools = results
        toolDetectionDone = true
        #endif
    }

    // MARK: - Install Missing Tools

    func installMissingTools() {
        #if os(macOS)
        isInstallingTools = true
        installToolsMessage = nil

        // Check if brew exists
        let brewExists = FileManager.default.fileExists(atPath: "/opt/homebrew/bin/brew") ||
                        FileManager.default.fileExists(atPath: "/usr/local/bin/brew")

        guard brewExists else {
            // Show native install instructions when brew is not available
            installToolsMessage = "Homebrew not detected. Native installers coming soon."
            isInstallingTools = false
            return
        }

        let brewInstallable: [String: String] = [
            "node": "node",
            "python3": "python3",
            "go": "go",
            "cargo": "rust",
            "brew": "" // Can't install brew via brew
        ]
        let notBrewInstallable = ["docker", "brew"]

        let missing = detectedTools.filter { !$0.found }
        let toInstall = missing.compactMap { tool -> String? in
            guard !notBrewInstallable.contains(tool.name) else { return nil }
            return brewInstallable[tool.name] ?? tool.name
        }

        let skipped = missing.filter { notBrewInstallable.contains($0.name) }.map(\.name)

        guard !toInstall.isEmpty else {
            let skippedMsg = skipped.isEmpty ? "" : " Skipped: \(skipped.joined(separator: ", ")) (install manually)."
            installToolsMessage = "Nothing to install via Homebrew.\(skippedMsg)"
            isInstallingTools = false
            return
        }

        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/brew")
            // Fallback to /usr/local/bin/brew for Intel Macs
            if !FileManager.default.fileExists(atPath: "/opt/homebrew/bin/brew") {
                process.executableURL = URL(fileURLWithPath: "/usr/local/bin/brew")
            }
            process.arguments = ["install"] + toInstall
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
                process.waitUntilExit()
                await MainActor.run {
                    let skippedMsg = skipped.isEmpty ? "" : " Skipped: \(skipped.joined(separator: ", ")) (install manually)."
                    if process.terminationStatus == 0 {
                        installToolsMessage = "Installed successfully!\(skippedMsg)"
                    } else {
                        installToolsMessage = "Some installs may have failed. Check terminal.\(skippedMsg)"
                    }
                    isInstallingTools = false
                    detectTools()
                }
            } catch {
                await MainActor.run {
                    installToolsMessage = "Failed: \(error.localizedDescription)"
                    isInstallingTools = false
                }
            }
        }
        #endif
    }
}
