import SwiftUI

// MARK: - Log Entry Model

struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let level: LogLevel
    let subsystem: String
    let category: String
    let message: String

    enum LogLevel: String, CaseIterable {
        case debug = "Debug"
        case info = "Info"
        case notice = "Notice"
        case error = "Error"
        case fault = "Fault"

        var icon: String {
            switch self {
            case .debug: return "ant"
            case .info: return "info.circle"
            case .notice: return "bell"
            case .error: return "exclamationmark.triangle"
            case .fault: return "xmark.octagon"
            }
        }

        var color: Color {
            switch self {
            case .debug: return Color(red: 0.5, green: 0.5, blue: 0.6)
            case .info: return Color(red: 0.3, green: 0.6, blue: 1.0)
            case .notice: return .orange
            case .error: return .red
            case .fault: return Color(red: 0.9, green: 0.2, blue: 0.3)
            }
        }
    }
}

// MARK: - Crash Report

struct CrashReport: Identifiable {
    let id = UUID()
    let path: String
    let processName: String
    let date: Date
    let exceptionType: String
    let threadBacktrace: String
    let rawContent: String
}

// MARK: - Log Service

@MainActor
final class LogService: ObservableObject {
    @Published var entries: [LogEntry] = []
    @Published var isStreaming = false
    @Published var crashReports: [CrashReport] = []
    @Published var filterLevel: LogEntry.LogLevel?
    @Published var filterText: String = ""

    #if os(macOS)
    private var logProcess: Process?
    #endif

    var filteredEntries: [LogEntry] {
        var result = entries
        if let level = filterLevel {
            result = result.filter { $0.level == level }
        }
        if !filterText.isEmpty {
            result = result.filter {
                $0.message.localizedCaseInsensitiveContains(filterText) ||
                $0.subsystem.localizedCaseInsensitiveContains(filterText) ||
                $0.category.localizedCaseInsensitiveContains(filterText)
            }
        }
        return result
    }

