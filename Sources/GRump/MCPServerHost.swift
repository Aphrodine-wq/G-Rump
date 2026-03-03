import Foundation
import os

#if os(macOS)
import Network
import AppKit

// MARK: - MCP Server Host
//
// Exposes G-Rump's tool system as an MCP server.
// External clients (OpenClaw, Claude Desktop, etc.) can connect via stdio or TCP
// and call tools/list → tools/call against G-Rump's 95+ tools.

actor MCPServerHost {
    static let shared = MCPServerHost()

    private(set) var isRunning = false
    private var listener: NWListener?
    private var activeConnections: [String: MCPServerConnection] = [:]
    private let logger = Logger(subsystem: "com.grump.mcp", category: "ServerHost")

    /// The port the server is listening on (nil if not running).
    private(set) var port: UInt16?

    /// Authentication token required for tools/call requests. Generated once at process start.
    let authToken: String = UUID().uuidString

    /// Workspace root for path traversal protection. File tools are restricted to this directory.
    var workspaceRoot: String = FileManager.default.currentDirectoryPath

    // MARK: - Lifecycle

    /// Start the MCP server on the given port. Binds to 127.0.0.1 only.
    func start(port: UInt16 = 18790) throws {
        guard !isRunning else { return }

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: .ipv4(.loopback),
            port: NWEndpoint.Port(rawValue: port)!
        )
        let nwListener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        self.listener = nwListener
        self.port = port

        nwListener.stateUpdateHandler = { [weak self] state in
            Task { [weak self] in
                switch state {
                case .ready:
                    await self?.setRunning(true)
                case .failed, .cancelled:
                    await self?.setRunning(false)
                default:
                    break
                }
            }
        }

        nwListener.newConnectionHandler = { [weak self] connection in
            Task { [weak self] in
                await self?.handleNewConnection(connection)
            }
        }

        nwListener.start(queue: .global(qos: .userInitiated))
        logger.info("MCP Server started on 127.0.0.1:\(port) — auth token: \(self.authToken)")
    }

    /// Stop the server and close all connections.
    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        port = nil
        for (_, conn) in activeConnections {
            conn.close()
        }
        activeConnections.removeAll()
        logger.info("MCP Server stopped")
    }

    private func setRunning(_ value: Bool) {
        isRunning = value
    }

    // MARK: - Connection Handling

    private func handleNewConnection(_ nwConnection: NWConnection) {
        let connId = UUID().uuidString
        let conn = MCPServerConnection(id: connId, connection: nwConnection, host: self)
        activeConnections[connId] = conn
        conn.start()
        logger.info("New MCP client connected: \(connId)")
    }

    func removeConnection(id: String) {
        activeConnections.removeValue(forKey: id)
    }

    // MARK: - Tool Registry

    /// Get all available tools as MCP tool definitions.
    nonisolated func toolDefinitions() -> [MCPToolDefinition] {
        return MCPServerHost.builtInToolDefs
    }

    /// Execute a tool call and return the result.
    nonisolated func executeTool(name: String, arguments: [String: Any], workspaceRoot: String? = nil) async -> MCPToolResult {
        let result = await MCPToolDispatcher.dispatch(name: name, arguments: arguments, workspaceRoot: workspaceRoot)
        return MCPToolResult(
            content: [.text(result)],
            isError: result.hasPrefix("Error:")
        )
    }

    // MARK: - Built-in Tool Definitions

    private static let builtInToolDefs: [MCPToolDefinition] = {
        var tools: [MCPToolDefinition] = []

        // File operations
        tools.append(MCPToolDefinition(name: "read_file", description: "Read the contents of a file", inputSchema: JSONSchema(
            type: "object", properties: [
                "path": JSONSchemaProperty(type: "string", description: "File path to read"),
                "encoding": JSONSchemaProperty(type: "string", description: "File encoding (default: utf-8)")
            ], required: ["path"])))

        tools.append(MCPToolDefinition(name: "write_file", description: "Write content to a file", inputSchema: JSONSchema(
            type: "object", properties: [
                "path": JSONSchemaProperty(type: "string", description: "File path to write"),
                "content": JSONSchemaProperty(type: "string", description: "Content to write")
            ], required: ["path", "content"])))

        tools.append(MCPToolDefinition(name: "edit_file", description: "Edit a file with search and replace", inputSchema: JSONSchema(
            type: "object", properties: [
                "path": JSONSchemaProperty(type: "string", description: "File path"),
                "old_text": JSONSchemaProperty(type: "string", description: "Text to find"),
                "new_text": JSONSchemaProperty(type: "string", description: "Replacement text")
            ], required: ["path", "old_text", "new_text"])))

        tools.append(MCPToolDefinition(name: "list_directory", description: "List files in a directory", inputSchema: JSONSchema(
            type: "object", properties: [
                "path": JSONSchemaProperty(type: "string", description: "Directory path")
            ], required: ["path"])))

        tools.append(MCPToolDefinition(name: "search_files", description: "Search for files by name pattern", inputSchema: JSONSchema(
            type: "object", properties: [
                "directory": JSONSchemaProperty(type: "string", description: "Directory to search"),
                "pattern": JSONSchemaProperty(type: "string", description: "Filename pattern to match")
            ], required: ["directory", "pattern"])))

        tools.append(MCPToolDefinition(name: "grep_search", description: "Search file contents with regex", inputSchema: JSONSchema(
            type: "object", properties: [
                "pattern": JSONSchemaProperty(type: "string", description: "Search pattern (regex)"),
                "directory": JSONSchemaProperty(type: "string", description: "Directory to search"),
                "file_pattern": JSONSchemaProperty(type: "string", description: "File glob pattern")
            ], required: ["pattern"])))

        // Web
        tools.append(MCPToolDefinition(name: "web_search", description: "Search the web", inputSchema: JSONSchema(
            type: "object", properties: [
                "query": JSONSchemaProperty(type: "string", description: "Search query")
            ], required: ["query"])))

        tools.append(MCPToolDefinition(name: "read_url", description: "Fetch and read a URL", inputSchema: JSONSchema(
            type: "object", properties: [
                "url": JSONSchemaProperty(type: "string", description: "URL to fetch")
            ], required: ["url"])))

        // System
        tools.append(MCPToolDefinition(name: "clipboard_read", description: "Read clipboard contents", inputSchema: JSONSchema(type: "object")))
        tools.append(MCPToolDefinition(name: "clipboard_write", description: "Write to clipboard", inputSchema: JSONSchema(
            type: "object", properties: [
                "text": JSONSchemaProperty(type: "string", description: "Text to copy")
            ], required: ["text"])))

        return tools
    }()
}

