import SwiftUI
import Foundation

// MARK: - LSP Message Models

struct LSPDiagnostic: Identifiable, Hashable {
    let id = UUID()
    let file: String
    let line: Int
    let column: Int
    let severity: DiagnosticSeverity
    let message: String
    let source: String

    enum DiagnosticSeverity: Int, Hashable {
        case error = 1
        case warning = 2
        case information = 3
        case hint = 4

        var icon: String {
            switch self {
            case .error: return "xmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .information: return "info.circle.fill"
            case .hint: return "lightbulb.fill"
            }
        }

        var color: Color {
            switch self {
            case .error: return .red
            case .warning: return .orange
            case .information: return Color(red: 0.3, green: 0.6, blue: 1.0)
            case .hint: return Color(red: 0.5, green: 0.5, blue: 0.6)
            }
        }

        var label: String {
            switch self {
            case .error: return "Error"
            case .warning: return "Warning"
            case .information: return "Info"
            case .hint: return "Hint"
            }
        }
    }
}

struct LSPCompletionItem: Identifiable, Hashable {
    let id = UUID()
    let label: String
    let detail: String?
    let kind: CompletionKind
    let insertText: String?

    enum CompletionKind: Int, Hashable {
        case text = 1, method = 2, function = 3, constructor = 4
        case field = 5, variable = 6, classKind = 7, interface = 8
        case module = 9, property = 10, unit = 11, value = 12
        case enumCase = 13, keyword = 14, snippet = 15, color = 16
        case file = 17, reference = 18, folder = 19, enumMember = 20
        case constant = 21, structKind = 22, event = 23, operatorKind = 24
        case typeParameter = 25
        case unknown = 0

        var icon: String {
            switch self {
            case .method, .function: return "f.square"
            case .variable, .field, .property: return "v.square"
            case .classKind, .interface, .structKind: return "c.square"
            case .enumCase, .enumMember: return "e.square"
            case .keyword: return "k.square"
            case .module: return "m.square"
            case .snippet: return "text.badge.plus"
            case .constructor: return "hammer"
            case .constant: return "number.square"
            case .typeParameter: return "t.square"
            default: return "textformat"
            }
        }

        var color: Color {
            switch self {
            case .method, .function: return Color(red: 0.6, green: 0.4, blue: 0.9)
            case .variable, .field, .property: return Color(red: 0.3, green: 0.7, blue: 1.0)
            case .classKind, .interface, .structKind: return Color(red: 1.0, green: 0.6, blue: 0.2)
            case .enumCase, .enumMember: return Color(red: 0.3, green: 0.8, blue: 0.5)
            case .keyword: return Color(red: 0.9, green: 0.4, blue: 0.5)
            case .module: return Color(red: 0.8, green: 0.7, blue: 0.3)
            default: return Color(red: 0.5, green: 0.5, blue: 0.6)
            }
        }
    }
}

struct LSPHoverInfo {
    let contents: String
    let range: NSRange?
}

struct LSPLocation: Identifiable {
    let id = UUID()
    let file: String
    let line: Int
    let column: Int
}

// MARK: - LSP Service

@MainActor
final class LSPService: ObservableObject {
    @Published var isRunning = false
    @Published var diagnostics: [String: [LSPDiagnostic]] = [:] // file → diagnostics
    @Published var lastHoverInfo: LSPHoverInfo?
    @Published var completionItems: [LSPCompletionItem] = []
    @Published var statusMessage: String = "Not started"

    #if os(macOS)
    private var process: Process?
    #endif
    private var stdin: FileHandle?
    private var stdoutHandle: FileHandle?
    private var requestId: Int = 0
    private var pendingRequests: [Int: (Any) -> Void] = [:]
    private var readBuffer = Data()
    private var expectedContentLength: Int?
    private var workspaceRoot: String = ""

    var allDiagnostics: [LSPDiagnostic] {
        diagnostics.values.flatMap { $0 }
    }

    var errorCount: Int {
        allDiagnostics.filter { $0.severity == .error }.count
    }

    var warningCount: Int {
        allDiagnostics.filter { $0.severity == .warning }.count
    }

    // MARK: - Lifecycle