    func startStreaming() {
        stopStreaming()
        isStreaming = true

        #if os(macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = ["stream", "--style", "compact", "--level", "info"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }
            let entries = LogService.parseLine(line)
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.entries.append(contentsOf: entries)
                // Keep max 5000 entries
                if self.entries.count > 5000 {
                    self.entries.removeFirst(self.entries.count - 5000)
                }
            }
        }

        try? process.run()
        logProcess = process
        #endif
    }

    func stopStreaming() {
        #if os(macOS)
        logProcess?.terminate()
        logProcess = nil
        #endif
        isStreaming = false
    }

    func clearLogs() {
        entries.removeAll()
    }

    func loadCrashReports() {
        Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            let diagDir = NSHomeDirectory() + "/Library/Logs/DiagnosticReports"
            guard let files = try? fm.contentsOfDirectory(atPath: diagDir) else {
                return
            }

            var reports: [CrashReport] = []
            for file in files.sorted().reversed().prefix(20) {
                let path = (diagDir as NSString).appendingPathComponent(file)
                guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { continue }

                let processName = LogService.extractField(from: content, prefix: "Process:") ?? file
                let exceptionType = LogService.extractField(from: content, prefix: "Exception Type:") ?? "Unknown"
                let attrs = try? fm.attributesOfItem(atPath: path)
                let date = attrs?[.modificationDate] as? Date ?? Date()

                // Extract thread backtrace (first crash thread)
                var backtrace = ""
                let lines = content.components(separatedBy: "\n")
                var inCrashThread = false
                for line in lines {
                    if line.contains("Crashed:") || line.contains("Thread 0") {
                        inCrashThread = true
                    } else if inCrashThread && line.isEmpty {
                        break
                    }
                    if inCrashThread {
                        backtrace += line + "\n"
                    }
                }

                reports.append(CrashReport(
                    path: path, processName: processName, date: date,
                    exceptionType: exceptionType, threadBacktrace: backtrace,
                    rawContent: content
                ))
            }

            await MainActor.run {
                self.crashReports = reports
            }
        }
    }

    nonisolated static func parseLine(_ rawLine: String) -> [LogEntry] {
        rawLine.components(separatedBy: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }

            let level: LogEntry.LogLevel
            if trimmed.contains("Error") || trimmed.contains("<Error>") { level = .error } else if trimmed.contains("Fault") || trimmed.contains("<Fault>") { level = .fault } else if trimmed.contains("Notice") || trimmed.contains("<Notice>") { level = .notice } else if trimmed.contains("Debug") || trimmed.contains("<Debug>") { level = .debug } else { level = .info }

            return LogEntry(
                timestamp: Date(), level: level,
                subsystem: "", category: "",
                message: trimmed
            )
        }
    }

    nonisolated private static func extractField(from content: String, prefix: String) -> String? {
        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(prefix) {
                return trimmed.replacingOccurrences(of: prefix, with: "").trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    deinit {
        #if os(macOS)
        logProcess?.terminate()
        #endif
    }
}

// MARK: - Log Viewer Panel

struct LogViewerPanel: View {
    @EnvironmentObject var themeManager: ThemeManager
    @StateObject private var service = LogService()
    @State private var selectedTab: LogTab = .console
    @State private var searchText = ""

    enum LogTab: String, CaseIterable {
        case console = "Console"
        case crashes = "Crashes"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: Spacing.lg) {
                Picker("", selection: $selectedTab) {
                    ForEach(LogTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)

                Spacer()

                if selectedTab == .console {
                    if service.isStreaming {
                        Button(action: { service.stopStreaming() }) {
                            HStack(spacing: Spacing.xs) {
                                Circle().fill(Color.red).frame(width: 6, height: 6)
                                Text("Stop")
                                    .font(Typography.captionSmallSemibold)
                            }
                            .foregroundColor(.red)
                        }
                        .buttonStyle(ScaleButtonStyle())
                    } else {
                        Button(action: { service.startStreaming() }) {
                            HStack(spacing: Spacing.xs) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 10))
                                Text("Stream")
                                    .font(Typography.captionSmallSemibold)
                            }
                            .foregroundColor(.accentGreen)
                        }
                        .buttonStyle(ScaleButtonStyle())
                    }

                    Button(action: { service.clearLogs() }) {
                        Image(systemName: "trash")
                            .font(Typography.captionSmall)
                            .foregroundColor(themeManager.palette.textMuted)
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .help("Clear logs")
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.lg)

            // Search
            HStack(spacing: Spacing.md) {
                Image(systemName: "magnifyingglass")
                    .font(Typography.captionSmall)
                    .foregroundColor(themeManager.palette.textMuted)
                TextField("Filter logs…", text: $searchText)
                    .font(Typography.bodySmall)
                    .textFieldStyle(.plain)
                    .onChange(of: searchText) { _, newValue in
                        service.filterText = newValue
                    }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.lg)
            .background(themeManager.palette.bgInput)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.md)

            // Level filters
            if selectedTab == .console {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.sm) {
                        levelChip(nil, label: "All")
                        ForEach(LogEntry.LogLevel.allCases, id: \.self) { level in
                            levelChip(level, label: level.rawValue)
                        }
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.bottom, Spacing.md)
                }
            }

            Rectangle()
                .fill(themeManager.palette.borderSubtle)
                .frame(height: Border.thin)

            // Content
            switch selectedTab {
            case .console:
                consoleView
            case .crashes:
                crashesView
            }
        }
        .background(themeManager.palette.bgDark)
        .onAppear { service.loadCrashReports() }
    }

    private func levelChip(_ level: LogEntry.LogLevel?, label: String) -> some View {
        let isSelected = service.filterLevel == level
        return Button(action: { service.filterLevel = level }) {
            Text(label)
                .font(Typography.micro)
                .foregroundColor(isSelected ? (level?.color ?? themeManager.palette.effectiveAccent) : themeManager.palette.textMuted)
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.sm)
                .background(isSelected ? (level?.color ?? themeManager.palette.effectiveAccent).opacity(0.12) : themeManager.palette.bgElevated)
                .clipShape(Capsule())
        }
        .buttonStyle(ScaleButtonStyle())
    }

    private var consoleView: some View {
        Group {
            if service.filteredEntries.isEmpty {
                VStack(spacing: Spacing.xxl) {
                    Spacer()
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 36, weight: .light))
                        .foregroundColor(themeManager.palette.textMuted)
                    Text(service.isStreaming ? "Waiting for logs…" : "Start streaming to capture logs")
                        .font(Typography.bodySmallMedium)
                        .foregroundColor(themeManager.palette.textSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(service.filteredEntries) { entry in
                                LogEntryRow(entry: entry)
                                    .id(entry.id)
                            }
                        }
                        .padding(.vertical, Spacing.sm)
                    }
                    .onChange(of: service.entries.count) { _, _ in
                        if let last = service.filteredEntries.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    private var crashesView: some View {
        Group {
            if service.crashReports.isEmpty {
                VStack(spacing: Spacing.xxl) {
                    Spacer()
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 36, weight: .light))
                        .foregroundColor(.accentGreen)
                    Text("No recent crash reports")
                        .font(Typography.bodySmallMedium)
                        .foregroundColor(themeManager.palette.textSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: Spacing.md) {
                        ForEach(service.crashReports) { report in
                            CrashReportRow(report: report)
                        }
                    }
                    .padding(Spacing.lg)
                }
            }
        }
    }
}

// MARK: - Log Entry Row

struct LogEntryRow: View {
    @EnvironmentObject var themeManager: ThemeManager
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: entry.level.icon)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(entry.level.color)
                .frame(width: 12)

            Text(entry.message)
                .font(Typography.codeSmall)
                .foregroundColor(themeManager.palette.textPrimary)
                .lineLimit(3)
                .textSelection(.enabled)

            Spacer()
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, 2)
    }
}

// MARK: - Crash Report Row

struct CrashReportRow: View {
    @EnvironmentObject var themeManager: ThemeManager
    let report: CrashReport
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { isExpanded.toggle() }) {
                HStack(spacing: Spacing.lg) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(Typography.bodySmall)
                        .foregroundColor(.red)

                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(report.processName)
                            .font(Typography.captionSmallSemibold)
                            .foregroundColor(themeManager.palette.textPrimary)
                        Text(report.exceptionType)
                            .font(Typography.micro)
                            .foregroundColor(themeManager.palette.textMuted)
                    }

                    Spacer()

                    Text(report.date, style: .relative)
                        .font(Typography.micro)
                        .foregroundColor(themeManager.palette.textMuted)

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(themeManager.palette.textMuted)
                }
                .padding(Spacing.xl)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                ScrollView {
                    Text(report.threadBacktrace.isEmpty ? report.rawContent.prefix(2000).description : report.threadBacktrace)
                        .font(Typography.codeSmall)
                        .foregroundColor(themeManager.palette.textSecondary)
                        .textSelection(.enabled)
                        .padding(Spacing.xl)
                }
                .frame(maxHeight: 300)
            }
        }
        .background(themeManager.palette.bgElevated.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .stroke(themeManager.palette.borderSubtle, lineWidth: Border.hairline)
        )
    }
}
