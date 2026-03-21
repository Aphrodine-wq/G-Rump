// ╔══════════════════════════════════════════════════════════════╗
// ║  SwarmModels.swift                                          ║
// ║  Multi-Agent Swarm — type definitions and data models       ║
// ╚══════════════════════════════════════════════════════════════╝

import Foundation

// MARK: - Swarm Configuration

/// Top-level configuration for a swarm execution.
struct SwarmConfig: Codable, Sendable {
    var maxAgents: Int
    var consensusThreshold: Double
    var timeout: TimeInterval
    var strategy: SwarmStrategy
    var allowedTools: [String]?

    init(
        maxAgents: Int = 8,
        consensusThreshold: Double = 0.7,
        timeout: TimeInterval = 300,
        strategy: SwarmStrategy = .divideAndConquer,
        allowedTools: [String]? = nil
    ) {
        self.maxAgents = maxAgents
        self.consensusThreshold = consensusThreshold
        self.timeout = timeout
        self.strategy = strategy
        self.allowedTools = allowedTools
    }
}

// MARK: - Swarm Strategy

/// The coordination strategy used to orchestrate agents within a swarm.
enum SwarmStrategy: String, CaseIterable, Codable, Sendable, Identifiable {
    /// Decompose the task into independent subtasks, solve each in parallel, merge.
    case divideAndConquer
    /// Agents argue approaches in multiple rounds; best argument wins.
    case debate
    /// All agents solve the same problem independently; results merged via voting.
    case ensemble
    /// Agents pass output sequentially, each refining the previous result.
    case pipeline
    /// A lead coordinator delegates work to specialized workers.
    case hierarchical
    /// Generate solution variations, evaluate fitness, select best, mutate, repeat.
    case evolutionary

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .divideAndConquer: return "Divide & Conquer"
        case .debate: return "Debate"
        case .ensemble: return "Ensemble"
        case .pipeline: return "Pipeline"
        case .hierarchical: return "Hierarchical"
        case .evolutionary: return "Evolutionary"
        }
    }

    var description: String {
        switch self {
        case .divideAndConquer:
            return "Decomposes the task into independent subtasks and assigns each to an agent."
        case .debate:
            return "Agents propose solutions and argue in rounds until consensus emerges."
        case .ensemble:
            return "Every agent solves the full problem; results are merged via voting."
        case .pipeline:
            return "Agents form a pipeline: each refines the output of the previous stage."
        case .hierarchical:
            return "A coordinator plans work and delegates tasks to specialized workers."
        case .evolutionary:
            return "Generates solution variants, evaluates fitness, selects and mutates the best."
        }
    }

    /// Suggested number of agents for this strategy.
    var suggestedAgentCount: Int {
        switch self {
        case .divideAndConquer: return 4
        case .debate: return 3
        case .ensemble: return 5
        case .pipeline: return 4
        case .hierarchical: return 5
        case .evolutionary: return 6
        }
    }

    /// Whether this strategy inherently requires a coordinator role.
    var requiresCoordinator: Bool {
        switch self {
        case .hierarchical: return true
        default: return false
        }
    }
}

// MARK: - Swarm Task

/// A unit of work within a swarm. May have parent/child relationships and dependencies.
struct SwarmTask: Identifiable, Codable, Sendable {
    let id: UUID
    var parentId: UUID?
    var description: String
    var assignedAgent: UUID?
    var status: SwarmTaskStatus
    var priority: Int
    var result: String?
    var dependencies: [UUID]
    var metadata: [String: String]

    init(
        id: UUID = UUID(),
        parentId: UUID? = nil,
        description: String,
        assignedAgent: UUID? = nil,
        status: SwarmTaskStatus = .queued,
        priority: Int = 0,
        result: String? = nil,
        dependencies: [UUID] = [],
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.parentId = parentId
        self.description = description
        self.assignedAgent = assignedAgent
        self.status = status
        self.priority = priority
        self.result = result
        self.dependencies = dependencies
        self.metadata = metadata
    }

