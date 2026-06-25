import Foundation

// MARK: - Prompt Building Extension
//
// Functions that construct the system prompt by prepending mode instructions,
// SOUL identity, skill content, and appending project context (memory,
// symbol graph, temporal intelligence, intent continuity, confidence).

extension ChatViewModel {

    /// Prepends mode-specific instructions to the base prompt.
    func prependModeInstructions(to basePrompt: String) -> String {
        let instructions: String
        switch agentMode {
        case .standard:
            instructions = """
            MODE: Chat.
            IMPORTANT — Your FIRST response should start with a brief acknowledgment (1-2 sentences) confirming you understand the request. This reassures the user that the system is working. Then proceed with your full answer, tool calls, or implementation.
            """
        case .plan:
            instructions = """
            MODE: Plan.
            IMPORTANT — Your FIRST response must be SHORT (under 150 words). Acknowledge what the user wants to build, then ask 2-3 focused clarifying questions (e.g. target platform, key constraints, scale, must-have vs nice-to-have features). This reassures the user the system is working and gathers context before you invest time planning.
            Once the user answers (or if they say "just go" / "skip"), THEN produce the full detailed plan with architecture, steps, tradeoffs, and timeline. Do not implement until the user approves the plan.
            """
        case .fullStack:
            instructions = """
            MODE: Full Stack Build.
            IMPORTANT — Do NOT ask clarifying questions. Start building IMMEDIATELY.
            1. Inspect the project structure and existing code using tools (tree_view, read_file, grep_search).
            2. Produce a brief Mermaid architecture diagram showing what you'll build and how it fits into the existing codebase.
            3. Implement the feature step by step — write real code, create/edit files, run builds, and fix errors as you go.
            4. After implementation, run tests or build commands to verify your work.
            If something is genuinely ambiguous (e.g. you cannot determine the tech stack from the project), state your assumption and proceed. The user chose Build mode because they want code, not questions.
            
            CRITICAL: When writing or modifying code, you MUST use the write_file or edit_file tools to write code directly to disk.
            Do NOT paste large code blocks into your text response — the user expects files to appear on disk in real time.
            In your text, show only a brief summary of what you wrote (filename, purpose, key changes). The actual code goes through tool calls.
            """
        case .argue:
            instructions = """
            MODE: Argue.
            IMPORTANT — Your FIRST response must be SHORT (under 150 words). Restate the user's position in your own words to confirm you understand it, then immediately present your strongest counter-argument or alternative. This gives instant feedback that the system is engaged.
            Continue the debate across follow-up messages. Push back, challenge assumptions, and explore tradeoffs until you converge on the best solution. Do not implement until the debate concludes.
            """
        case .spec:
            instructions = """
            MODE: Spec.
            IMPORTANT — Your FIRST response must be SHORT (under 150 words). Confirm what the user wants to spec out, then present 3-5 structured clarifying questions (numbered, specific, with example answers where helpful). This reassures the user that the system understood their request and is gathering the right context.
            Once the user answers (or says "just go" / "skip"), produce the full detailed spec. Proceed only after gathering enough context.
            """
        case .parallel:
            instructions = """
            MODE: Parallel.
            IMPORTANT — Your FIRST response must be SHORT (under 150 words). Acknowledge the task, then briefly outline how you plan to decompose it into parallel subtasks (e.g. "I'll split this into 3 parallel agents: one for X, one for Y, one for Z"). This gives the user immediate confidence that the system is working and shows the orchestration strategy.
            Then proceed to decompose, assign each subtask to the best-fit model, run them in parallel, and synthesize the results into a single coherent response.
            """
        case .speculative:
            instructions = """
            MODE: Explore (Speculative Branching).
            The system will automatically generate 2-3 competing solution approaches in parallel, \
            evaluate each one, and present the winner. You are one branch of this exploration. \
            Commit fully to your assigned approach — do not hedge or mention alternatives.
            """
        }
        let antiXML = "\nIMPORTANT: Do NOT output raw XML, function calls, or tool invocation markup (e.g. <execute>, <function>, <tool_call>) in your text response. Use the native tool_calls API mechanism instead. Any XML tool markup in your text will be stripped and may cause unexpected behavior."
        return instructions + antiXML + "\n\n" + basePrompt
    }

    /// Prepends SOUL.md identity content as the foundation layer.
    func prependSoulContent(to basePrompt: String) -> String {
        guard let soul = SoulStorage.loadSoul(workingDirectory: workingDirectory) else { return basePrompt }
        let soulBlock = "\n\n--- Soul: \(soul.name) ---\n" + soul.body + "\n\n--- End of soul ---\n\n"
        return soulBlock + basePrompt
    }

