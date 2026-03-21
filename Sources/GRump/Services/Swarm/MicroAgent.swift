// ╔══════════════════════════════════════════════════════════════╗
// ║  MicroAgent.swift                                           ║
// ║  Multi-Agent Swarm — individual micro-agent execution       ║
// ╚══════════════════════════════════════════════════════════════╝

import Foundation

// MARK: - Message

/// A single message in the agent's conversation history.
struct AgentMessage: Sendable {
    enum Role: String, Sendable {
        case system
        case user
        case assistant
        case tool
    }

    let role: Role
    let content: String
    let timestamp: Date

    init(role: Role, content: String) {
        self.role = role
        self.content = content
        self.timestamp = Date()
    }
}

// MARK: - Accumulated Tool Call

/// Represents a tool call being assembled from streaming deltas.
private struct AccumulatedToolCall: Sendable {
    var id: String
    var name: String
    var arguments: String

    init(id: String = "", name: String = "", arguments: String = "") {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

// MARK: - Micro Agent

/// A single autonomous agent within a swarm. Manages its own conversation
/// history, executes tool calls, and produces a final `AgentResult`.
actor MicroAgent {

    // MARK: - Properties

    let config: MicroAgentConfig
    private(set) var state: AgentState = .idle
    private(set) var messageHistory: [AgentMessage] = []
    private(set) var toolCallCount: Int = 0
    private var successfulToolCalls: Int = 0
    private var failedToolCalls: Int = 0

    private let maxIterations = 20
    private let maxToolCallsPerIteration = 10

    // MARK: - Init

    init(config: MicroAgentConfig) {
        self.config = config
    }

    // MARK: - Execution

    /// Execute the assigned task and return the result.
    func execute(
        task: SwarmTask,
        context: String,
        providerStream: @escaping ProviderStreamFn
    ) async -> AgentResult {
        let startTime = Date()
        state = .thinking

        // Build system prompt
        let systemPrompt = buildSystemPrompt()

        // Build initial user prompt
        let userPrompt = buildUserPrompt(task: task, context: context)

        // Initialize message history
        messageHistory = [
            AgentMessage(role: .system, content: systemPrompt),
            AgentMessage(role: .user, content: userPrompt)
        ]

        var lastAssistantText = ""
        var iterationsUsed = 0

        // Multi-turn execution loop
        for iteration in 0..<maxIterations {
            iterationsUsed = iteration + 1

            // Check for timeout (based on elapsed time)
            let elapsed = Date().timeIntervalSince(startTime)
            if elapsed > 120 {
                state = .failed
                return buildResult(
                    task: task,
                    result: lastAssistantText.isEmpty
                        ? "Agent timed out after \(String(format: "%.0f", elapsed))s"
                        : lastAssistantText,
                    startTime: startTime,
                    confidence: 0.2
                )
            }

            state = .thinking

            // Stream response from the provider
            let (responseText, toolCalls) = await streamProviderResponse(
                providerStream: providerStream,
                systemPrompt: systemPrompt,
                userPrompt: buildConversationPrompt()
            )

            if !responseText.isEmpty {
                lastAssistantText = responseText
                messageHistory.append(AgentMessage(role: .assistant, content: responseText))
            }

            // If no tool calls, we're done
            if toolCalls.isEmpty {
                state = .done
                return buildResult(
                    task: task,
                    result: lastAssistantText,
                    startTime: startTime,
                    confidence: calculateConfidence()
                )
            }

            // Execute tool calls
            state = .executing
            var toolResultsText = ""

            for call in toolCalls.prefix(maxToolCallsPerIteration) {
                let toolResult = await handleToolCall(name: call.name, arguments: call.arguments)
                toolCallCount += 1

                if toolResult.hasPrefix("Error:") || toolResult.hasPrefix("error:") {
                    failedToolCalls += 1
                } else {
                    successfulToolCalls += 1
                }

                toolResultsText += "Tool: \(call.name)\nResult: \(toolResult)\n\n"
            }

            // Add tool results to history
            messageHistory.append(AgentMessage(role: .tool, content: toolResultsText))

            // If we've used too many tool calls, wrap up
            if toolCallCount > 50 {
                state = .done
                return buildResult(
                    task: task,
                    result: lastAssistantText.isEmpty
                        ? "Agent completed with extensive tool usage (\(toolCallCount) calls)"
                        : lastAssistantText,
                    startTime: startTime,
                    confidence: calculateConfidence() * 0.8
                )
            }
        }

        // Hit max iterations
        state = .done
        return buildResult(
            task: task,
            result: lastAssistantText.isEmpty
                ? "Agent reached maximum iterations (\(maxIterations))"
                : lastAssistantText,
            startTime: startTime,
            confidence: calculateConfidence() * 0.7
        )
    }

    // MARK: - System Prompt Builder

    /// Build the system prompt based on the agent's role and specialization.
    func buildSystemPrompt() -> String {
        var prompt = roleSystemPrompt()

        if !config.specialization.isEmpty {
            prompt += "\n\nSpecialization: \(config.specialization)"
        }

        if !config.systemPromptAddition.isEmpty {
            prompt += "\n\n\(config.systemPromptAddition)"
        }

        prompt += "\n\nRules:"
        prompt += "\n- Be concise and focused on your task."
        prompt += "\n- Use tools when needed, but don't over-use them."
        prompt += "\n- If you can answer directly from your knowledge, do so."
        prompt += "\n- When done, state your final answer clearly."
        prompt += "\n- Report your confidence level (0.0-1.0) at the end."

        return prompt
    }

    /// The base system prompt for each role.
    private func roleSystemPrompt() -> String {
        switch config.role {
        case .coordinator:
            return """
            You are the lead architect and coordinator. Your job is to decompose problems \
            into clear subtasks, delegate work to specialized agents, and synthesize their \
            results into a coherent final answer. Think strategically about task ordering \
            and dependencies. Ensure nothing falls through the cracks.
            """
        case .researcher:
            return """
            You are a code researcher. Your job is to explore codebases thoroughly: read \
            files, search for patterns, understand architectures, and map out how components \
            connect. Report your findings with specifics -- file paths, line numbers, function \
            signatures. Be thorough but focused on what's relevant to the task.
            """
        case .implementer:
            return """
            You are a code implementer. Your job is to write clean, working code. Create \
            files, edit existing code, and ensure your implementations follow the project's \
            conventions. Focus on correctness first, then readability. Run builds to verify \
            your changes compile.
            """
        case .reviewer:
            return """
            You are a code reviewer. Your job is to critically examine code for bugs, style \
            violations, performance issues, security vulnerabilities, and design problems. \
            Be specific in your feedback: cite exact lines, explain why something is wrong, \
            and suggest concrete fixes. Check edge cases and error handling.
            """
        case .tester:
            return """
            You are a test engineer. Your job is to write and run tests that verify behavior \
            and catch bugs. Think about edge cases, boundary conditions, error paths, and \
            integration points. Ensure good coverage of the code under test. Run tests and \
            report results clearly.
            """
        case .debugger:
            return """
            You are a debugger and diagnostician. Your job is to track down the root cause \
            of bugs and failures. Read error logs, trace execution paths, check variable \
            states, and isolate the minimal reproduction case. Once you find the cause, \
            propose a targeted fix.
            """
        case .architect:
            return """
            You are a software architect. Your job is to analyze system design, evaluate \
            architectural patterns, plan refactoring strategies, and ensure the codebase \
            has clean separation of concerns. Consider scalability, maintainability, and \
            testability in your recommendations.
            """
        case .optimizer:
            return """
            You are a performance optimizer. Your job is to identify bottlenecks, reduce \
            algorithmic complexity, minimize memory allocations, and improve runtime \
            characteristics. Profile before optimizing. Focus on the hot paths. Measure \
            your improvements with concrete numbers.
            """
        }
    }

    // MARK: - Prompt Building

    /// Build the initial user prompt from the task and context.
    private func buildUserPrompt(task: SwarmTask, context: String) -> String {
        var prompt = "Task: \(task.description)"

        if !context.isEmpty {
            prompt += "\n\nContext:\n\(context)"
        }

        if !task.metadata.isEmpty {
            let metadataStr = task.metadata.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
            prompt += "\n\nMetadata:\n\(metadataStr)"
        }

        return prompt
    }

    /// Build a conversation prompt from the full message history (for multi-turn).
    private func buildConversationPrompt() -> String {
        // Take the last several messages to keep context window manageable
        let recentMessages = messageHistory.suffix(10)
        return recentMessages.map { msg in
            switch msg.role {
            case .system:
                return "" // Already sent as system prompt
            case .user:
                return "User: \(msg.content)"
            case .assistant:
                return "Assistant: \(msg.content)"
            case .tool:
                return "Tool Results:\n\(msg.content)"
            }
        }
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
    }

    // MARK: - Provider Streaming

    /// Stream a response from the provider and collect text + tool calls.
    private func streamProviderResponse(
        providerStream: @escaping ProviderStreamFn,
        systemPrompt: String,
        userPrompt: String
    ) async -> (text: String, toolCalls: [AccumulatedToolCall]) {
        var fullText = ""
        var toolCalls: [Int: AccumulatedToolCall] = [:]

        do {
            let tools = config.toolFilter ?? config.role.defaultTools
            let stream = try await providerStream(systemPrompt, userPrompt, tools)

            for try await event in stream {
                switch event {
                case .text(let chunk):
                    fullText += chunk

                case .toolCallDelta(let deltas):
                    for delta in deltas {
                        var existing = toolCalls[delta.index] ?? AccumulatedToolCall()
                        if let id = delta.id {
                            existing.id = id
                        }
                        if let name = delta.name {
                            existing.name = name
                        }
                        existing.arguments += delta.arguments
                        toolCalls[delta.index] = existing
                    }

                case .done(let finalText):
                    if !finalText.isEmpty {
                        fullText = finalText
                    }
                }
            }
        } catch {
            fullText += "\n[Stream error: \(error.localizedDescription)]"
        }

        let sortedCalls = toolCalls.sorted(by: { $0.key < $1.key }).map(\.value)
        return (fullText, sortedCalls)
    }

    // MARK: - Tool Call Handling

    /// Handle a single tool call by delegating to the G-Rump tool system.
    func handleToolCall(name: String, arguments: String) async -> String {
        // Check tool filter
        if let filter = config.toolFilter, !filter.contains(name) {
            return "Error: Tool '\(name)' is not in this agent's allowed tool list."
        }

        // Parse arguments as JSON
        guard let argData = arguments.data(using: .utf8) else {
            return "Error: Invalid argument encoding."
        }

        let parsedArgs: [String: Any]
        do {
            parsedArgs = (try JSONSerialization.jsonObject(with: argData) as? [String: Any]) ?? [:]
        } catch {
            return "Error: Failed to parse tool arguments: \(error.localizedDescription)"
        }

        // Delegate to the actual tool execution system
        // In a real integration, this would call into the G-Rump ToolExecution subsystem.
        // For now, we handle the most common read-only tools directly:

        switch name {
        case "read_file":
            return await executeReadFile(parsedArgs)
        case "list_directory":
            return await executeListDirectory(parsedArgs)
        case "search_files":
            return await executeSearchFiles(parsedArgs)
        case "grep_search":
            return await executeGrepSearch(parsedArgs)
        case "write_file":
            return await executeWriteFile(parsedArgs)
        case "edit_file":
            return await executeEditFile(parsedArgs)
        case "run_command":
            return await executeRunCommand(parsedArgs)
        default:
            return "Error: Tool '\(name)' is not implemented in the micro-agent runtime."
        }
    }

    // MARK: - Tool Implementations

    private func executeReadFile(_ args: [String: Any]) async -> String {
        guard let path = args["path"] as? String else {
            return "Error: 'path' argument required."
        }
        do {
            let content = try String(contentsOfFile: path, encoding: .utf8)
            let maxChars = 8000
            if content.count > maxChars {
                return String(content.prefix(maxChars)) + "\n... [truncated, \(content.count) chars total]"
            }
            return content
        } catch {
            return "Error: Could not read file: \(error.localizedDescription)"
        }
    }

    private func executeListDirectory(_ args: [String: Any]) async -> String {
        guard let path = args["path"] as? String else {
            return "Error: 'path' argument required."
        }
        do {
            let fm = FileManager.default
            let items = try fm.contentsOfDirectory(atPath: path)
            var output = ""
            for item in items.sorted() {
                var isDir: ObjCBool = false
                let fullPath = (path as NSString).appendingPathComponent(item)
                fm.fileExists(atPath: fullPath, isDirectory: &isDir)
                output += isDir.boolValue ? "\(item)/\n" : "\(item)\n"
            }
            return output.isEmpty ? "(empty directory)" : output
        } catch {
            return "Error: Could not list directory: \(error.localizedDescription)"
        }
    }

    private func executeSearchFiles(_ args: [String: Any]) async -> String {
        guard let path = args["path"] as? String,
              let pattern = args["pattern"] as? String else {
            return "Error: 'path' and 'pattern' arguments required."
        }
        do {
            let fm = FileManager.default
            guard let enumerator = fm.enumerator(atPath: path) else {
                return "Error: Could not enumerate directory."
            }
            var matches: [String] = []
            while let file = enumerator.nextObject() as? String {
                if file.localizedCaseInsensitiveContains(pattern) {
                    matches.append(file)
                    if matches.count >= 50 { break }
                }
            }
            return matches.isEmpty ? "No files matching '\(pattern)'" : matches.joined(separator: "\n")
        }
    }

    private func executeGrepSearch(_ args: [String: Any]) async -> String {
        guard let path = args["path"] as? String,
              let pattern = args["pattern"] as? String else {
            return "Error: 'path' and 'pattern' arguments required."
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/grep")
        process.arguments = ["-r", "-n", "-l", "--include=*.swift", "--include=*.ts", "--include=*.js", "--include=*.rs", pattern, path]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return output.isEmpty ? "No matches found for '\(pattern)'" : output
        } catch {
            return "Error: grep failed: \(error.localizedDescription)"
        }
    }

    private func executeWriteFile(_ args: [String: Any]) async -> String {
        guard let path = args["path"] as? String,
              let content = args["content"] as? String else {
            return "Error: 'path' and 'content' arguments required."
        }
        do {
            let dirPath = (path as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(atPath: dirPath, withIntermediateDirectories: true)
            try content.write(toFile: path, atomically: true, encoding: .utf8)
            return "File written: \(path) (\(content.count) chars)"
        } catch {
            return "Error: Could not write file: \(error.localizedDescription)"
        }
    }

    private func executeEditFile(_ args: [String: Any]) async -> String {
        guard let path = args["path"] as? String,
              let oldText = args["old_text"] as? String,
              let newText = args["new_text"] as? String else {
            return "Error: 'path', 'old_text', and 'new_text' arguments required."
        }
        do {
            var content = try String(contentsOfFile: path, encoding: .utf8)
            guard let range = content.range(of: oldText) else {
                return "Error: old_text not found in file."
            }
            content.replaceSubrange(range, with: newText)
            try content.write(toFile: path, atomically: true, encoding: .utf8)
            return "File edited: \(path)"
        } catch {
            return "Error: Could not edit file: \(error.localizedDescription)"
        }
    }

    private func executeRunCommand(_ args: [String: Any]) async -> String {
        guard let command = args["command"] as? String else {
            return "Error: 'command' argument required."
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        if let cwd = args["cwd"] as? String {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
            process.waitUntilExit()

            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""

            let exitCode = process.terminationStatus
            var output = "Exit code: \(exitCode)\n"
            if !stdout.isEmpty { output += "stdout:\n\(stdout)\n" }
            if !stderr.isEmpty { output += "stderr:\n\(stderr)\n" }

            // Truncate large output
            if output.count > 6000 {
                output = String(output.prefix(6000)) + "\n... [truncated]"
            }

            return output
        } catch {
            return "Error: Command failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Confidence Calculation

    /// Calculate confidence based on tool success rate and iteration count.
    private func calculateConfidence() -> Double {
        let totalCalls = successfulToolCalls + failedToolCalls
        guard totalCalls > 0 else { return 0.6 } // Default confidence if no tools used

        let successRate = Double(successfulToolCalls) / Double(totalCalls)

        // Base confidence on success rate with some adjustments
        var confidence = successRate

        // Bonus for completing with fewer iterations
        let iterationBonus = max(0, 0.1 * (1.0 - Double(messageHistory.count) / Double(maxIterations * 2)))
        confidence += iterationBonus

        // Penalty for too many tool calls (sign of confusion)
        if totalCalls > 30 {
            confidence *= 0.8
        }

        return min(1.0, max(0.0, confidence))
    }

    // MARK: - Result Building

    /// Build the final `AgentResult` from accumulated state.
    private func buildResult(
        task: SwarmTask,
        result: String,
        startTime: Date,
        confidence: Double
    ) -> AgentResult {
        // Extract reasoning from message history
        let reasoning = messageHistory
            .filter { $0.role == .assistant }
            .map(\.content)
            .joined(separator: "\n")
            .prefix(2000)

        return AgentResult(
            agentId: config.id,
            role: config.role,
            taskId: task.id,
            result: result,
            confidence: confidence,
            reasoning: String(reasoning),
            toolCallCount: toolCallCount,
            executionTime: Date().timeIntervalSince(startTime)
        )
    }

    // MARK: - State Access

    var currentState: AgentState { state }
    var name: String { config.name }
    var role: AgentRole { config.role }
    var historyCount: Int { messageHistory.count }
}