    /// Whether every dependency has been resolved (checked externally).
    func dependenciesSatisfied(completedTaskIds: Set<UUID>) -> Bool {
        dependencies.allSatisfy { completedTaskIds.contains($0) }
    }
}

// MARK: - Swarm Task Status

enum SwarmTaskStatus: String, CaseIterable, Codable, Sendable {
    case queued
    case assigned
    case inProgress
    case completed
    case failed
    case cancelled
    case merged

    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled, .merged: return true
        default: return false
        }
    }

    var isActive: Bool {
        switch self {
        case .assigned, .inProgress: return true
        default: return false
        }
    }
}

// MARK: - Micro-Agent Configuration

/// Configuration for a single micro-agent within a swarm.
struct MicroAgentConfig: Identifiable, Codable, Sendable {
    let id: UUID
    var name: String
    var role: AgentRole
    var specialization: String
    var modelOverride: String?
    var systemPromptAddition: String
    var toolFilter: [String]?
    var maxTokens: Int

    init(
        id: UUID = UUID(),
        name: String,
        role: AgentRole,
        specialization: String = "",
        modelOverride: String? = nil,
        systemPromptAddition: String = "",
        toolFilter: [String]? = nil,
        maxTokens: Int = 4096
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.specialization = specialization
        self.modelOverride = modelOverride
        self.systemPromptAddition = systemPromptAddition
        self.toolFilter = toolFilter
        self.maxTokens = maxTokens
    }
}

// MARK: - Agent Role

/// The functional role assigned to a micro-agent.
enum AgentRole: String, CaseIterable, Codable, Sendable, Identifiable {
    case coordinator
    case researcher
    case implementer
    case reviewer
    case tester
    case debugger
    case architect
    case optimizer

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .coordinator: return "Coordinator"
        case .researcher: return "Researcher"
        case .implementer: return "Implementer"
        case .reviewer: return "Reviewer"
        case .tester: return "Tester"
        case .debugger: return "Debugger"
        case .architect: return "Architect"
        case .optimizer: return "Optimizer"
        }
    }

    /// Default tools this role should have access to.
    var defaultTools: [String] {
        switch self {
        case .coordinator:
            return ["read_file", "list_directory", "search_files"]
        case .researcher:
            return ["read_file", "search_files", "grep_search", "list_directory", "find_symbol"]
        case .implementer:
            return ["read_file", "write_file", "edit_file", "create_directory", "run_command"]
        case .reviewer:
            return ["read_file", "search_files", "grep_search", "git_diff", "git_log"]
        case .tester:
            return ["read_file", "write_file", "run_command", "run_tests"]
        case .debugger:
            return ["read_file", "search_files", "grep_search", "run_command", "git_log"]
        case .architect:
            return ["read_file", "list_directory", "search_files", "find_symbol", "grep_search"]
        case .optimizer:
            return ["read_file", "edit_file", "run_command", "search_files", "grep_search"]
        }
    }

    /// Priority ordering: lower values get assigned first in hierarchical mode.
    var assignmentPriority: Int {
        switch self {
        case .coordinator: return 0
        case .architect: return 1
        case .researcher: return 2
        case .implementer: return 3
        case .reviewer: return 4
        case .tester: return 5
        case .debugger: return 6
        case .optimizer: return 7
        }
    }
}

// MARK: - Swarm Result

/// The aggregate result from a completed swarm execution.
struct SwarmResult: Codable, Sendable {
    let swarmId: UUID
    let strategy: SwarmStrategy
    let totalAgents: Int
    let completedTasks: Int
    let failedTasks: Int
    let consensusReached: Bool
    let finalResult: String
    let agentResults: [AgentResult]
    let executionTime: TimeInterval
    let tokenUsage: Int

