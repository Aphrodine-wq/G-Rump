import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - Simulator Device Model

struct SimulatorDevice: Identifiable, Hashable {
    let id: String // UDID
    let name: String
    let runtime: String
    let state: DeviceState
    let deviceType: String

    enum DeviceState: String, Hashable {
        case booted = "Booted"
        case shutdown = "Shutdown"
        case creating = "Creating"
        case unknown = "Unknown"

        var color: Color {
            switch self {
            case .booted: return .accentGreen
            case .shutdown: return Color(red: 0.5, green: 0.5, blue: 0.6)
            case .creating: return .orange
            case .unknown: return .red
            }
        }

        var icon: String {
            switch self {
            case .booted: return "power"
            case .shutdown: return "power.circle"
            case .creating: return "hourglass"
            case .unknown: return "questionmark.circle"
            }
        }
    }

    var deviceIcon: String {
        let lower = name.lowercased()
        if lower.contains("ipad") { return "ipad" }
        if lower.contains("watch") { return "applewatch" }
        if lower.contains("tv") { return "appletv" }
        if lower.contains("vision") { return "visionpro" }
        return "iphone"
    }

    var shortRuntime: String {
        // "com.apple.CoreSimulator.SimRuntime.iOS-17-2" → "iOS 17.2"
        let parts = runtime.components(separatedBy: ".")
        if let last = parts.last {
            return last.replacingOccurrences(of: "-", with: ".")
        }
        return runtime
    }
}

// MARK: - Simulator Service

@MainActor
final class SimulatorService: ObservableObject {
    static let shared = SimulatorService()

    @Published var devices: [SimulatorDevice] = []
    @Published var isLoading = false
    #if os(macOS)
    @Published var lastScreenshot: NSImage?
    #endif
    @Published var errorMessage: String?

    /// Pure parser for `simctl list devices -j` output: available devices only,
    /// booted first, then by name.
    nonisolated static func parseDeviceList(_ data: Data) -> [SimulatorDevice]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let devicesDict = json["devices"] as? [String: [[String: Any]]] else {
            return nil
        }

        var parsed: [SimulatorDevice] = []
        for (runtime, deviceList) in devicesDict {
            for device in deviceList {
                guard let udid = device["udid"] as? String,
                      let name = device["name"] as? String,
                      let stateStr = device["state"] as? String,
                      let isAvailable = device["isAvailable"] as? Bool,
                      isAvailable else { continue }

                let state: SimulatorDevice.DeviceState
                switch stateStr {
                case "Booted": state = .booted
                case "Shutdown": state = .shutdown
                case "Creating": state = .creating
                default: state = .unknown
                }

                let deviceType = (device["deviceTypeIdentifier"] as? String) ?? ""
                parsed.append(SimulatorDevice(
                    id: udid, name: name, runtime: runtime,
                    state: state, deviceType: deviceType
                ))
            }
        }

        parsed.sort { a, b in
            if a.state == .booted && b.state != .booted { return true }
            if a.state != .booted && b.state == .booted { return false }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
        return parsed
    }

    func refresh() {
        isLoading = true
        errorMessage = nil
        #if os(macOS)
        Task.detached(priority: .userInitiated) {
            do {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
                process.arguments = ["simctl", "list", "devices", "-j"]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = Pipe()
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                guard let parsed = Self.parseDeviceList(data) else {
                    await MainActor.run {
                        self.isLoading = false
                        self.errorMessage = "Failed to parse simulator list"
                    }
                    return
                }

                await MainActor.run {
                    self.devices = parsed
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
        #else
        isLoading = false
        errorMessage = "Simulators not available on this platform"
        #endif
    }

    func boot(_ device: SimulatorDevice) {
        #if os(macOS)
        runSimctl(["boot", device.id])
        #endif
    }

    func shutdown(_ device: SimulatorDevice) {
        #if os(macOS)
        runSimctl(["shutdown", device.id])
        #endif
    }

    func screenshot(_ device: SimulatorDevice) {
        #if os(macOS)
        Task.detached(priority: .userInitiated) {
            let tempPath = FileManager.default.temporaryDirectory
                .appendingPathComponent("sim_screenshot_\(Int(Date().timeIntervalSince1970)).png").path
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = ["simctl", "io", device.id, "screenshot", tempPath]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            try? process.run()
            process.waitUntilExit()

            if let image = NSImage(contentsOfFile: tempPath) {
                await MainActor.run {
                    self.lastScreenshot = image
                }
            }
        }
        #endif
    }

    func openSimulatorApp() {
        #if os(macOS)
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iphonesimulator") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
        #endif
    }

    #if os(macOS)
    private func runSimctl(_ args: [String]) {
        Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = ["simctl"] + args
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            try? process.run()
            process.waitUntilExit()
            try? await Task.sleep(for: .seconds(1))
            await self.refresh()
        }
    }
    #endif
}

// MARK: - Simulator Dashboard View

struct SimulatorDashboardView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject private var service = SimulatorService.shared
    @State private var searchText = ""
    @State private var showScreenshot = false

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: Spacing.lg) {
                Text("Simulators")
                    .font(Typography.captionSmallSemibold)
                    .foregroundColor(themeManager.palette.textSecondary)

                Spacer()

                Button(action: { service.openSimulatorApp() }) {
                    Image(systemName: "arrow.up.forward.app")
                        .font(Typography.captionSmall)
                        .foregroundColor(themeManager.palette.textMuted)
                }
                .buttonStyle(ScaleButtonStyle())
                .help("Open Simulator.app")

                Button(action: { service.refresh() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(Typography.captionSmall)
                        .foregroundColor(themeManager.palette.textMuted)
                }
                .buttonStyle(ScaleButtonStyle())
                .help("Refresh")
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.lg)

            // Search
            HStack(spacing: Spacing.md) {
                Image(systemName: "magnifyingglass")
                    .font(Typography.captionSmall)
                    .foregroundColor(themeManager.palette.textMuted)
                TextField("Filter devices…", text: $searchText)
                    .font(Typography.bodySmall)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.lg)
            .background(themeManager.palette.bgInput)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.md)

