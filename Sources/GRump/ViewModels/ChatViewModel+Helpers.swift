import Foundation

// MARK: - Helpers Extension
//
// Contains API message building, token estimation, tool result truncation,
// message context truncation, effective agent config resolution,
// MCP tools loading, project memory, and tool call summarization.
// Extracted from ChatViewModel.swift for maintainability.

extension ChatViewModel {

    // MARK: - Agent Configuration

    /// Load tools from enabled MCP servers.
    func loadMCPTools() async -> [[String: Any]] {
        let configs = MCPServerConfigStorage.load().filter { $0.enabled }
        var all: [[String: Any]] = []
        for cfg in configs {
            let tools = await MCPService.fetchTools(serverId: cfg.id, transport: cfg.transport)
            all.append(contentsOf: tools)
        }
        return all
    }

    /// Effective model, prompt, tools, and max steps (project config > preset > user default).
    func effectiveAgentConfig() -> (model: AIModel, prompt: String, tools: [[String: Any]], maxSteps: Int) {
        let storedMax = UserDefaults.standard.object(forKey: "MaxAgentSteps") as? Int ?? 200
        let baseMax = min(1000, max(5, storedMax))
        let presetMax = appliedPresetMaxAgentSteps.map { min(1000, max(5, $0)) } ?? baseMax
        guard let cfg = projectConfig else {
            var prompt = prependModeInstructions(to: prependSkillsContent(to: prependMindContent(to: prependSoulContent(to: systemPrompt))))
            if !workingDirectory.isEmpty {
                prompt += "\n\nCurrent working directory: \(workingDirectory)"
            }
            appendSymbolGraphSummary(to: &prompt)
            appendProjectMemory(to: &prompt)
            appendTemporalIntelligence(to: &prompt)
            appendIntentContext(to: &prompt)
            appendConfidenceWarning(to: &prompt)
            let allowlist = appliedPresetToolAllowlist ?? nil
            let userDenylist = ToolsSettingsStorage.loadDenylist()
            let tools = ToolDefinitions.toolsFiltered(allowlist: allowlist, userDenylist: userDenylist)
            return (selectedModel, prompt, tools, presetMax)
        }
        let (model, prompt, toolAllowlist, maxSteps) = cfg.merged(
            currentModel: selectedModel,
            currentPrompt: systemPrompt,
            currentMaxSteps: presetMax
        )
        var finalPrompt = prependModeInstructions(to: prependSkillsContent(to: prependMindContent(to: prependSoulContent(to: prompt))))
        if !workingDirectory.isEmpty {
            finalPrompt += "\n\nCurrent working directory: \(workingDirectory)"
        }
        cfg.appendFacts(to: &finalPrompt)
        cfg.appendContext(to: &finalPrompt, baseDir: workingDirectory)
        appendSymbolGraphSummary(to: &finalPrompt)
        appendProjectMemory(to: &finalPrompt)
        appendTemporalIntelligence(to: &finalPrompt)
        appendIntentContext(to: &finalPrompt)
        appendConfidenceWarning(to: &finalPrompt)
        let allowlist = appliedPresetToolAllowlist ?? toolAllowlist
        let userDenylist = ToolsSettingsStorage.loadDenylist()
        let tools = ToolDefinitions.toolsFiltered(allowlist: allowlist, userDenylist: userDenylist)
        return (model, finalPrompt, tools, maxSteps)
    }

    // MARK: - API Message Building