    /// The average confidence across all agent results.
    var averageConfidence: Double {
        guard !agentResults.isEmpty else { return 0 }
        return agentResults.map(\.confidence).reduce(0, +) / Double(agentResults.count)
    }

    /// Whether the swarm completed without any failed tasks.
    var isCleanSuccess: Bool {
        failedTasks == 0 && completedTasks > 0
    }

    /// A brief human-readable summary.
    var summary: String {
        let status = isCleanSuccess ? "succeeded" : "completed with \(failedTasks) failure(s)"
        return "Swarm \(status): \(completedTasks)/\(totalAgents) tasks done in \(String(format: "%.1f", executionTime))s using \(strategy.displayName)"
    }
}

// MARK: - Agent Result

/// The result produced by a single micro-agent for one task.
struct AgentResult: Identifiable, Codable, Sendable {
    let id: UUID
    let agentId: UUID
    let role: AgentRole
    let taskId: UUID
    let result: String
    let confidence: Double
    let reasoning: String
    let toolCallCount: Int
    let executionTime: TimeInterval

    init(
        id: UUID = UUID(),
        agentId: UUID,
        role: AgentRole,
        taskId: UUID,
        result: String,
        confidence: Double,
        reasoning: String,
        toolCallCount: Int,
        executionTime: TimeInterval = 0
    ) {
        self.id = id
        self.agentId = agentId
        self.role = role
        self.taskId = taskId
        self.result = result
        self.confidence = confidence
        self.reasoning = reasoning
        self.toolCallCount = toolCallCount
        self.executionTime = executionTime
    }
}

// MARK: - Consensus Vote

/// A single agent's vote during a consensus round.
struct ConsensusVote: Codable, Sendable {
    let agentId: UUID
    let proposedResult: String
    let confidence: Double
    let reasoning: String

    /// Weighted score: confidence acts as vote weight.
    var weightedScore: Double { confidence }
}

// MARK: - Swarm Event

/// Events emitted during swarm execution for external observation.
enum SwarmEvent: Sendable {
    case agentSpawned(UUID, AgentRole)
    case taskAssigned(UUID, UUID)
    case agentProgress(UUID, String)
    case agentCompleted(UUID, AgentResult)
    case consensusRound(Int, [ConsensusVote])
    case swarmCompleted(SwarmResult)
    case swarmFailed(String)
}

// MARK: - Stream Event

/// Simplified streaming event type used by the provider stream closure.
enum StreamEvent: Sendable {
    case text(String)
    case toolCallDelta([ToolCallDelta])
    case done(String)
}

// MARK: - Tool Call Delta

/// Incremental tool call information received during streaming.
struct ToolCallDelta: Sendable {
    let index: Int
    let id: String?
    let name: String?
    let arguments: String

    init(index: Int, id: String? = nil, name: String? = nil, arguments: String = "") {
        self.index = index
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

// MARK: - Swarm Session

/// Tracks the runtime state of a single swarm execution.
final class SwarmSession: Sendable {
    let id: UUID
    let config: SwarmConfig
    let startTime: Date
    nonisolated(unsafe) var tasks: [SwarmTask]
    nonisolated(unsafe) var agents: [MicroAgentConfig]
    nonisolated(unsafe) var results: [AgentResult]
    nonisolated(unsafe) var isComplete: Bool

    init(id: UUID = UUID(), config: SwarmConfig) {
        self.id = id
        self.config = config
        self.startTime = Date()
        self.tasks = []
        self.agents = []
        self.results = []
        self.isComplete = false
    }

    var elapsed: TimeInterval {
        Date().timeIntervalSince(startTime)
    }

    var isTimedOut: Bool {
        elapsed > config.timeout
    }
}

// MARK: - Agent State

/// The lifecycle state of a single micro-agent.
enum AgentState: String, Sendable {
    case idle
    case thinking
    case executing
    case waiting
    case done
    case failed

    var isTerminal: Bool {
        self == .done || self == .failed
    }
}