    func start(workspaceRoot: String) {
        #if os(macOS)
        guard !isRunning else { return }
        self.workspaceRoot = workspaceRoot

        // Find sourcekit-lsp
        let lspPath = findSourceKitLSP()
        guard let lspPath = lspPath else {
            statusMessage = "sourcekit-lsp not found"
            return
        }

        statusMessage = "Starting…"

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: lspPath)
        proc.arguments = []
        proc.environment = ProcessInfo.processInfo.environment

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        proc.standardInput = stdinPipe
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        self.stdin = stdinPipe.fileHandleForWriting
        self.stdoutHandle = stdoutPipe.fileHandleForReading

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor [weak self] in
                self?.handleData(data)
            }
        }

        proc.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isRunning = false
                self?.statusMessage = "Stopped"
            }
        }

        do {
            try proc.run()
            self.process = proc
            self.isRunning = true
            statusMessage = "Initializing…"
            sendInitialize()
        } catch {
            statusMessage = "Failed to start: \(error.localizedDescription)"
        }
        #else
        statusMessage = "LSP not available on this platform"
        #endif
    }

    func stop() {
        #if os(macOS)
        process?.terminate()
        process = nil
        #endif
        stdin = nil
        stdoutHandle?.readabilityHandler = nil
        stdoutHandle = nil
        isRunning = false
        statusMessage = "Stopped"
        diagnostics.removeAll()
        pendingRequests.removeAll()
    }

    // MARK: - LSP Protocol

    private func sendInitialize() {
        let id = nextRequestId()
        let params: [String: Any] = [
            "processId": ProcessInfo.processInfo.processIdentifier,
            "rootUri": "file://\(workspaceRoot)",
            "capabilities": [
                "textDocument": [
                    "completion": [
                        "completionItem": ["snippetSupport": false]
                    ],
                    "hover": ["contentFormat": ["plaintext", "markdown"]],
                    "publishDiagnostics": ["relatedInformation": true],
                    "definition": [:] as [String: Any],
                    "references": [:] as [String: Any]
                ],
                "workspace": [
                    "workspaceFolders": true
                ]
            ] as [String: Any],
            "workspaceFolders": [
                ["uri": "file://\(workspaceRoot)", "name": (workspaceRoot as NSString).lastPathComponent]
            ]
        ]

        sendRequest(method: "initialize", id: id, params: params) { [weak self] _ in
            self?.sendNotification(method: "initialized", params: [:] as [String: Any])
            self?.statusMessage = "Ready"
        }
    }

    func openDocument(_ filePath: String) {
        guard isRunning else { return }
        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else { return }

        let params: [String: Any] = [
            "textDocument": [
                "uri": "file://\(filePath)",
                "languageId": "swift",
                "version": 1,
                "text": content
            ]
        ]
        sendNotification(method: "textDocument/didOpen", params: params)
    }

    func closeDocument(_ filePath: String) {
        guard isRunning else { return }
        let params: [String: Any] = [
            "textDocument": ["uri": "file://\(filePath)"]
        ]
        sendNotification(method: "textDocument/didClose", params: params)
    }

    func documentChanged(_ filePath: String, content: String, version: Int) {
        guard isRunning else { return }
        let params: [String: Any] = [
            "textDocument": [
                "uri": "file://\(filePath)",
                "version": version
            ],
            "contentChanges": [
                ["text": content]
            ]
        ]
        sendNotification(method: "textDocument/didChange", params: params)
    }

    func requestCompletion(file: String, line: Int, column: Int) {
        guard isRunning else { return }
        let id = nextRequestId()
        let params: [String: Any] = [
            "textDocument": ["uri": "file://\(file)"],
            "position": ["line": line, "character": column]
        ]

        sendRequest(method: "textDocument/completion", id: id, params: params) { [weak self] response in
            guard let dict = response as? [String: Any] else { return }
            let items = (dict["items"] as? [[String: Any]]) ?? (response as? [[String: Any]]) ?? []
            self?.completionItems = items.map { item in
                let kindRaw = item["kind"] as? Int ?? 0
                return LSPCompletionItem(
                    label: item["label"] as? String ?? "",
                    detail: item["detail"] as? String,
                    kind: LSPCompletionItem.CompletionKind(rawValue: kindRaw) ?? .unknown,
                    insertText: item["insertText"] as? String
                )
            }
        }
    }

    func requestHover(file: String, line: Int, column: Int) {
        guard isRunning else { return }
        let id = nextRequestId()
        let params: [String: Any] = [
            "textDocument": ["uri": "file://\(file)"],
            "position": ["line": line, "character": column]
        ]

        sendRequest(method: "textDocument/hover", id: id, params: params) { [weak self] response in
            guard let dict = response as? [String: Any],
                  let contents = dict["contents"] else {
                self?.lastHoverInfo = nil
                return
            }

            let text: String
            if let str = contents as? String {
                text = str
            } else if let markup = contents as? [String: Any] {
                text = markup["value"] as? String ?? ""
            } else {
                text = ""
            }

            self?.lastHoverInfo = LSPHoverInfo(contents: text, range: nil)
        }
    }

    func requestDefinition(file: String, line: Int, column: Int, completion: @escaping (LSPLocation?) -> Void) {
        guard isRunning else { completion(nil); return }
        let id = nextRequestId()
        let params: [String: Any] = [
            "textDocument": ["uri": "file://\(file)"],
            "position": ["line": line, "character": column]
        ]

        sendRequest(method: "textDocument/definition", id: id, params: params) { response in
            guard let locations = response as? [[String: Any]], let first = locations.first,
                  let uri = first["uri"] as? String,
                  let range = first["range"] as? [String: Any],
                  let start = range["start"] as? [String: Any],
                  let line = start["line"] as? Int,
                  let col = start["character"] as? Int else {
                completion(nil)
                return
            }
            let path = uri.replacingOccurrences(of: "file://", with: "")
            completion(LSPLocation(file: path, line: line, column: col))
        }
    }

    // MARK: - JSON-RPC Transport

    private func nextRequestId() -> Int {
        requestId += 1
        return requestId
    }

    private func sendRequest(method: String, id: Int, params: [String: Any], handler: @escaping (Any) -> Void) {
        pendingRequests[id] = handler
        let message: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params
        ]
        sendMessage(message)
    }

    private func sendNotification(method: String, params: [String: Any]) {
        let message: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
            "params": params
        ]
        sendMessage(message)
    }

    private func sendMessage(_ message: [String: Any]) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: message),
              String(data: jsonData, encoding: .utf8) != nil else { return }

        let header = "Content-Length: \(jsonData.count)\r\n\r\n"
        guard let headerData = header.data(using: .utf8) else { return }

        stdin?.write(headerData)
        stdin?.write(jsonData)
    }

    private func handleData(_ data: Data) {
        readBuffer.append(data)
        processBuffer()
    }

    private func processBuffer() {
        while true {
            if expectedContentLength == nil {
                // Look for header
                guard let headerEnd = readBuffer.range(of: Data("\r\n\r\n".utf8)) else { return }
                let headerData = readBuffer[readBuffer.startIndex..<headerEnd.lowerBound]
                guard let headerStr = String(data: headerData, encoding: .utf8) else { return }

                for line in headerStr.components(separatedBy: "\r\n") {
                    if line.lowercased().hasPrefix("content-length:") {
                        let lenStr = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                        expectedContentLength = Int(lenStr)
                    }
                }

                readBuffer.removeSubrange(readBuffer.startIndex...headerEnd.upperBound - 1)
            }

            guard let length = expectedContentLength else { return }
            guard readBuffer.count >= length else { return }

            let messageData = readBuffer.prefix(length)
            readBuffer.removeFirst(length)
            expectedContentLength = nil

            handleMessage(messageData)
        }
    }

    private func handleMessage(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        // Handle response
        if let id = json["id"] as? Int, let handler = pendingRequests.removeValue(forKey: id) {
            let result = json["result"] ?? json["error"] as Any
            handler(result)
            return
        }

        // Handle notification
        if let method = json["method"] as? String {
            handleNotification(method: method, params: json["params"] as? [String: Any] ?? [:])
        }
    }

    private func handleNotification(method: String, params: [String: Any]) {
        switch method {
        case "textDocument/publishDiagnostics":
            handlePublishDiagnostics(params)
        default:
            break
        }
    }

    private func handlePublishDiagnostics(_ params: [String: Any]) {
        guard let uri = params["uri"] as? String else { return }
        let filePath = uri.replacingOccurrences(of: "file://", with: "")
        let fileName = (filePath as NSString).lastPathComponent

        guard let diagArray = params["diagnostics"] as? [[String: Any]] else { return }

        let parsed: [LSPDiagnostic] = diagArray.compactMap { diag in
            guard let range = diag["range"] as? [String: Any],
                  let start = range["start"] as? [String: Any],
                  let line = start["line"] as? Int,
                  let col = start["character"] as? Int,
                  let message = diag["message"] as? String else { return nil }

            let severityRaw = diag["severity"] as? Int ?? 1
            let severity = LSPDiagnostic.DiagnosticSeverity(rawValue: severityRaw) ?? .error
            let source = diag["source"] as? String ?? "sourcekit"

            return LSPDiagnostic(
                file: fileName, line: line + 1, column: col + 1,
                severity: severity, message: message, source: source
            )
        }

        diagnostics[fileName] = parsed.isEmpty ? nil : parsed
    }

    // MARK: - Path Discovery

    nonisolated private func findSourceKitLSP() -> String? {
        // Check common locations
        let candidates = [
            "/usr/bin/sourcekit-lsp",
            "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/sourcekit-lsp",
            "/Library/Developer/CommandLineTools/usr/bin/sourcekit-lsp"
        ]

        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        #if os(macOS)
        // Try xcrun
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["--find", "sourcekit-lsp"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try? process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        #endif

        return nil
    }
}