    func buildAPIMessages(cachedPrompt: String? = nil) -> [Message] {
        var apiMessages: [Message] = []
        var prompt = cachedPrompt ?? effectiveAgentConfig().prompt

        // Apple Intelligence: inject intent + sentiment context
        var intelContext: [String] = []
        if lastUserIntent != .general {
            intelContext.append("[User intent: \(lastUserIntent.rawValue)]")
        }
        if lastUserSentiment == .frustrated {
            intelContext.append("[User appears frustrated — be empathetic, acknowledge the difficulty, and focus on solutions.]")
        }
        if !intelContext.isEmpty {
            prompt += "\n\n" + intelContext.joined(separator: "\n")
        }

        if !prompt.isEmpty {
            apiMessages.append(Message(role: .system, content: prompt))
        }

        if let conversation = currentConversation {
            let msgs = conversation.messages
            let estimatedTokens = msgs.reduce(0) { $0 + estimateTokens($1.content) }
            let contextLimit = selectedModel.contextWindow - selectedModel.maxOutput - 2000

            if estimatedTokens > contextLimit {
                apiMessages.append(contentsOf: truncateMessages(msgs, targetTokens: contextLimit))
            } else {
                apiMessages.append(contentsOf: msgs)
            }
        }
        return apiMessages
    }

    // MARK: - Token Estimation

    /// Estimate token count for a message, accounting for role overhead and tool call metadata.
    func estimateTokens(_ text: String) -> Int {
        // ~4 chars per token for English text, plus overhead per message
        max(1, text.count / 4) + 4
    }

    /// Estimate tokens for an entire message including tool calls.
    func estimateMessageTokens(_ msg: Message) -> Int {
        var tokens = estimateTokens(msg.content)
        if let toolCalls = msg.toolCalls {
            for tc in toolCalls {
                tokens += estimateTokens(tc.name) + estimateTokens(tc.arguments) + 10
            }
        }
        return tokens
    }

    // MARK: - Truncation

    /// Truncate tool result content that is excessively large.
    /// Keeps the first and last portions so the model retains key info.
    func truncateToolResult(_ result: String, maxChars: Int = 8000) -> String {
        guard result.count > maxChars else { return result }
        let headSize = maxChars * 3 / 4
        let tailSize = maxChars / 4
        let head = String(result.prefix(headSize))
        let tail = String(result.suffix(tailSize))
        let omitted = result.count - headSize - tailSize
        return head + "\n\n[... \(omitted) characters omitted ...]\n\n" + tail
    }

    func truncateMessages(_ messages: [Message], targetTokens: Int) -> [Message] {
        // 1. Always keep system messages (they carry instructions)
        let systemMsgs = messages.filter { $0.role == .system }
        let nonSystemMsgs = messages.filter { $0.role != .system }

        let systemTokens = systemMsgs.reduce(0) { $0 + estimateMessageTokens($1) }
        let budget = targetTokens - systemTokens
        guard budget > 0 else {
            // Even system prompt is too large; keep just the last system message
            return Array(systemMsgs.suffix(1))
        }

        // 2. Walk backwards through non-system messages, fitting as many as possible
        var result: [Message] = []
        var tokenCount = 0

        for msg in nonSystemMsgs.reversed() {
            var m = msg
            var msgTokens = estimateMessageTokens(m)

            // Truncate very large tool results to save budget
            if m.role == .tool && m.content.count > 8000 {
                m = Message(role: .tool, content: truncateToolResult(m.content), toolCallId: m.toolCallId)
                msgTokens = estimateMessageTokens(m)
            }

            if tokenCount + msgTokens > budget { break }
            result.insert(m, at: 0)
            tokenCount += msgTokens
        }

        // 3. Prepend system messages
        let droppedCount = nonSystemMsgs.count - result.count
        if droppedCount > 0 {
            let note = Message(role: .system, content: "[Context note: \(droppedCount) earlier messages were omitted to fit context window. The most recent messages are preserved.]")
            result.insert(note, at: 0)
        }
        return systemMsgs + result
    }

    // MARK: - Project Memory

