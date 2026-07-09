import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - Build Phase

/// Build engine state machine. Session E's run pipeline extends the succeeded
/// path with installing → launching → running(app).
enum BuildPhase: Equatable {
    case idle
    case building
    case succeeded(duration: TimeInterval, warnings: Int)
    case failed(errors: Int, warnings: Int)
    case cancelled

    var isActive: Bool { self == .building }

    /// Legal edges only: idle/terminal → building → terminal; terminal → idle.
    static func isLegalTransition(from: BuildPhase, to: BuildPhase) -> Bool {
        switch (from, to) {
        case (.idle, .building),
             (.succeeded, .building), (.failed, .building), (.cancelled, .building):
            return true
        case (.building, .succeeded), (.building, .failed), (.building, .cancelled):
            return true
        case (.succeeded, .idle), (.failed, .idle), (.cancelled, .idle):
            return true
        default:
            return false
        }
    }

    /// Maps a finished process to its terminal phase. A user cancel wins over
    /// whatever exit code the terminated process reports.
    static func terminal(
        exitCode: Int32,
        cancelled: Bool,
        duration: TimeInterval,
        errors: Int,
        warnings: Int
    ) -> BuildPhase {
        if cancelled { return .cancelled }
        return exitCode == 0
            ? .succeeded(duration: duration, warnings: warnings)
            : .failed(errors: errors, warnings: warnings)
    }
}

// MARK: - Build Destination

enum BuildDestination: Hashable, Identifiable {
    case mac
    case simulator(udid: String, name: String, booted: Bool)

    var id: String {
        switch self {
        case .mac: return "mac"
        case .simulator(let udid, _, _): return udid
        }
    }

    var label: String {
        switch self {
        case .mac: return "My Mac"
        case .simulator(_, let name, let booted): return booted ? "\(name) (Booted)" : name
        }
    }

    /// The `-destination` value xcodebuild expects.
    var xcodebuildArgument: String {
        switch self {
        case .mac: return "platform=macOS"
        case .simulator(let udid, _, _): return "id=\(udid)"
        }
    }

    /// Default pick: a booted simulator, else the first iPhone simulator, else My Mac.
    static func defaultDestination(from destinations: [BuildDestination]) -> BuildDestination? {
        if let booted = destinations.first(where: {
            if case .simulator(_, _, true) = $0 { return true } else { return false }
        }) {
            return booted
        }
        if let iphone = destinations.first(where: {
            if case .simulator(_, let name, _) = $0 { return name.localizedCaseInsensitiveContains("iPhone") }
            return false
        }) {
            return iphone
        }
        if destinations.contains(.mac) { return .mac }
        return destinations.first
    }
}

// MARK: - Chunk Line Buffer

/// Reassembles complete lines from arbitrary pipe chunks — a chunk can end
/// mid-line, and the remainder must join the next chunk.
struct ChunkLineBuffer {
    private var partial = ""

    mutating func consume(_ chunk: String) -> [String] {
        var pieces = (partial + chunk).components(separatedBy: "\n")
        partial = pieces.removeLast()
        return pieces.filter { !$0.isEmpty }
    }

    mutating func flushRemainder() -> String? {
        guard !partial.isEmpty else { return nil }
        defer { partial = "" }
        return partial
    }
}

// MARK: - Build Service

/// Drives xcodebuild / swift build for the open project: one build at a time,
/// streamed console output (ring-buffered + batch-flushed), parsed issues, and
/// scheme/destination state for the toolbar.
@MainActor
final class BuildService: ObservableObject {
    static let shared = BuildService()

    struct ConsoleLine: Identifiable, Equatable {
        let id: Int
        let text: String
        let isStderr: Bool
    }

    @Published private(set) var phase: BuildPhase = .idle
    @Published private(set) var consoleLines: [ConsoleLine] = []
    @Published private(set) var issues: [BuildError] = []
    @Published private(set) var schemes: [String] = []
    @Published private(set) var destinations: [BuildDestination] = [.mac]
    @Published var selectedScheme: String? {
        didSet { if selectedScheme != oldValue { prefetchBuildSettings() } }
    }
    @Published var selectedConfiguration = "Debug" {
        didSet { if selectedConfiguration != oldValue { prefetchBuildSettings() } }
    }
    @Published var selectedDestination: BuildDestination?