// MARK: - MCP Server Connection
//
// Handles a single client connection to the MCP server.

final class MCPServerConnection: @unchecked Sendable {
    let id: String
    private let connection: NWConnection
    private weak var host: MCPServerHost?
    private var buffer = Data()

    init(id: String, connection: NWConnection, host: MCPServerHost) {
        self.id = id
        self.connection = connection
        self.host = host
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            if case .failed = state { self?.close() }
            if case .cancelled = state { self?.close() }
        }
        connection.start(queue: .global(qos: .userInitiated))
        receiveData()
    }

    func close() {
        connection.cancel()
        Task { await host?.removeConnection(id: id) }
    }

    private func receiveData() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            if let data = data {
                self.buffer.append(data)
                self.processBuffer()
            }
            if isComplete || error != nil {
                self.close()
            } else {
                self.receiveData()
            }
        }
    }

    private func processBuffer() {
        while let newlineIdx = buffer.firstIndex(of: 0x0a) {
            let line = buffer.prefix(upTo: newlineIdx)
            buffer = Data(buffer.dropFirst(newlineIdx + 1))

            guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let method = json["method"] as? String else { continue }

            let requestId = json["id"]
            let params = json["params"] as? [String: Any]

            Task {
                let response = await self.handleRequest(method: method, params: params)
                self.sendResponse(id: requestId, result: response)
            }
        }
    }

    private func handleRequest(method: String, params: [String: Any]?) async -> Any {
        switch method {
        case "initialize":
            return [
                "protocolVersion": "2024-11-05",
                "capabilities": [
                    "tools": ["listChanged": false]
                ] as [String: Any],
                "serverInfo": [
                    "name": "G-Rump",
                    "version": "2.0.0"
                ]
            ] as [String: Any]

        case "tools/list":
            guard let host = host else { return ["tools": []] }
            // Require auth token for tool listing (prevents tool enumeration by unauthenticated clients)
            let listToken = params?["auth_token"] as? String
            let expectedListToken = await host.authToken
            guard listToken == expectedListToken else {
                return [
                    "error": [
                        "code": -32600,
                        "message": "Authentication required. Provide 'auth_token' in params."
                    ] as [String: Any]
                ]
            }
            let defs = host.toolDefinitions()
            let tools: [[String: Any]] = defs.map { def in
                var tool: [String: Any] = ["name": def.name]
                if let desc = def.description { tool["description"] = desc }
                if let schema = def.inputSchema,
                   let data = try? JSONEncoder().encode(schema),
                   let obj = try? JSONSerialization.jsonObject(with: data) {
                    tool["inputSchema"] = obj
                }
                return tool
            }
            return ["tools": tools]

        case "tools/call":
            // Require auth token for tool execution
            guard let host = host else {
                return ["content": [["type": "text", "text": "Error: server not available"]], "isError": true] as [String: Any]
            }
            let providedToken = params?["auth_token"] as? String
            let expectedToken = await host.authToken
            guard providedToken == expectedToken else {
                return [
                    "error": [
                        "code": -32600,
                        "message": "Authentication required. Provide 'auth_token' in params."
                    ] as [String: Any]
                ]
            }
            guard let name = params?["name"] as? String else {
                return ["content": [["type": "text", "text": "Error: missing tool name"]], "isError": true] as [String: Any]
            }
            let arguments = params?["arguments"] as? [String: Any] ?? [:]
            let workspaceRoot = await host.workspaceRoot
            let result = await host.executeTool(name: name, arguments: arguments, workspaceRoot: workspaceRoot)
            let content: [[String: Any]] = result.content.map { block in
                switch block {
                case .text(let text): return ["type": "text", "text": text]
                case .image(let data, let mime): return ["type": "image", "data": data, "mimeType": mime]
                case .resource(let res): return ["type": "resource", "uri": res.uri, "text": res.text ?? ""]
                }
            }
            return ["content": content, "isError": result.isError ?? false] as [String: Any]

        case "notifications/initialized":
            return [String: Any]()

        default:
            return ["error": "Unknown method: \(method)"]
        }
    }

    private func sendResponse(id: Any?, result: Any) {
        var response: [String: Any] = ["jsonrpc": "2.0"]
        if let id = id { response["id"] = id }
        response["result"] = result
        guard let data = try? JSONSerialization.data(withJSONObject: response) else { return }
        var line = data
        line.append(0x0a)
        connection.send(content: line, completion: .contentProcessed({ _ in }))
    }
}