    func saveToProjectMemoryIfEnabled() {
        let enabled = UserDefaults.standard.object(forKey: "ProjectMemoryEnabled") as? Bool ?? true
        guard enabled, !workingDirectory.isEmpty else { return }
        let msgs = currentConversation?.messages ?? []
        guard let lastAssistant = msgs.last(where: { $0.role == .assistant }),
              let lastUser = msgs.last(where: { $0.role == .user }) else { return }

        let toolSummary = buildToolCallSummary(from: msgs)
        let convId = currentConversation?.id.uuidString ?? ""
        for store in activeMemoryStores() {
            store.addEntry(
                conversationId: convId,
                userMessage: lastUser.content,
                assistantContent: lastAssistant.content,
                toolCallSummary: toolSummary
            )
        }
    }

    /// Build a compact summary of tool calls from conversation messages.
    /// e.g. "Edited 3 files (foo.swift, bar.ts, baz.py), ran tests (passed), committed"
    func buildToolCallSummary(from messages: [Message]) -> String {
        var toolCounts: [String: Int] = [:]
        var filePaths: [String] = []
        var commandResults: [String] = []

        for msg in messages {
            guard msg.role == .assistant, let calls = msg.toolCalls else { continue }
            for call in calls {
                toolCounts[call.name, default: 0] += 1
                if let data = call.arguments.data(using: .utf8),
                   let args = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let path = args["path"] as? String {
                        let name = (path as NSString).lastPathComponent
                        if !filePaths.contains(name) { filePaths.append(name) }
                    }
                    if let cmd = args["command"] as? String {
                        let short = cmd.components(separatedBy: " ").first ?? cmd
                        if !commandResults.contains(short) { commandResults.append(short) }
                    }
                }
            }
        }

        guard !toolCounts.isEmpty else { return "" }

        var parts: [String] = []
        let editTools = ["edit_file", "write_file", "create_file", "append_file"]
        let editCount = editTools.compactMap { toolCounts[$0] }.reduce(0, +)
        if editCount > 0 {
            let fileList = filePaths.prefix(5).joined(separator: ", ")
            parts.append("Edited \(editCount) file\(editCount == 1 ? "" : "s")\(fileList.isEmpty ? "" : " (\(fileList))")")
        }
        if let readCount = toolCounts["read_file"].map({ $0 + (toolCounts["batch_read_files"] ?? 0) }), readCount > 0 {
            parts.append("Read \(readCount) file\(readCount == 1 ? "" : "s")")
        }
        let searchTools = ["search_files", "grep_search", "find_and_replace"]
        let searchCount = searchTools.compactMap { toolCounts[$0] }.reduce(0, +)
        if searchCount > 0 { parts.append("Searched \(searchCount)x") }
        if let n = toolCounts["run_command"], n > 0 {
            let cmds = commandResults.prefix(3).joined(separator: ", ")
            parts.append("Ran \(n) command\(n == 1 ? "" : "s")\(cmds.isEmpty ? "" : " (\(cmds))")")
        }
        if let n = toolCounts["run_tests"], n > 0 { parts.append("Ran tests") }
        if let n = toolCounts["git_commit"], n > 0 { parts.append("Committed") }
        if let n = toolCounts["web_search"], n > 0 { parts.append("Web search \(n)x") }
        if let n = toolCounts["delete_file"], n > 0 { parts.append("Deleted \(n) file\(n == 1 ? "" : "s")") }

        return parts.joined(separator: ", ")
    }

    // MARK: - Error Formatting

    func friendlyErrorMessage(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut: return "Request timed out. Please retry or choose a faster model."
            case .notConnectedToInternet: return "No internet connection. Check your network and try again."
            case .networkConnectionLost: return "Network connection lost. Please retry."
            case .cannotConnectToHost: return "Could not connect to server. Check your connection."
            case .dnsLookupFailed: return "DNS lookup failed. Check your internet connection."
            default: return "Network error: \(urlError.localizedDescription)"
            }
        }
        if let serviceError = error as? QwenService.ServiceError {
            if case .apiError(let code, let msg) = serviceError {
                if code == 503 { return "Service temporarily unavailable. Please retry in a moment." }
                if code == 429 { return "Rate limit reached. Please wait a moment and try again." }
                if let m = msg { return m }
            }
        }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