            Rectangle()
                .fill(themeManager.palette.borderSubtle)
                .frame(height: Border.thin)

            if service.isLoading && service.devices.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = service.errorMessage {
                VStack(spacing: Spacing.xxl) {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 28))
                        .foregroundColor(.accentOrange)
                    Text(error)
                        .font(Typography.bodySmall)
                        .foregroundColor(themeManager.palette.textMuted)
                    Button("Retry") { service.refresh() }
                        .buttonStyle(ScaleButtonStyle())
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: Spacing.sm) {
                        ForEach(filteredDevices) { device in
                            SimulatorDeviceRow(device: device, service: service)
                        }
                    }
                    .padding(Spacing.lg)
                }
            }

            // Screenshot preview
            #if os(macOS)
            if let screenshot = service.lastScreenshot {
                Rectangle()
                    .fill(themeManager.palette.borderSubtle)
                    .frame(height: Border.thin)

                HStack(spacing: Spacing.lg) {
                    Image(nsImage: screenshot)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md))

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Screenshot captured")
                            .font(Typography.captionSmallSemibold)
                            .foregroundColor(themeManager.palette.textPrimary)
                        Text("Click to send to chat for AI analysis")
                            .font(Typography.micro)
                            .foregroundColor(themeManager.palette.textMuted)
                    }

                    Spacer()

                    Button(action: { service.lastScreenshot = nil }) {
                        Image(systemName: "xmark")
                            .font(Typography.captionSmall)
                            .foregroundColor(themeManager.palette.textMuted)
                    }
                    .buttonStyle(.plain)
                }
                .padding(Spacing.lg)
                .background(themeManager.palette.bgCard)
            }
            #endif
        }
        .background(themeManager.palette.bgDark)
        .onAppear { service.refresh() }
    }

    private var filteredDevices: [SimulatorDevice] {
        guard !searchText.isEmpty else { return service.devices }
        return service.devices.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.shortRuntime.localizedCaseInsensitiveContains(searchText)
        }
    }
}

// MARK: - Device Row

struct SimulatorDeviceRow: View {
    @EnvironmentObject var themeManager: ThemeManager
    let device: SimulatorDevice
    @ObservedObject var service: SimulatorService
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Spacing.xl) {
            // Device icon
            Image(systemName: device.deviceIcon)
                .font(.system(size: 18, weight: .light))
                .foregroundColor(device.state == .booted ? themeManager.palette.effectiveAccent : themeManager.palette.textMuted)
                .frame(width: 28)

            // Info
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(device.name)
                    .font(Typography.bodySmallMedium)
                    .foregroundColor(themeManager.palette.textPrimary)
                    .lineLimit(1)

                HStack(spacing: Spacing.md) {
                    // State badge
                    HStack(spacing: Spacing.xs) {
                        Circle()
                            .fill(device.state.color)
                            .frame(width: 6, height: 6)
                        Text(device.state.rawValue)
                            .font(Typography.micro)
                            .foregroundColor(device.state.color)
                    }

                    Text(device.shortRuntime)
                        .font(Typography.micro)
                        .foregroundColor(themeManager.palette.textMuted)
                }
            }

            Spacer()

            // Actions (on hover)
            if isHovered {
                HStack(spacing: Spacing.md) {
                    if device.state == .booted {
                        Button(action: { service.screenshot(device) }) {
                            Image(systemName: "camera")
                                .font(Typography.captionSmall)
                                .foregroundColor(themeManager.palette.textMuted)
                        }
                        .buttonStyle(ScaleButtonStyle())
                        .help("Screenshot")

                        Button(action: { service.shutdown(device) }) {
                            Image(systemName: "stop.circle")
                                .font(Typography.captionSmall)
                                .foregroundColor(.red.opacity(0.8))
                        }
                        .buttonStyle(ScaleButtonStyle())
                        .help("Shutdown")
                    } else {
                        Button(action: { service.boot(device) }) {
                            Image(systemName: "play.circle")
                                .font(Typography.captionSmall)
                                .foregroundColor(.accentGreen)
                        }
                        .buttonStyle(ScaleButtonStyle())
                        .help("Boot")
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(isHovered ? themeManager.palette.bgElevated.opacity(0.5) : Color.clear)
        )
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: Anim.instant), value: isHovered)
    }
}