    private(set) var currentProject: Project?
    /// Session E's install step needs these; prefetched per scheme+config.
    private(set) var cachedBuildSettings: [String: XcodeProjectInspector.BuildSettings] = [:]

    let maxConsoleLines = 10_000
    private let flushThreshold = 50
    private let flushInterval: Duration = .milliseconds(100)

    private var pendingLines: [ConsoleLine] = []
    private var nextLineId = 0
    private var flushScheduled = false
    private var stdoutBuffer = ChunkLineBuffer()
    private var stderrBuffer = ChunkLineBuffer()
    /// Only lines the issue parser cares about — the full log can be huge.
    private var issueCandidates = ""
    private var wasCancelled = false
    private var buildStart: Date?
    #if os(macOS)
    private var process: Process?
    #endif

    init() {
        #if os(macOS)
        // Never orphan an xcodebuild: kill the active build when the app quits.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                BuildService.shared.stop()
            }
        }
        #endif
    }

    // MARK: - Project / scheme / destination state

    /// Called when the open project changes (ProjectStore.current).
    func refresh(for project: Project?) {
        currentProject = project
        schemes = []
        selectedScheme = nil
        cachedBuildSettings = [:]

        guard let project else {
            destinations = [.mac]
            selectedDestination = .mac
            return
        }

        switch project.kind {
        case .spmPackage, .plainFolder:
            destinations = [.mac]
            selectedDestination = .mac
        case .xcworkspace, .xcodeproj:
            let root = project.rootPath
            Task { @MainActor in
                let result = await Task.detached(priority: .userInitiated) {
                    XcodeProjectInspector.parse(dir: root)
                }.value
                guard self.currentProject?.rootPath == root else { return }
                self.schemes = result.schemes.map(\.name)
                self.selectedScheme = self.schemes.first
            }
            refreshDestinations()
        }
    }

    func refreshDestinations() {
        #if os(macOS)
        Task { @MainActor in
            let devices = await Task.detached(priority: .userInitiated) { () -> [SimulatorDevice]? in
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
                process.arguments = ["simctl", "list", "devices", "-j"]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = Pipe()
                guard (try? process.run()) != nil else { return nil }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                return SimulatorService.parseDeviceList(data)
            }.value

            let sims = (devices ?? [])
                .filter { $0.runtime.contains("iOS") }
                .map { BuildDestination.simulator(udid: $0.id, name: $0.name, booted: $0.state == .booted) }
            self.destinations = sims + [.mac]
            if self.selectedDestination == nil || !self.destinations.contains(self.selectedDestination!) {
                self.selectedDestination = BuildDestination.defaultDestination(from: self.destinations)
            }
        }
        #else
        destinations = [.mac]
        selectedDestination = .mac
        #endif
    }

    private func prefetchBuildSettings() {
        #if os(macOS)
        guard let project = currentProject,
              let container = project.containerPath,
              let scheme = selectedScheme else { return }
        let key = "\(scheme)|\(selectedConfiguration)"
        guard cachedBuildSettings[key] == nil else { return }
        let isWorkspace = project.kind == .xcworkspace
        let config = selectedConfiguration
        Task { @MainActor in
            let settings = await XcodeProjectInspector.buildSettings(
                containerPath: container,
                isWorkspace: isWorkspace,
                scheme: scheme,
                configuration: config
            )
            if let settings {
                self.cachedBuildSettings[key] = settings
            }
        }
        #endif
    }

    // MARK: - Build

    /// Kicks off a build of the selected scheme/config/destination.
    /// No-op while a build is already active.
    func build() {
        #if os(macOS)
        guard !phase.isActive, let project = currentProject else { return }

        let executable: String
        var arguments: [String]
        switch project.kind {
        case .plainFolder:
            return
        case .spmPackage:
            executable = "/usr/bin/swift"
            arguments = ["build"]
        case .xcworkspace, .xcodeproj:
            guard let container = project.containerPath, let scheme = selectedScheme else { return }
            executable = "/usr/bin/xcodebuild"
            arguments = [
                project.kind == .xcworkspace ? "-workspace" : "-project", container,
                "-scheme", scheme,
                "-configuration", selectedConfiguration
            ]
            if let destination = selectedDestination {
                arguments += ["-destination", destination.xcodebuildArgument]
            }
            arguments.append("build")
        }

        transition(to: .building)
        consoleLines = []
        pendingLines = []
        issues = []
        issueCandidates = ""
        stdoutBuffer = ChunkLineBuffer()
        stderrBuffer = ChunkLineBuffer()
        wasCancelled = false
        buildStart = Date()
        appendLine("$ \(executable) \(arguments.joined(separator: " "))", isStderr: false)

        let workingDir = project.rootPath
        Task.detached(priority: .userInitiated) { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.currentDirectoryURL = URL(fileURLWithPath: workingDir)
            process.environment = ProcessInfo.processInfo.environment

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                Task { @MainActor [weak self] in
                    self?.consumeChunk(text, isStderr: false)
                }
            }
            errPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                Task { @MainActor [weak self] in
                    self?.consumeChunk(text, isStderr: true)
                }
            }

            do {
                try process.run()
                await MainActor.run { [weak self] in
                    self?.process = process
                }
                process.waitUntilExit()
            } catch {
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                await MainActor.run { [weak self] in
                    self?.appendLine("Error: \(error.localizedDescription)", isStderr: true)
                    self?.finish(exitCode: -1)
                }
                return
            }

            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            let exitCode = process.terminationStatus
            await MainActor.run { [weak self] in
                self?.finish(exitCode: exitCode)
            }
        }
        #endif
    }

    /// Terminates the active build. Safe to call when idle.
    func stop() {
        #if os(macOS)
        guard phase.isActive else { return }
        wasCancelled = true
        process?.terminate()
        #endif
    }

    private func finish(exitCode: Int32) {
        #if os(macOS)
        process = nil
        #endif
        if let remainder = stdoutBuffer.flushRemainder() { bufferLine(remainder, isStderr: false) }
        if let remainder = stderrBuffer.flushRemainder() { bufferLine(remainder, isStderr: true) }
        flushPending()

        issues = BuildErrorParserEngine.parse(issueCandidates)
        let errorCount = issues.filter { $0.severity == .error }.count
        let warningCount = issues.filter { $0.severity == .warning }.count
        let duration = buildStart.map { Date().timeIntervalSince($0) } ?? 0

        let terminal = BuildPhase.terminal(
            exitCode: exitCode,
            cancelled: wasCancelled,
            duration: duration,
            errors: errorCount,
            warnings: warningCount
        )
        transition(to: terminal)

        // Auto-open the build console on FAILURE only — success stays quiet.
        if case .failed = terminal {
            UserDefaults.standard.set("issues", forKey: "BuildConsoleTab")
            UserDefaults.standard.set(PanelTab.build.rawValue, forKey: "SelectedPanel")
            UserDefaults.standard.set(false, forKey: "RightPanelCollapsed")
        }
        buildStart = nil
    }

    private func transition(to newPhase: BuildPhase) {
        guard BuildPhase.isLegalTransition(from: phase, to: newPhase) else {
            GRumpLogger.general.error("BuildService: illegal transition \(String(describing: self.phase)) → \(String(describing: newPhase))")
            return
        }
        phase = newPhase
    }

    // MARK: - Console streaming (ring buffer + batched flush)

    private func consumeChunk(_ text: String, isStderr: Bool) {
        let lines = isStderr ? stderrBuffer.consume(text) : stdoutBuffer.consume(text)
        for line in lines {
            bufferLine(line, isStderr: isStderr)
        }
        if pendingLines.count >= flushThreshold {
            flushPending()
        } else {
            scheduleFlush()
        }
    }

    private func bufferLine(_ text: String, isStderr: Bool) {
        pendingLines.append(ConsoleLine(id: nextLineId, text: text, isStderr: isStderr))
        nextLineId += 1
        if text.contains(": error: ") || text.contains(": warning: ")
            || text.contains(": note: ") || text.contains("fix-it:") {
            issueCandidates += text + "\n"
        }
    }

    private func appendLine(_ text: String, isStderr: Bool) {
        bufferLine(text, isStderr: isStderr)
        flushPending()
    }

    private func scheduleFlush() {
        guard !flushScheduled else { return }
        flushScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.flushInterval)
            self.flushScheduled = false
            self.flushPending()
        }
    }

    private func flushPending() {
        guard !pendingLines.isEmpty else { return }
        consoleLines.append(contentsOf: pendingLines)
        pendingLines.removeAll(keepingCapacity: true)
        if consoleLines.count > maxConsoleLines {
            consoleLines.removeFirst(consoleLines.count - maxConsoleLines)
        }
    }
}