// MARK: - LSP Diagnostics View

struct LSPDiagnosticsView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject var lspService: LSPService
    @State private var filterSeverity: LSPDiagnostic.DiagnosticSeverity?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: Spacing.lg) {
                // Status indicator
                HStack(spacing: Spacing.sm) {
                    Circle()
                        .fill(lspService.isRunning ? Color.accentGreen : Color(red: 0.5, green: 0.5, blue: 0.6))
                        .frame(width: 6, height: 6)
                    Text("SourceKit-LSP")
                        .font(Typography.captionSmallSemibold)
                        .foregroundColor(themeManager.palette.textSecondary)
                }

                Text(lspService.statusMessage)
                    .font(Typography.micro)
                    .foregroundColor(themeManager.palette.textMuted)

                Spacer()

                // Summary badges
                if lspService.errorCount > 0 {
                    Label("\(lspService.errorCount)", systemImage: "xmark.circle.fill")
                        .font(Typography.micro)
                        .foregroundColor(.red)
                }
                if lspService.warningCount > 0 {
                    Label("\(lspService.warningCount)", systemImage: "exclamationmark.triangle.fill")
                        .font(Typography.micro)
                        .foregroundColor(.orange)
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.lg)

            if !lspService.allDiagnostics.isEmpty {
                Rectangle()
                    .fill(themeManager.palette.borderSubtle)
                    .frame(height: Border.thin)

                // Filter chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.sm) {
                        filterChip(nil, label: "All (\(lspService.allDiagnostics.count))")
                        filterChip(.error, label: "Errors (\(lspService.errorCount))")
                        filterChip(.warning, label: "Warnings (\(lspService.warningCount))")
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.md)
                }

                // Diagnostics list
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredDiagnostics) { diag in
                            DiagnosticRow(diagnostic: diag)
                        }
                    }
                    .padding(.vertical, Spacing.sm)
                }
            }
        }
        .background(themeManager.palette.bgElevated.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .stroke(themeManager.palette.borderSubtle, lineWidth: Border.hairline)
        )
    }

    private var filteredDiagnostics: [LSPDiagnostic] {
        guard let severity = filterSeverity else { return lspService.allDiagnostics }
        return lspService.allDiagnostics.filter { $0.severity == severity }
    }

    private func filterChip(_ severity: LSPDiagnostic.DiagnosticSeverity?, label: String) -> some View {
        let isSelected = filterSeverity == severity
        return Button(action: { filterSeverity = severity }) {
            Text(label)
                .font(Typography.micro)
                .foregroundColor(isSelected ? (severity?.color ?? themeManager.palette.effectiveAccent) : themeManager.palette.textMuted)
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.sm)
                .background(isSelected ? (severity?.color ?? themeManager.palette.effectiveAccent).opacity(0.12) : themeManager.palette.bgElevated)
                .clipShape(Capsule())
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - Diagnostic Row

struct DiagnosticRow: View {
    @EnvironmentObject var themeManager: ThemeManager
    let diagnostic: LSPDiagnostic

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: diagnostic.severity.icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(diagnostic.severity.color)
                .frame(width: 14)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(diagnostic.message)
                    .font(Typography.captionSmallMedium)
                    .foregroundColor(themeManager.palette.textPrimary)
                    .lineLimit(3)

                HStack(spacing: Spacing.md) {
                    Text(diagnostic.file)
                        .font(Typography.codeMicro)
                        .foregroundColor(themeManager.palette.effectiveAccent)
                    Text(":\(diagnostic.line):\(diagnostic.column)")
                        .font(Typography.codeMicro)
                        .foregroundColor(themeManager.palette.textMuted)
                }
            }

            Spacer()
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.md)
    }
}
