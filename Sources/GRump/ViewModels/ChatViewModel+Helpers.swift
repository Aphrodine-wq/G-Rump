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
    func effectiveAgentConfig() -> (model: EnhancedAIModel, prompt: String, tools: [[String: Any]], maxSteps: Int) {
        let storedMax = UserDefaults.standard.object(forKey: "MaxAgentSteps") as? Int ?? 400
        let baseMax = min(2000, max(5, storedMax))
        let presetMax = appliedPresetMaxAgentSteps.map { min(2000, max(5, $0)) } ?? baseMax
        guard let cfg = projectConfig else {
            var prompt = prependModeInstructions(to: prependSkillsContent(to: prependMindContent(to: prependDeveloperProfileContent(to: prependSoulContent(to: systemPrompt)))))
            if !workingDirectory.isEmpty {
                prompt += "\n\nCurrent working directory: \(workingDirectory)"
                // A project can carry .grump/context.md without any config.json —
                // the default instance's nil contextFile falls back to it.
                ProjectConfig().appendContext(to: &prompt, baseDir: workingDirectory)
            }
            appendSymbolGraphSummary(to: &prompt)
            appendProjectMemory(to: &prompt)
            appendTemporalIntelligence(to: &prompt)
            appendIntentContext(to: &prompt)
            appendConfidenceWarning(to: &prompt)
            appendLessons(to: &prompt)
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
        var finalPrompt = prependModeInstructions(to: prependSkillsContent(to: prependMindContent(to: prependDeveloperProfileContent(to: prependSoulContent(to: prompt)))))
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
        appendLessons(to: &finalPrompt)
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
            var msgs = conversation.messages

            // Consume rolling compaction: pinned framing + summary note
            // replace everything before the cutoff (persisted history is
            // untouched — this shapes only the API payload).
            if compactionCutoffIndex > 0, compactionCutoffIndex < msgs.count, let summary = compactionSummary {
                var reduced: [Message] = []
                if let framing = msgs.prefix(compactionCutoffIndex).first(where: { $0.role == .user }) {
                    reduced.append(framing)
                }
                reduced.append(Message(role: .user, content: "[Agent notice] Summary of earlier progress (older turns compacted):\n\(summary)"))
                reduced.append(contentsOf: msgs[compactionCutoffIndex...])
                msgs = reduced
            }

            let estimatedTokens = msgs.reduce(0) { $0 + estimateTokens($1.content) }
            let contextLimit = selectedModel.contextWindow - selectedModel.maxOutput - 2000

            if estimatedTokens > contextLimit {
                apiMessages.append(contentsOf: truncateMessages(msgs, targetTokens: contextLimit))
            } else {
                apiMessages.append(contentsOf: msgs)
            }
        }

        // Tracked plan rides as a TRAILING user-role note: trailing keeps the
        // cached prefix stable, user-role avoids the system-block hoist.
        if let plan = currentPlan, !plan.steps.isEmpty {
            apiMessages.append(Message(role: .user, content: "[Agent notice] Current tracked plan:\n\(plan.markdownSnapshot())"))
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
        var budget = targetTokens - systemTokens
        guard budget > 0 else {
            // Even system prompt is too large; keep just the last system message
            return Array(systemMsgs.suffix(1))
        }

        // 2. Pin the first user message — the task framing must survive
        // truncation or long runs forget what they were asked to do.
        let pinned = nonSystemMsgs.first(where: { $0.role == .user })
        if let pinned {
            budget -= estimateMessageTokens(pinned)
        }

        // 3. Walk backwards through non-system messages, fitting as many as possible
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

        // 4. Orphan guard: a tool_result whose parent assistant tool_use turn
        // was dropped is rejected by the Anthropic API — drop leading tool
        // messages until the window starts on a non-tool message.
        while let first = result.first, first.role == .tool {
            result.removeFirst()
        }

        // 5. Re-attach the pinned framing (dedupe by id) + a drop note.
        // The note is user-role: a system-role note would be hoisted into the
        // Anthropic system block and invalidate the prompt cache every turn.
        var head: [Message] = []
        if let pinned, !result.contains(where: { $0.id == pinned.id }) {
            head.append(pinned)
        }
        let droppedCount = nonSystemMsgs.count - result.count - head.count
        if droppedCount > 0 {
            head.append(Message(role: .user, content: "[Agent notice] \(droppedCount) earlier messages were omitted to fit the context window. The original request and the most recent messages are preserved."))
        }
        return systemMsgs + head + result
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
        let info = chatErrorInfo(error)
        return "\(info.title). \(info.guidance)"
    }

    /// Maps a failure to the inline error card's contract: what happened and
    /// what to do about it in plain English up front, the raw failure behind
    /// the Details disclosure, and an optional recovery action.
    func chatErrorInfo(_ error: Error) -> ChatErrorInfo {
        let raw = String(describing: error)
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return ChatErrorInfo(title: "Request timed out",
                                     guidance: "Retry, or switch to a faster model.",
                                     technicalDetail: raw)
            case .notConnectedToInternet:
                return ChatErrorInfo(title: "No internet connection",
                                     guidance: "Check your network and retry.",
                                     technicalDetail: raw)
            case .networkConnectionLost:
                return ChatErrorInfo(title: "Network connection lost",
                                     guidance: "Retry when the connection is back.",
                                     technicalDetail: raw)
            case .cannotConnectToHost:
                return ChatErrorInfo(title: "Couldn't connect to the server",
                                     guidance: "Check your connection and retry.",
                                     technicalDetail: raw)
            case .dnsLookupFailed:
                return ChatErrorInfo(title: "DNS lookup failed",
                                     guidance: "Check your internet connection and retry.",
                                     technicalDetail: raw)
            default:
                return ChatErrorInfo(title: "Network error",
                                     guidance: urlError.localizedDescription,
                                     technicalDetail: raw)
            }
        }
        if let serviceError = error as? OpenAICompatibleService.ServiceError,
           case .apiError(let code, let msg) = serviceError {
            let detail = "HTTP \(code)" + (msg.map { ": \($0)" } ?? "")
            switch code {
            case 503:
                return ChatErrorInfo(title: "Service temporarily unavailable",
                                     guidance: "Give it a moment, then retry.",
                                     technicalDetail: detail)
            case 429:
                return ChatErrorInfo(title: "Rate limit reached",
                                     guidance: "Wait a moment, then retry.",
                                     technicalDetail: detail)
            case 404, 410:
                // Ollama :cloud models keep appearing in /api/tags after the
                // hosted backend retires or paywalls them — the failure only
                // shows up here, at request time.
                return ChatErrorInfo(title: "\u{201C}\(selectedModel)\u{201D} is no longer available",
                                     guidance: "The provider retired or paywalled it. Pick a different model and retry.",
                                     technicalDetail: detail,
                                     action: .pickModel)
            case 401, 403:
                return ChatErrorInfo(title: "The provider rejected the API key",
                                     guidance: "Check the key in Settings → AI Providers, then retry.",
                                     technicalDetail: detail)
            default:
                return ChatErrorInfo(title: "The provider returned an error",
                                     guidance: msg ?? "Retry in a moment.",
                                     technicalDetail: detail)
            }
        }
        let described = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        return ChatErrorInfo(title: "Something went wrong",
                             guidance: described,
                             technicalDetail: raw)
    }
}

// MARK: - Structured chat errors

/// Contract for the inline chat error card: `title` and `guidance` are plain
/// English shown up front; `technicalDetail` lives behind the Details
/// disclosure; `action` adds a contextual recovery button.
struct ChatErrorInfo: Equatable {
    enum Action: Equatable {
        /// The selected model is gone (retired/paywalled) — offer an inline
        /// model menu that retries on selection.
        case pickModel
    }

    var title: String
    var guidance: String
    var technicalDetail: String
    var action: Action?

    init(title: String, guidance: String, technicalDetail: String, action: Action? = nil) {
        self.title = title
        self.guidance = guidance
        self.technicalDetail = technicalDetail
        self.action = action
    }
}
