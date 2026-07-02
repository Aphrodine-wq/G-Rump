import Foundation
import os

// MARK: - MCP Connection Manager
//
// Actor-based connection manager with persistent stdio/HTTP/WebSocket connections.
// Connections are lazily created and kept alive across tool calls.

actor MCPConnectionManager {
    static let shared = MCPConnectionManager()

    private var connections: [String: MCPConnection] = [:]
    private let logger = Logger(subsystem: "com.grump.mcp", category: "ConnectionManager")

    // MARK: - Public API

    /// Get or create a persistent connection for a server.
    func connection(for config: MCPServerConfig) async -> MCPConnection {
        if let existing = connections[config.id], await existing.state.isConnected {
            return existing
        }
        // Close stale connection if exists
        if let stale = connections[config.id] {
            await stale.disconnect()
        }
        let conn = MCPConnection(config: config)
        connections[config.id] = conn
        return conn
    }

    /// Close a specific connection.
    func closeConnection(serverId: String) async {
        if let conn = connections.removeValue(forKey: serverId) {
            await conn.disconnect()
        }
    }

    /// Close all connections.
    func closeAll() async {
        for (_, conn) in connections {
            await conn.disconnect()
        }
        connections.removeAll()
    }

    /// Get connection summaries for UI display.
    func summaries() async -> [MCPConnectionSummary] {
        var result: [MCPConnectionSummary] = []
        for (id, conn) in connections {
            let state = await conn.state
            let info = await conn.serverInfo
            let caps = await conn.serverCapabilities
            let tools = await conn.cachedTools?.count ?? 0
            let resources = await conn.cachedResources?.count ?? 0
            let prompts = await conn.cachedPrompts?.count ?? 0
            result.append(MCPConnectionSummary(
                serverId: id, state: state, serverInfo: info,
                capabilities: caps, toolCount: tools,
                resourceCount: resources, promptCount: prompts
            ))
        }
        return result
    }

    /// Fetch tools from an MCP server (returns OpenRouter-format).
    func fetchTools(config: MCPServerConfig) async -> [[String: Any]] {
        let conn = await connection(for: config)
        do {
            try await conn.ensureConnected()
            let tools = try await conn.listTools()
            let prefix = "mcp_\(config.id)_"
            return tools.map { MCPService.convertToOpenRouter(tool: $0, prefix: prefix) }
        } catch {
            logger.error("fetchTools failed for \(config.id): \(error.localizedDescription)")
            return []
        }
    }

    /// Call an MCP tool.
    func callTool(config: MCPServerConfig, toolNameWithPrefix: String, arguments: [String: Any]) async -> String {
        let prefix = "mcp_\(config.id)_"
        let bareName = toolNameWithPrefix.hasPrefix(prefix)
            ? String(toolNameWithPrefix.dropFirst(prefix.count))
            : toolNameWithPrefix

        let conn = await connection(for: config)
        do {
            try await conn.ensureConnected()
            let result = try await conn.callTool(name: bareName, arguments: arguments)
            return result.textContent
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    /// List resources from a connected server.
    func listResources(config: MCPServerConfig) async throws -> [MCPResource] {
        let conn = await connection(for: config)
        try await conn.ensureConnected()
        return try await conn.listResources()
    }

    /// Read a resource by URI.
    func readResource(config: MCPServerConfig, uri: String) async throws -> MCPResourceContent {
        let conn = await connection(for: config)
        try await conn.ensureConnected()
        return try await conn.readResource(uri: uri)
    }

    /// List prompts from a connected server.
    func listPrompts(config: MCPServerConfig) async throws -> [MCPPrompt] {
        let conn = await connection(for: config)
        try await conn.ensureConnected()
        return try await conn.listPrompts()
    }

    /// Get a prompt by name.
    func getPrompt(config: MCPServerConfig, name: String, arguments: [String: String]?) async throws -> MCPGetPromptResult {
        let conn = await connection(for: config)
        try await conn.ensureConnected()
        return try await conn.getPrompt(name: name, arguments: arguments)
    }
}

// MARK: - MCP Connection
//
// A single persistent connection to an MCP server.

actor MCPConnection {
    let config: MCPServerConfig
    private(set) var state: MCPConnectionState = .disconnected
    private(set) var serverInfo: MCPServerInfo?
    private(set) var serverCapabilities: MCPServerCapabilities?
    private(set) var cachedTools: [MCPToolDefinition]?
    private(set) var cachedResources: [MCPResource]?
    private(set) var cachedPrompts: [MCPPrompt]?

    private var transport: MCPTransport?
    private var nextRequestId: Int64 = 1
    private let logger = Logger(subsystem: "com.grump.mcp", category: "Connection")

    init(config: MCPServerConfig) {
        self.config = config
    }

    // MARK: - Lifecycle

    func ensureConnected() async throws {
        if state.isConnected { return }
        try await connect()
    }

    func connect() async throws {
        state = .connecting

        do {
            let t = try await createTransport()
            transport = t
            state = .initializing

            let initResult = try await initialize(transport: t)
            serverInfo = initResult.serverInfo
            serverCapabilities = initResult.capabilities
            state = .ready
            logger.info("Connected to \(self.config.id): \(initResult.serverInfo.name) v\(initResult.serverInfo.version)")
        } catch {
            state = .error(error.localizedDescription)
            throw error
        }
    }

    func disconnect() async {
        if let t = transport {
            await t.close()
        }
        transport = nil
        state = .disconnected
        cachedTools = nil
        cachedResources = nil
        cachedPrompts = nil
    }

    // MARK: - Tools

    func listTools() async throws -> [MCPToolDefinition] {
        if let cached = cachedTools { return cached }
        guard let t = transport else { throw MCPError.notConnected }

        let resp = try await sendRequest(transport: t, method: "tools/list", params: nil)
        guard let result = resp.result?.objectValue,
              let toolsValue = result["tools"]?.arrayValue else {
            throw MCPError.invalidResponse("Missing tools array")
        }

        let tools: [MCPToolDefinition] = toolsValue.compactMap { val in
            guard let data = try? JSONEncoder().encode(val),
                  let tool = try? JSONDecoder().decode(MCPToolDefinition.self, from: data) else { return nil }
            return tool
        }
        cachedTools = tools
        return tools
    }

    func callTool(name: String, arguments: [String: Any]) async throws -> MCPToolResult {
        guard let t = transport else { throw MCPError.notConnected }

        var params: [String: Any] = ["name": name]
        params["arguments"] = arguments

        let resp = try await sendRequest(transport: t, method: "tools/call", params: params)
        if let error = resp.error {
            return MCPToolResult(content: [.text("Error: \(error.message)")], isError: true)
        }
        guard let resultData = resp.result else {
            return MCPToolResult(content: [.text("No content returned")], isError: false)
        }
        let data = try JSONEncoder().encode(resultData)
        return try JSONDecoder().decode(MCPToolResult.self, from: data)
    }

    // MARK: - Resources

    func listResources() async throws -> [MCPResource] {
        if let cached = cachedResources { return cached }
        guard let t = transport else { throw MCPError.notConnected }

        let resp = try await sendRequest(transport: t, method: "resources/list", params: nil)
        guard let result = resp.result?.objectValue,
              let resourcesValue = result["resources"]?.arrayValue else {
            return []
        }

        let resources: [MCPResource] = resourcesValue.compactMap { val in
            guard let data = try? JSONEncoder().encode(val),
                  let res = try? JSONDecoder().decode(MCPResource.self, from: data) else { return nil }
            return res
        }
        cachedResources = resources
        return resources
    }

    func readResource(uri: String) async throws -> MCPResourceContent {
        guard let t = transport else { throw MCPError.notConnected }

        let resp = try await sendRequest(transport: t, method: "resources/read", params: ["uri": uri])
        guard let result = resp.result?.objectValue,
              let contents = result["contents"]?.arrayValue,
              let first = contents.first else {
            throw MCPError.invalidResponse("No resource content")
        }
        let data = try JSONEncoder().encode(first)
        return try JSONDecoder().decode(MCPResourceContent.self, from: data)
    }

    // MARK: - Prompts

    func listPrompts() async throws -> [MCPPrompt] {
        if let cached = cachedPrompts { return cached }
        guard let t = transport else { throw MCPError.notConnected }

        let resp = try await sendRequest(transport: t, method: "prompts/list", params: nil)
        guard let result = resp.result?.objectValue,
              let promptsValue = result["prompts"]?.arrayValue else {
            return []
        }

        let prompts: [MCPPrompt] = promptsValue.compactMap { val in
            guard let data = try? JSONEncoder().encode(val),
                  let prompt = try? JSONDecoder().decode(MCPPrompt.self, from: data) else { return nil }
            return prompt
        }
        cachedPrompts = prompts
        return prompts
    }

    func getPrompt(name: String, arguments: [String: String]?) async throws -> MCPGetPromptResult {
        guard let t = transport else { throw MCPError.notConnected }

        var params: [String: Any] = ["name": name]
        if let args = arguments { params["arguments"] = args }

        let resp = try await sendRequest(transport: t, method: "prompts/get", params: params)
        guard let resultData = resp.result else {
            throw MCPError.invalidResponse("No prompt result")
        }
        let data = try JSONEncoder().encode(resultData)
        return try JSONDecoder().decode(MCPGetPromptResult.self, from: data)
    }

    // MARK: - Internal Transport

    private func createTransport() async throws -> MCPTransport {
        switch config.transport {
        case .stdio(let command, let args):
            #if os(macOS)
            return try StdioTransport(command: command, args: args, serverId: config.id)
            #else
            throw MCPError.unsupportedPlatform("Stdio transport not available on iOS")
            #endif
        case .http(let url):
            return HTTPTransport(url: url)
        case .websocket(let url):
            return try await WebSocketTransport(url: url)
        }
    }

    private func initialize(transport: MCPTransport) async throws -> MCPInitializeResult {
        let resp = try await sendRequest(transport: transport, method: "initialize", params: [
            "protocolVersion": "2024-11-05",
            "capabilities": [
                "roots": ["listChanged": true],
                "sampling": [String: Any]()
            ] as [String: Any],
            "clientInfo": [
                "name": "G-Rump",
                "version": "1.0.0"
            ] as [String: Any]
        ])

        // Send initialized notification
        try await transport.sendNotification(method: "notifications/initialized", params: nil)

        guard let resultData = resp.result else {
            throw MCPError.invalidResponse("No initialize result")
        }
        let data = try JSONEncoder().encode(resultData)
        return try JSONDecoder().decode(MCPInitializeResult.self, from: data)
    }

    private func sendRequest(transport: MCPTransport, method: String, params: [String: Any]?) async throws -> JSONRPCResponse {
        let id = nextRequestId
        nextRequestId += 1
        return try await transport.sendRequest(id: id, method: method, params: params)
    }

    /// Invalidate tool cache (e.g., on tools/list_changed notification).
    func invalidateToolCache() { cachedTools = nil }
    func invalidateResourceCache() { cachedResources = nil }
    func invalidatePromptCache() { cachedPrompts = nil }
}

// MARK: - MCP Error

enum MCPError: LocalizedError {
    case notConnected
    case invalidResponse(String)
    case transportError(String)
    case unsupportedPlatform(String)
    case timeout
    case serverError(code: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .notConnected: return "Not connected to MCP server"
        case .invalidResponse(let msg): return "Invalid MCP response: \(msg)"
        case .transportError(let msg): return "Transport error: \(msg)"
        case .unsupportedPlatform(let msg): return msg
        case .timeout: return "MCP request timed out"
        case .serverError(let code, let msg): return "MCP server error (\(code)): \(msg)"
        }
    }
}

// MARK: - Transport Protocol

protocol MCPTransport: Sendable {
    func sendRequest(id: Int64, method: String, params: [String: Any]?) async throws -> JSONRPCResponse
    func sendNotification(method: String, params: [String: Any]?) async throws
    func close() async
}

// MARK: - Stdio Transport (macOS only)

#if os(macOS)
final class StdioTransport: MCPTransport, @unchecked Sendable {
    private let process: Process
    private let writer: FileHandle
    private let reader: FileHandle
    private let readLock = NSLock()

    init(command: String, args: [String], serverId: String) throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = [command] + args
        proc.environment = MCPCredentialVault.processEnvironment(for: serverId)

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardInput = stdinPipe
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        try proc.run()

        self.process = proc
        self.writer = stdinPipe.fileHandleForWriting
        self.reader = stdoutPipe.fileHandleForReading
    }

    func sendRequest(id: Int64, method: String, params: [String: Any]?) async throws -> JSONRPCResponse {
        var req: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method]
        if let p = params { req["params"] = p }
        let data = try JSONSerialization.data(withJSONObject: req)

        return try await withCheckedThrowingContinuation { continuation in
            readLock.lock()
            defer { readLock.unlock() }

            var line = data
            line.append(0x0a)
            writer.write(line)

            do {
                let response = try readResponse()
                continuation.resume(returning: response)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    func sendNotification(method: String, params: [String: Any]?) async throws {
        var req: [String: Any] = ["jsonrpc": "2.0", "method": method]
        if let p = params { req["params"] = p }
        let data = try JSONSerialization.data(withJSONObject: req)
        var line = data
        line.append(0x0a)
        writer.write(line)
    }

    func close() async {
        writer.closeFile()
        process.terminate()
    }

    private func readResponse() throws -> JSONRPCResponse {
        var buffer = Data()
        let chunkSize = 4096
        while true {
            let chunk = reader.readData(ofLength: chunkSize)
            if chunk.isEmpty {
                throw MCPError.transportError("EOF while reading response")
            }
            buffer.append(chunk)
            if let idx = buffer.firstIndex(of: 0x0a) {
                let line = buffer.prefix(upTo: idx)
                // Try to parse as JSON-RPC response (skip notifications)
                if let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any] {
                    // If it has "id", it's a response. If it has "method" only, it's a notification — skip.
                    if json["id"] != nil || json["result"] != nil || json["error"] != nil {
                        let responseData = try JSONSerialization.data(withJSONObject: json)
                        return try JSONDecoder().decode(JSONRPCResponse.self, from: responseData)
                    }
                }
                // Skip this line and continue reading
                buffer = Data(buffer.dropFirst(idx + 1))
            }
        }
    }
}
#endif

// MARK: - HTTP Transport

final class HTTPTransport: MCPTransport, @unchecked Sendable {
    private let baseURL: String
    private var sessionId: String?

    init(url: String) {
        self.baseURL = url.hasSuffix("/") ? String(url.dropLast()) : url
    }

    func sendRequest(id: Int64, method: String, params: [String: Any]?) async throws -> JSONRPCResponse {
        guard let url = URL(string: baseURL + "/mcp") else {
            throw MCPError.transportError("Invalid URL: \(baseURL)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2024-11-05", forHTTPHeaderField: "MCP-Protocol-Version")
        if let sid = sessionId {
            request.setValue(sid, forHTTPHeaderField: "MCP-Session-ID")
        }

        var body: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method]
        if let p = params { body["params"] = p }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        // Extract session ID from response headers
        if let httpResp = response as? HTTPURLResponse,
           let sid = httpResp.value(forHTTPHeaderField: "MCP-Session-ID") {
            sessionId = sid
        }

        return try JSONDecoder().decode(JSONRPCResponse.self, from: data)
    }

    func sendNotification(method: String, params: [String: Any]?) async throws {
        guard let url = URL(string: baseURL + "/mcp") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2024-11-05", forHTTPHeaderField: "MCP-Protocol-Version")
        if let sid = sessionId {
            request.setValue(sid, forHTTPHeaderField: "MCP-Session-ID")
        }

        var body: [String: Any] = ["jsonrpc": "2.0", "method": method]
        if let p = params { body["params"] = p }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        _ = try await URLSession.shared.data(for: request)
    }

    func close() async {
        sessionId = nil
    }
}

// MARK: - WebSocket Transport

final class WebSocketTransport: MCPTransport, @unchecked Sendable {
    private let task: URLSessionWebSocketTask
    private let pendingRequests = NSLock()
    private var continuations: [Int64: CheckedContinuation<JSONRPCResponse, Error>] = [:]
    private var readerTask: Task<Void, Never>?

    init(url: String) async throws {
        guard let wsURL = URL(string: url) else {
            throw MCPError.transportError("Invalid WebSocket URL: \(url)")
        }
        let session = URLSession(configuration: .default)
        task = session.webSocketTask(with: wsURL)
        task.resume()
        startReading()
    }

    func sendRequest(id: Int64, method: String, params: [String: Any]?) async throws -> JSONRPCResponse {
        var body: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method]
        if let p = params { body["params"] = p }
        let data = try JSONSerialization.data(withJSONObject: body)
        let text = String(data: data, encoding: .utf8)!

        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests.lock()
            continuations[id] = continuation
            pendingRequests.unlock()

            task.send(.string(text)) { error in
                if let error = error {
                    self.pendingRequests.lock()
                    let cont = self.continuations.removeValue(forKey: id)
                    self.pendingRequests.unlock()
                    cont?.resume(throwing: MCPError.transportError(error.localizedDescription))
                }
            }
        }
    }

    func sendNotification(method: String, params: [String: Any]?) async throws {
        var body: [String: Any] = ["jsonrpc": "2.0", "method": method]
        if let p = params { body["params"] = p }
        let data = try JSONSerialization.data(withJSONObject: body)
        let text = String(data: data, encoding: .utf8)!
        try await task.send(.string(text))
    }

    func close() async {
        readerTask?.cancel()
        task.cancel(with: .normalClosure, reason: nil)
        // Fail all pending requests
        pendingRequests.lock()
        let pending = continuations
        continuations.removeAll()
        pendingRequests.unlock()
        for (_, cont) in pending {
            cont.resume(throwing: MCPError.transportError("Connection closed"))
        }
    }

    private func startReading() {
        readerTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { break }
                do {
                    let message = try await self.task.receive()
                    switch message {
                    case .string(let text):
                        guard let data = text.data(using: .utf8) else { continue }
                        self.handleMessage(data)
                    case .data(let data):
                        self.handleMessage(data)
                    @unknown default:
                        break
                    }
                } catch {
                    break
                }
            }
        }
    }

    private func handleMessage(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        // Check if this is a response (has id + result/error)
        if let idValue = json["id"] {
            let id: Int64
            if let i = idValue as? Int64 { id = i } else if let i = idValue as? Int { id = Int64(i) } else { return }

            pendingRequests.lock()
            let cont = continuations.removeValue(forKey: id)
            pendingRequests.unlock()

            if let cont = cont {
                do {
                    let responseData = try JSONSerialization.data(withJSONObject: json)
                    let response = try JSONDecoder().decode(JSONRPCResponse.self, from: responseData)
                    cont.resume(returning: response)
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
        // Notifications (no id) are handled here in the future
    }
}

// MARK: - MCPService (Static Compatibility Layer)
//
// Keeps the old MCPService static API working for existing call sites,
// routing through the new MCPConnectionManager.

final class MCPService {

    /// Fetch tools from an MCP server. Returns OpenRouter-format tool definitions.
    static func fetchTools(
        serverId: String,
        transport: MCPServerConfig.Transport
    ) async -> [[String: Any]] {
        let config = MCPServerConfig(id: serverId, name: serverId, enabled: true, transport: transport)
        return await MCPConnectionManager.shared.fetchTools(config: config)
    }

    /// Call an MCP tool. Returns the tool result as a string.
    static func callTool(
        serverId: String,
        transport: MCPServerConfig.Transport,
        toolNameWithPrefix: String,
        arguments: [String: Any]
    ) async -> String {
        let config = MCPServerConfig(id: serverId, name: serverId, enabled: true, transport: transport)
        return await MCPConnectionManager.shared.callTool(config: config, toolNameWithPrefix: toolNameWithPrefix, arguments: arguments)
    }

    // MARK: - OpenRouter Conversion

    static func convertToOpenRouter(tool: MCPToolDefinition, prefix: String) -> [String: Any] {
        let name = prefix + tool.name
        var params: [String: Any] = ["type": "object", "properties": [String: Any](), "required": [String]()]
        if let schema = tool.inputSchema {
            if let props = schema.properties {
                var propDict = [String: Any]()
                for (k, v) in props {
                    var p: [String: Any] = [:]
                    if let t = v.type { p["type"] = t }
                    if let d = v.description { p["description"] = d }
                    propDict[k] = p
                }
                params["properties"] = propDict
            }
            if let r = schema.required {
                params["required"] = r
            }
        }
        return [
            "type": "function",
            "function": [
                "name": name,
                "description": tool.description ?? "",
                "parameters": params
            ] as [String: Any]
        ]
    }
}