// MARK: - Tool Dispatcher (standalone, non-UI)
//
// Routes MCP tool calls to implementations that don't require ChatViewModel.
// For tools that need ChatViewModel (like run_command with approval), returns an error
// indicating the tool requires interactive use.

enum MCPToolDispatcher {
    static func dispatch(name: String, arguments: [String: Any], workspaceRoot: String? = nil) async -> String {
        switch name {
        case "read_file":
            guard let path = arguments["path"] as? String else { return "Error: missing path" }
            let resolved = resolvePath(path)
            if let err = checkPathTraversal(resolved, workspaceRoot: workspaceRoot) { return err }
            guard let data = FileManager.default.contents(atPath: resolved),
                  let content = String(data: data, encoding: .utf8) else {
                return "Error: could not read file at \(resolved)"
            }
            return content

        case "list_directory":
            guard let path = arguments["path"] as? String else { return "Error: missing path" }
            let resolved = resolvePath(path)
            if let err = checkPathTraversal(resolved, workspaceRoot: workspaceRoot) { return err }
            guard let items = try? FileManager.default.contentsOfDirectory(atPath: resolved) else {
                return "Error: could not list directory at \(resolved)"
            }
            return items.sorted().joined(separator: "\n")

        case "clipboard_read":
            return NSPasteboard.general.string(forType: .string) ?? ""

        case "write_file":
            guard let path = arguments["path"] as? String,
                  let content = arguments["content"] as? String else { return "Error: missing path or content" }
            let resolved = resolvePath(path)
            if let err = checkPathTraversal(resolved, workspaceRoot: workspaceRoot) { return err }
            do {
                try content.write(toFile: resolved, atomically: true, encoding: .utf8)
                return "OK: wrote \(content.count) characters to \(resolved)"
            } catch {
                return "Error: \(error.localizedDescription)"
            }

        case "edit_file":
            guard let path = arguments["path"] as? String,
                  let oldText = arguments["old_text"] as? String,
                  let newText = arguments["new_text"] as? String else {
                return "Error: missing path, old_text, or new_text"
            }
            let resolved = resolvePath(path)
            if let err = checkPathTraversal(resolved, workspaceRoot: workspaceRoot) { return err }
            guard let data = FileManager.default.contents(atPath: resolved),
                  let content = String(data: data, encoding: .utf8) else {
                return "Error: could not read file at \(resolved)"
            }
            guard content.contains(oldText) else {
                return "Error: old_text not found in \(resolved)"
            }
            let updated = content.replacingOccurrences(of: oldText, with: newText)
            do {
                try updated.write(toFile: resolved, atomically: true, encoding: .utf8)
                return "OK: replaced text in \(resolved)"
            } catch {
                return "Error: \(error.localizedDescription)"
            }

        case "search_files":
            guard let directory = arguments["directory"] as? String,
                  let pattern = arguments["pattern"] as? String else {
                return "Error: missing directory or pattern"
            }
            let resolved = resolvePath(directory)
            if let err = checkPathTraversal(resolved, workspaceRoot: workspaceRoot) { return err }
            let fm = FileManager.default
            guard let enumerator = fm.enumerator(atPath: resolved) else {
                return "Error: could not enumerate \(resolved)"
            }
            var matches: [String] = []
            while let item = enumerator.nextObject() as? String {
                if item.localizedCaseInsensitiveContains(pattern) {
                    matches.append(item)
                }
                if matches.count >= 200 { break }
            }
            return matches.isEmpty ? "No files matching '\(pattern)'" : matches.joined(separator: "\n")

        case "grep_search":
            guard let pattern = arguments["pattern"] as? String else { return "Error: missing pattern" }
            let directory = resolvePath((arguments["directory"] as? String) ?? ".")
            if let err = checkPathTraversal(directory, workspaceRoot: workspaceRoot) { return err }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/grep")
            var args = ["-rn", pattern, directory]
            if let filePattern = arguments["file_pattern"] as? String {
                args.insert(contentsOf: ["--include", filePattern], at: 0)
            }
            process.arguments = args
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                if output.isEmpty { return "No matches found for '\(pattern)'" }
                if output.count > 50_000 { return String(output.prefix(50_000)) + "\n... (truncated)" }
                return output
            } catch {
                return "Error: \(error.localizedDescription)"
            }

        case "web_search":
            return "Error: web_search is not available in MCP server mode. Use G-Rump's chat interface for web searches."

        case "read_url":
            guard let urlString = arguments["url"] as? String,
                  let url = URL(string: urlString) else { return "Error: missing or invalid url" }
            do {
                let config = URLSessionConfiguration.default
                config.timeoutIntervalForRequest = 10
                let session = URLSession(configuration: config)
                let (data, response) = try await session.data(from: url)
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                let body = String(data: data, encoding: .utf8) ?? "(binary data, \(data.count) bytes)"
                if body.count > 50_000 { return "HTTP \(statusCode)\n" + String(body.prefix(50_000)) + "\n... (truncated)" }
                return "HTTP \(statusCode)\n" + body
            } catch {
                return "Error: \(error.localizedDescription)"
            }

        case "clipboard_write":
            guard let text = arguments["text"] as? String else { return "Error: missing text" }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            return "OK: copied \(text.count) characters to clipboard"

        default:
            return "Error: tool '\(name)' is not available in MCP server mode"
        }
    }

    /// Check that a resolved path is within the workspace root. Returns an error string if traversal detected.
    private static func checkPathTraversal(_ resolvedPath: String, workspaceRoot: String?) -> String? {
        guard let root = workspaceRoot, !root.isEmpty else {
            return "Error: no workspace root configured — file access denied"
        }
        let standardizedPath = URL(fileURLWithPath: resolvedPath).standardizedFileURL.path
        let standardizedRoot = URL(fileURLWithPath: root).standardizedFileURL.path
        guard standardizedPath.hasPrefix(standardizedRoot) else {
            return "Error: path is outside workspace root"
        }
        return nil
    }

    private static func resolvePath(_ path: String) -> String {
        if path.hasPrefix("~") {
            return (path as NSString).expandingTildeInPath
        }
        return path
    }
}

#endif