    /// Prepends MIND.md identity content as the outermost foundation layer (before Soul).
    func prependMindContent(to basePrompt: String) -> String {
        guard let mind = MindStorage.loadMind(workingDirectory: workingDirectory) else { return basePrompt }
        let mindBlock = "\n\n--- Mind: \(mind.name) ---\n" + mind.body + "\n\n--- End of mind ---\n\n"
        return mindBlock + basePrompt
    }

    /// Prepends enabled skill instructions to the base prompt.
    /// Combines explicitly enabled skills + context-aware auto-suggested skills (score > 0.7).
    func prependSkillsContent(to basePrompt: String) -> String {
        let skills = SkillsStorage.loadSkills(workingDirectory: workingDirectory)
        let enabledIds = SkillsSettingsStorage.loadAllowlist()
        var activeSkills = skills.filter { enabledIds.contains($0.id) }

        // Context-aware auto-injection: find relevant skills not already enabled
        if let lastMessage = messages.last(where: { $0.role == .user })?.content {
            let fileExtensions = detectFileExtensions()
            let candidates = skills.filter { !enabledIds.contains($0.id) }
            let suggested = candidates
                .map { ($0, $0.relevanceScore(for: lastMessage, fileExtensions: fileExtensions)) }
                .filter { $0.1 > 0.7 }
                .sorted { $0.1 > $1.1 }
                .prefix(3)
                .map(\.0)
            activeSkills.append(contentsOf: suggested)
        }

        guard !activeSkills.isEmpty else { return basePrompt }
        let skillBlocks = activeSkills.map { skill in
            let header = "\n\n--- Skill: \(skill.name) ---\n"
            return header + skill.body
        }
        return skillBlocks.joined() + "\n\n--- End of skills ---\n\n" + basePrompt
    }

    /// Detect file extensions in the working directory for context-aware skill matching.
    func detectFileExtensions() -> Set<String> {
        guard !workingDirectory.isEmpty else { return [] }
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: workingDirectory) else { return [] }
        var extensions: Set<String> = []
        for item in items.prefix(50) { // Sample up to 50 files
            let ext = (item as NSString).pathExtension
            if !ext.isEmpty { extensions.insert(".\(ext)") }
        }
        return extensions
    }

    // MARK: - Prompt Context Appenders

    /// Returns the active memory stores based on user settings.
    func activeMemoryStores() -> [ProjectMemoryStore] {
        guard !workingDirectory.isEmpty else { return [] }
        var stores: [ProjectMemoryStore] = []
        let semanticEnabled = UserDefaults.standard.object(forKey: "SemanticMemoryEnabled") as? Bool ?? true
        if semanticEnabled {
            stores.append(SemanticMemoryStore(baseDirectory: workingDirectory))
        }
        // Plain-text store always active for backward compatibility
        stores.append(MemoryStore(baseDirectory: workingDirectory))
        return stores
    }

    func appendSymbolGraphSummary(to prompt: inout String) {
        let sgs = SymbolGraphService.shared
        guard sgs.symbolCount > 0 else { return }
        let summary = sgs.apiSummary(maxTokens: 3000)
        guard !summary.contains("No symbol graph loaded") else { return }
        prompt += "\n\n# Project Symbol Graph\n\n" + summary
    }

    func appendProjectMemory(to prompt: inout String) {
        let enabled = UserDefaults.standard.object(forKey: "ProjectMemoryEnabled") as? Bool ?? true
        guard enabled, !workingDirectory.isEmpty else { return }

        let queryText = currentConversation?.messages.last(where: { $0.role == .user })?.content ?? ""
        for store in activeMemoryStores() {
            if let block = store.memoryBlock(for: queryText) {
                prompt += block
                return
            }
        }
    }

    /// Appends temporal code intelligence summary (hotspots, coupling, decay) to the system prompt.
    func appendTemporalIntelligence(to prompt: inout String) {
        guard !workingDirectory.isEmpty else { return }
        if let snapshot = TemporalCodeIntelligenceService.shared.snapshot {
            let summary = snapshot.promptSummary(maxTokens: 800)
            if !summary.isEmpty {
                prompt += "\n\n" + summary
            }
        }
    }

    /// Appends active intent context (cross-session goal continuity) to the system prompt.
    func appendIntentContext(to prompt: inout String) {
        guard let intent = intentContinuity.activeIntent else { return }
        prompt += "\n\n" + intent.promptFragment
    }

    /// Appends confidence calibration warning when confidence is low.
    func appendConfidenceWarning(to prompt: inout String) {
        if let fragment = confidenceCalibration.lowConfidencePromptFragment() {
            prompt += "\n\n" + fragment
        }
    }
}
