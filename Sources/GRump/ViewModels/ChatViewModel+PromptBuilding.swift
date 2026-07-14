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
            2. For any task with 2 or more distinct steps, FIRST call update_plan with your full step list. Update statuses as you work — mark steps in_progress when you start them and done when you finish. The task is complete only when every step is done.
            3. Produce a brief Mermaid architecture diagram showing what you'll build and how it fits into the existing codebase.
            4. Implement the feature step by step — write real code, create/edit files, run builds, and fix errors as you go.
            5. After implementation, run tests or build commands to verify your work.
            If something is genuinely ambiguous (e.g. you cannot determine the tech stack from the project), state your assumption and proceed. The user chose Build mode because they want code, not questions.

            CRITICAL: When writing or modifying code, you MUST use the write_file or edit_file tools to write code directly to disk.
            Do NOT paste large code blocks into your text response — the user expects files to appear on disk in real time.
            In your text, show only a brief summary of what you wrote (filename, purpose, key changes). The actual code goes through tool calls.
            """
        case .spec:
            instructions = """
            MODE: Spec.
            IMPORTANT — Your FIRST response must be SHORT (under 150 words). Confirm what the user wants to spec out, then present 3-5 structured clarifying questions (numbered, specific, with example answers where helpful). This reassures the user that the system understood their request and is gathering the right context.
            Once the user answers (or says "just go" / "skip"), produce the full detailed spec. Proceed only after gathering enough context.
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

    /// Prepends the developer profile (Profile → You) so it lands between Mind
    /// and Soul in the final prompt order. Pass a profile explicitly for tests;
    /// nil loads `~/.grump/profile.json`.
    func prependDeveloperProfileContent(to basePrompt: String, profile: DeveloperProfile? = nil) -> String {
        guard let block = (profile ?? DeveloperProfile.load()).promptBlock else { return basePrompt }
        return block + basePrompt
    }

    /// Appends the top learned lessons for this request (learning loop).
    /// Injected ids are stashed on the view model so the post-run outcome can
    /// attribute wins/losses back to exactly the lessons the model saw.
    /// Hard cap ~800 tokens; kill switch = BrainConfig.learningEnabled.
    func appendLessons(to prompt: inout String) {
        let config = BrainConfigStore.shared.load()
        guard config.learningEnabled else {
            lastInjectedLessonIds = []
            return
        }
        let query = currentConversation?.messages.last(where: { $0.role == .user })?.content ?? ""
        let picked = LessonStore.shared.relevant(
            for: query.isEmpty ? prompt : query,
            limit: max(1, min(10, config.lessonInjectionCount))
        )
        guard !picked.isEmpty else {
            lastInjectedLessonIds = []
            return
        }

        var block = "\n\n## Learned Lessons\nLessons distilled from previous runs — apply when relevant:\n"
        var injectedIds: [String] = []
        let characterBudget = 800 * 4   // ~4 chars/token
        for lesson in picked {
            let line = "- \(lesson.text)\n"
            guard block.count + line.count <= characterBudget else { break }
            block += line
            injectedIds.append(lesson.id)
        }
        guard !injectedIds.isEmpty else {
            lastInjectedLessonIds = []
            return
        }
        prompt += block
        lastInjectedLessonIds = injectedIds
        LessonStore.shared.recordInjection(ids: injectedIds)
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
            // Budget-aware recall: the most relevant/recent/important memories
            // packed into a fixed token window (Track 1 MemoryAgent).
            if let block = store.budgetedMemoryBlock(for: queryText, tokenBudget: CognitiveMemory.defaultTokenBudget) {
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
