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
        case .general:    return "sparkles"
        }
    }
}

enum ModelRouter {

    // MARK: - Routing Table
    //
    // Maps task types to a ranked list of models (primary + fallbacks).
    // Free models preferred where capable.

    /// Primary route: returns the best model for a task type.
    static func route(taskType: TaskType, fallback: AIModel) -> AIModel {
        return fallbackChain(for: taskType, fallback: fallback).first ?? fallback
    }

    /// Context-aware route: picks the best model whose context window fits `estimatedTokens`.
    static func route(taskType: TaskType, fallback: AIModel, estimatedTokens: Int) -> AIModel {
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
    /// Single provider now: routes across Qwen tiers — Coder Plus for code,
    /// Max for reasoning, Plus/Turbo for lighter work.
    static func fallbackChain(for taskType: TaskType, fallback: AIModel) -> [AIModel] {
        switch taskType {
        case .reasoning, .planning:
            return [.qwenMax, .qwenPlus, fallback]

        case .debugging:
            return [.qwenCoderPlus, .qwenMax, fallback]

        case .fileOps, .search:
            return [.qwenTurbo, .qwenPlus, fallback]

        case .codeGen, .testing:
            return [.qwenCoderPlus, .qwenMax, fallback]

        case .synthesis, .writing:
            return [.qwenPlus, .qwenMax, fallback]

        case .web, .research:
            return [.qwenPlus, .qwenTurbo, fallback]

        case .general:
            return [fallback, .qwenCoderPlus, .qwenPlus]
        }
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

    // MARK: - Helpers

    private static func containsAny(_ text: String, _ keywords: [String]) -> Bool {
        keywords.contains { text.contains($0) }
    }
}
