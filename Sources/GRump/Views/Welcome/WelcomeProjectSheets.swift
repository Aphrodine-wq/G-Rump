// MARK: - Welcome Window Sheets
//
// Clone Repository and New Project sheets for the welcome window.
// Both hand a ready-to-open path back to the welcome window on success.

#if os(macOS)
import SwiftUI
import AppKit

// MARK: - Clone Model

/// Runs `git clone` off the main thread, streaming stderr (git's progress
/// channel) back for display. Cancelable; a watchdog kills clones that hang.
@MainActor
final class WelcomeCloneModel: ObservableObject {
    @Published var isCloning = false
    @Published var output = ""
    @Published var failed = false

    private var process: Process?
    private static let timeout: Duration = .seconds(300)

    /// "https://host/owner/repo.git" → "repo"
    nonisolated static func repoName(from urlString: String) -> String {
        var name = urlString.split(separator: "/").last.map(String.init) ?? "repository"
        if name.hasSuffix(".git") { name = String(name.dropLast(4)) }
        return name.isEmpty ? "repository" : name
    }

    func clone(repoURL: String, into destinationDir: String, onSuccess: @escaping @MainActor (String) -> Void) {
        let trimmed = repoURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isCloning else { return }
        let target = (destinationDir as NSString).appendingPathComponent(Self.repoName(from: trimmed))
        guard !FileManager.default.fileExists(atPath: target) else {
            output = "\(target) already exists — pick a different destination."
            failed = true
            return
        }

        isCloning = true
        failed = false
        output = ""

        Task.detached(priority: .userInitiated) { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["git", "clone", "--progress", trimmed, target]
            let errPipe = Pipe()
            process.standardError = errPipe
            process.standardOutput = Pipe()

            errPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                Task { @MainActor [weak self] in
                    self?.output += text
                }
            }

            do {
                try process.run()
                await MainActor.run { [weak self] in
                    self?.process = process
                }
                process.waitUntilExit()
            } catch {
                errPipe.fileHandleForReading.readabilityHandler = nil
                await MainActor.run { [weak self] in
                    self?.output += "Error: \(error.localizedDescription)"
                    self?.failed = true
                    self?.isCloning = false
                }
                return
            }

            errPipe.fileHandleForReading.readabilityHandler = nil
            let status = process.terminationStatus
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.process = nil
                guard self.isCloning else { return }   // cancelled — state already settled
                self.isCloning = false
                if status == 0 {
                    onSuccess(target)
                } else {
                    self.failed = true
                }
            }
        }

        Task { [weak self] in
            try? await Task.sleep(for: Self.timeout)
            guard let self, self.isCloning else { return }
            self.output += "\nTimed out after 5 minutes — cancelled."
            self.cancel()
        }
    }

    func cancel() {
        guard isCloning else { return }
        isCloning = false
        failed = true
        output += "\nCancelled."
        process?.terminate()
        process = nil
    }
}

// MARK: - Clone Repository Sheet

struct CloneRepositorySheet: View {
    let onCloned: @MainActor (String) -> Void
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = WelcomeCloneModel()

    @State private var repoURL = ""
    @State private var destinationDir = WelcomeProjectDefaults.location

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            Text("Clone Repository")
                .font(Typography.bodySemibold)
                .foregroundColor(themeManager.palette.textPrimary)

            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Repository URL")
                    .font(Typography.captionSemibold)
                    .foregroundColor(themeManager.palette.textMuted)
                TextField("https://github.com/owner/repo.git", text: $repoURL)
                    .textFieldStyle(.roundedBorder)
                    .font(Typography.bodySmall)
                    .disabled(model.isCloning)
            }

            WelcomeLocationPicker(title: "Clone into", path: $destinationDir)
                .disabled(model.isCloning)

            if !model.output.isEmpty {
                ScrollView(.vertical) {
                    Text(model.output)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(model.failed ? .red : themeManager.palette.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(height: 90)
                .padding(Spacing.md)
                .background(themeManager.palette.bgInput)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }

            HStack {
                Button("Cancel") {
                    if model.isCloning {
                        model.cancel()
                    }
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                if model.isCloning {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, Spacing.md)
                }

                Button("Clone") {
                    model.clone(repoURL: repoURL, into: destinationDir) { path in
                        dismiss()
                        onCloned(path)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.isCloning || repoURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(Spacing.colossal)
        .frame(width: 460)
    }
}

// MARK: - New Project Sheet

struct NewProjectSheet: View {
    let onCreated: @MainActor (String) -> Void
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) private var dismiss

    @State private var projectName = ""
    @State private var location = WelcomeProjectDefaults.location
    @State private var initializeGit = true
    @State private var errorMessage: String?

    private var trimmedName: String {
        projectName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            Text("New Project")
                .font(Typography.bodySemibold)
                .foregroundColor(themeManager.palette.textPrimary)

            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Name")
                    .font(Typography.captionSemibold)
                    .foregroundColor(themeManager.palette.textMuted)
                TextField("MyProject", text: $projectName)
                    .textFieldStyle(.roundedBorder)
                    .font(Typography.bodySmall)
            }

            WelcomeLocationPicker(title: "Create in", path: $location)

            Toggle("Create Git repository", isOn: $initializeGit)
                .toggleStyle(.checkbox)
                .font(Typography.bodySmall)

            if let errorMessage {
                Text(errorMessage)
                    .font(Typography.captionSmall)
                    .foregroundColor(.red)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create") { createProject() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty)
            }
        }
        .padding(Spacing.colossal)
        .frame(width: 460)
    }

    private func createProject() {
        let target = (location as NSString).appendingPathComponent(trimmedName)
        guard !FileManager.default.fileExists(atPath: target) else {
            errorMessage = "\((target as NSString).abbreviatingWithTildeInPath) already exists."
            return
        }
        do {
            try FileManager.default.createDirectory(atPath: target, withIntermediateDirectories: true)
        } catch {
            errorMessage = "Couldn't create folder: \(error.localizedDescription)"
            return
        }

        if initializeGit {
            // Best-effort: a failed git init still leaves a usable folder.
            Task.detached(priority: .utility) {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = ["git", "init", target]
                process.standardOutput = Pipe()
                process.standardError = Pipe()
                do {
                    try process.run()
                    process.waitUntilExit()
                } catch {
                    GRumpLogger.general.error("git init failed: \(error.localizedDescription)")
                }
            }
        }

        dismiss()
        onCreated(target)
    }
}

// MARK: - Shared Bits

enum WelcomeProjectDefaults {
    /// ~/Developer when it exists (the macOS convention), else home.
    static var location: String {
        let developer = NSHomeDirectory() + "/Developer"
        return FileManager.default.fileExists(atPath: developer) ? developer : NSHomeDirectory()
    }
}

struct WelcomeLocationPicker: View {
    let title: String
    @Binding var path: String
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(title)
                .font(Typography.captionSemibold)
                .foregroundColor(themeManager.palette.textMuted)
            HStack(spacing: Spacing.md) {
                Text((path as NSString).abbreviatingWithTildeInPath)
                    .font(Typography.bodySmall)
                    .foregroundColor(themeManager.palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Choose…") {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.canCreateDirectories = true
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK, let url = panel.url {
                        path = url.path
                    }
                }
                .font(Typography.bodySmallMedium)
            }
        }
    }
}
#endif
