import Foundation

// MARK: - Model Router
//
// Automatically selects the best model for a given subtask type.
// Optimizes for cost, speed, and capability per task category.

enum TaskType: String, Codable, CaseIterable {
    case reasoning    = "reasoning"
    case planning     = "planning"
    case fileOps      = "file_ops"
    case search       = "search"
    case codeGen      = "code_gen"
    case synthesis    = "synthesis"
    case writing      = "writing"
    case web          = "web"
    case research     = "research"
    case testing      = "testing"
    case debugging    = "debugging"
    case reflection   = "reflection"
    case general      = "general"

    var displayName: String {
        switch self {
        case .reasoning:  return "Reasoning"
        case .planning:   return "Planning"
        case .fileOps:    return "File Operations"
        case .search:     return "Search"
        case .codeGen:    return "Code Generation"
        case .synthesis:  return "Synthesis"
        case .writing:    return "Writing"
        case .web:        return "Web"
        case .research:   return "Research"
        case .testing:    return "Testing"
        case .debugging:  return "Debugging"
        case .reflection: return "Reflection"
        case .general:    return "General"
        }
    }

    var icon: String {
        switch self {
        case .reasoning:  return "brain"
        case .planning:   return "list.bullet.clipboard"
        case .fileOps:    return "doc.text"
        case .search:     return "magnifyingglass"
        case .codeGen:    return "chevron.left.forwardslash.chevron.right"
        case .synthesis:  return "arrow.triangle.merge"
        case .writing:    return "pencil"
        case .web:        return "globe"
        case .research:   return "books.vertical"
        case .testing:    return "checkmark.circle"
        case .debugging:  return "ant"
        case .reflection: return "graduationcap"
        case .general:    return "sparkles"
        }
    }
}

enum ModelRouter {

    // MARK: - Routing Table
    //
    // Maps task types to a ranked list of catalog model ids (primary +
    // fallbacks). Opus and Sonnet trade places on heavy vs. balanced work,
    // Haiku takes the light mechanical tiers. Fable is premium and is NEVER
    // auto-routed — reaching it requires an explicit user selection.
    // Local Ollama models are also never auto-routed: subtask quality is
    // unpredictable across arbitrary local models, so they are used only
    // when explicitly selected as the current model.

    private static let opus = "claude-opus-4-8"
    private static let sonnet = "claude-sonnet-5"
    private static let haiku = "claude-haiku-4-5"

    /// Primary route: returns the best model for a task type.
    static func route(taskType: TaskType, fallback: EnhancedAIModel) -> EnhancedAIModel {
        return fallbackChain(for: taskType, fallback: fallback).first ?? fallback
    }

    /// Context-aware route: picks the best model whose context window fits `estimatedTokens`.
    static func route(taskType: TaskType, fallback: EnhancedAIModel, estimatedTokens: Int) -> EnhancedAIModel {
        let chain = fallbackChain(for: taskType, fallback: fallback)
        // Pick the first model with enough context (leaving room for output)
        for model in chain {
            if model.contextWindow - model.maxOutput > estimatedTokens {
                return model
            }
        }
        // None fit — pick the largest context window
        return chain.max(by: { $0.contextWindow < $1.contextWindow }) ?? fallback
    }

    /// Ordered fallback chain for a task type (best → acceptable alternatives).
    /// Ids resolve through the registry, so a catalog change can never route
    /// to a model that doesn't exist; the caller's fallback always survives.
    static func fallbackChain(for taskType: TaskType, fallback: EnhancedAIModel) -> [EnhancedAIModel] {
        let preferredIDs: [String]
        switch taskType {
        case .reasoning, .planning:
            preferredIDs = [opus, sonnet]
        case .debugging:
            preferredIDs = [opus, sonnet]
        case .fileOps, .search:
            preferredIDs = [haiku, sonnet]
        case .codeGen, .testing:
            preferredIDs = [opus, sonnet]
        case .synthesis, .writing:
            preferredIDs = [sonnet, opus]
        case .web, .research:
            preferredIDs = [sonnet, haiku]
        case .reflection:
            // Post-run distillation is cheap, frequent background work.
            preferredIDs = [haiku, sonnet]
        case .general:
            preferredIDs = []
        }

        let registry = AIModelRegistry.shared
        var chain: [EnhancedAIModel] = taskType == .general ? [fallback] : []
        for id in preferredIDs {
            guard let model = registry.getModel(by: id) else { continue }
            if !chain.contains(where: { $0.id == model.id }) {
                chain.append(model)
            }
        }
        if !chain.contains(where: { $0.id == fallback.id }) {
            chain.append(fallback)
        }
        return chain
    }

    // MARK: - Task Type Detection (weighted scoring)
    //
    // Scores each task type against keyword matches, returns the highest-scoring type.

    private static let keywordTable: [(TaskType, [String], Int)] = [
        // (type, keywords, weight per match)
        (.reasoning, ["reason", "think through", "analyze", "evaluate", "compare", "tradeoff", "decide", "should i", "which is better", "pros and cons", "why does", "explain why"], 3),
        (.planning, ["plan", "outline", "steps", "approach", "strategy", "architect", "design", "roadmap", "phase"], 3),
        (.debugging, ["debug", "fix", "bug", "error", "crash", "exception", "failing", "broken", "issue", "diagnose", "stacktrace", "segfault", "panic"], 4),
        (.codeGen, ["implement", "write code", "create function", "add method", "build", "generate", "code for", "write a", "scaffold", "boilerplate", "refactor"], 3),
        (.testing, ["test", "spec", "unit test", "integration test", "coverage", "assert", "mock", "fixture", "e2e", "snapshot test"], 3),
        (.fileOps, ["read file", "write file", "edit file", "list directory", "search files", "find in", "replace in", "rename file", "move file", "delete file"], 4),
        (.search, ["search", "find", "look for", "locate", "where is", "grep", "which file"], 2),
        (.web, ["web search", "look up", "fetch url", "http", "api call", "documentation", "curl"], 3),
        (.research, ["research", "investigate", "learn about", "deep dive", "survey", "state of the art"], 3),
        (.synthesis, ["summarize", "synthesize", "combine", "merge results", "consolidate"], 3),
        (.writing, ["document", "write docs", "readme", "changelog", "describe", "draft", "blog post", "article"], 3)
    ]

    static func detectTaskType(from description: String) -> TaskType {
        let lower = description.lowercased()
        var scores: [TaskType: Int] = [:]

        for (taskType, keywords, weight) in keywordTable {
            let hits = keywords.filter { lower.contains($0) }.count
            if hits > 0 {
                scores[taskType, default: 0] += hits * weight
            }
        }

        guard let best = scores.max(by: { $0.value < $1.value }), best.value > 0 else {
            return .general
        }
        return best.key
    }
}
