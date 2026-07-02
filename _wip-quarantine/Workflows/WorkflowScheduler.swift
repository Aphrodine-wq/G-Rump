import Foundation

// MARK: - Workflow Scheduler

/// Actor responsible for scheduling, prioritizing, and orchestrating parallel workflow step execution.
/// Supports dependency graph analysis, critical path identification, cycle detection,
/// and concurrency-limited parallel wave execution.
actor WorkflowScheduler {

    // MARK: - Configuration

    private let maxConcurrentSteps: Int = 4
    private var scheduledWorkflows: [ScheduledWorkflow] = []
    private var executionHistory: [StepExecutionRecord] = []
    private let historyLimit = 500

    // MARK: - Scheduled Workflow

    struct ScheduledWorkflow: Sendable {
        let workflowId: UUID
        let priority: Int
        let scheduledAt: Date
        var estimatedCompletion: TimeInterval
    }

    struct StepExecutionRecord: Sendable {
        let stepId: UUID
        let workflowId: UUID
        let stepName: String
        let startedAt: Date
        let completedAt: Date
        let duration: TimeInterval
        let success: Bool
    }

    // MARK: - Scheduling

    /// Schedule a workflow for execution with priority ordering.
    func schedule(_ workflow: Workflow) -> ScheduledWorkflow {
        let priority = calculatePriority(workflow)
        let estimate = estimateCompletion(workflow)

        let scheduled = ScheduledWorkflow(
            workflowId: workflow.id,
            priority: priority,
            scheduledAt: Date(),
            estimatedCompletion: estimate
        )

        // Insert in priority order (higher priority first)
        if let insertIdx = scheduledWorkflows.firstIndex(where: { $0.priority < priority }) {
            scheduledWorkflows.insert(scheduled, at: insertIdx)
        } else {
            scheduledWorkflows.append(scheduled)
        }

        return scheduled
    }

    /// Remove a workflow from the schedule.
    func unschedule(_ workflowId: UUID) {
        scheduledWorkflows.removeAll { $0.workflowId == workflowId }
    }

    /// Get the next workflow to execute.
    func nextWorkflow() -> ScheduledWorkflow? {
        scheduledWorkflows.first
    }

    /// Dequeue the next workflow for execution.
    func dequeueNext() -> ScheduledWorkflow? {
        guard !scheduledWorkflows.isEmpty else { return nil }
        return scheduledWorkflows.removeFirst()
    }

    // MARK: - Dependency Graph

    /// Build a dependency graph from workflow steps.
    func buildDependencyGraph(_ steps: [WorkflowStep]) -> DirectedGraph<UUID> {
        var graph = DirectedGraph<UUID>()

        for step in steps {
            graph.addNode(step.id)
            for depId in step.dependencies {
                graph.addEdge(from: depId, to: step.id)
            }
        }

        return graph
    }

    /// Find steps whose dependencies are all satisfied.
    func findReadySteps(in workflow: Workflow) -> [WorkflowStep] {
        let completedIds = Set(
            workflow.steps.filter { step in
                step.state == .succeeded || step.state == .skipped
            }.map(\.id)
        )

        return workflow.steps.filter { step in
            guard step.state == .pending || step.state == .ready else { return false }
            return step.dependencySet.isSubset(of: completedIds)
        }
    }

    /// Find steps that are blocked (have unsatisfied dependencies).
    func findBlockedSteps(in workflow: Workflow) -> [WorkflowStep] {
        let completedIds = Set(
            workflow.steps.filter { step in
                step.state == .succeeded || step.state == .skipped
            }.map(\.id)
        )

        return workflow.steps.filter { step in
            guard step.state == .pending || step.state == .blocked else { return false }
            return !step.dependencySet.isSubset(of: completedIds)
        }
    }

    // MARK: - Wave Execution

    /// Execute a wave of independent steps in parallel, respecting concurrency limits.
    func executeWave(_ steps: [WorkflowStep], in workflow: Workflow,
                     executor: @Sendable (WorkflowStep) async -> (Bool, String?)) async -> [(stepId: UUID, success: Bool, result: String?)] {
        let batch = Array(steps.prefix(maxConcurrentSteps))

        return await withTaskGroup(of: (UUID, Bool, String?).self) { group in
            for step in batch {
                group.addTask {
                    let startTime = Date()
                    let (success, result) = await executor(step)
                    let endTime = Date()

                    // Record execution history
                    await self.recordExecution(StepExecutionRecord(
                        stepId: step.id,
                        workflowId: workflow.id,
                        stepName: step.name,
                        startedAt: startTime,
                        completedAt: endTime,
                        duration: endTime.timeIntervalSince(startTime),
                        success: success
                    ))

                    return (step.id, success, result)
                }
            }

            var results: [(stepId: UUID, success: Bool, result: String?)] = []
            for await result in group {
                results.append((stepId: result.0, success: result.1, result: result.2))
            }
            return results
        }
    }

    // MARK: - Cycle Detection

    /// Detect cycles in the dependency graph. Returns arrays of step IDs forming cycles.
    func detectCycles(in steps: [WorkflowStep]) -> [[UUID]] {
        let graph = buildDependencyGraph(steps)
        let sccs = graph.stronglyConnectedComponents()

        // Filter to only SCCs with more than one node (actual cycles)
        return sccs.filter { $0.count > 1 }
    }

    /// Validate that a workflow has no dependency cycles.
    func validateDependencies(_ steps: [WorkflowStep]) -> DependencyValidation {
        let cycles = detectCycles(in: steps)

        if !cycles.isEmpty {
            return DependencyValidation(
                isValid: false,
                cycles: cycles,
                unreachableSteps: [],
                warnings: ["Dependency cycles detected: \(cycles.count) cycle(s)"]
            )
        }

        // Check for unreachable steps (depend on non-existent steps)
        let allStepIds = Set(steps.map(\.id))
        var unreachable: [UUID] = []
        var warnings: [String] = []

        for step in steps {
            for depId in step.dependencies {
                if !allStepIds.contains(depId) {
                    unreachable.append(step.id)
                    warnings.append("Step '\(step.name)' depends on non-existent step \(depId)")
                }
            }
        }

        // Check for orphaned steps (no dependencies and no dependents)
        let allDeps = Set(steps.flatMap(\.dependencies))
        let stepsWithDependents = Set(steps.filter { allDeps.contains($0.id) }.map(\.id))
        let stepsWithDeps = Set(steps.filter { !$0.dependencies.isEmpty }.map(\.id))
        let connected = stepsWithDependents.union(stepsWithDeps)

        for step in steps {
            if !connected.contains(step.id) && steps.count > 1 {
                warnings.append("Step '\(step.name)' is isolated (no dependencies and no dependents)")
            }
        }

        return DependencyValidation(
            isValid: unreachable.isEmpty,
            cycles: [],
            unreachableSteps: unreachable,
            warnings: warnings
        )
    }

    // MARK: - Critical Path Analysis

    /// Find the critical path (longest path through the dependency graph).
    func findCriticalPath(in steps: [WorkflowStep]) -> [WorkflowStep] {
        let stepMap = Dictionary(uniqueKeysWithValues: steps.map { ($0.id, $0) })
        let graph = buildDependencyGraph(steps)

        // Topological sort
        guard let sorted = graph.topologicalSort() else { return [] }

        // Calculate longest path to each node
        var longestPath: [UUID: TimeInterval] = [:]
        var predecessor: [UUID: UUID] = [:]

        for id in sorted {
            longestPath[id] = stepMap[id]?.estimatedDuration ?? 0
        }

        for id in sorted {
            let currentLength = longestPath[id] ?? 0
            let stepDuration = stepMap[id]?.estimatedDuration ?? 0

            for neighbor in graph.neighbors(of: id) {
                let neighborDuration = stepMap[neighbor]?.estimatedDuration ?? 0
                let newLength = currentLength + neighborDuration

                if newLength > (longestPath[neighbor] ?? 0) {
                    longestPath[neighbor] = newLength
                    predecessor[neighbor] = id
                }
            }
        }

        // Find the end of the critical path (node with longest path)
        guard let criticalEnd = longestPath.max(by: { $0.value < $1.value })?.key else {
            return []
        }

        // Trace back the path
        var path: [UUID] = [criticalEnd]
        var current = criticalEnd
        while let pred = predecessor[current] {
            path.insert(pred, at: 0)
            current = pred
        }

        return path.compactMap { stepMap[$0] }
    }

    /// Calculate the minimum possible total duration (critical path length).
    func criticalPathDuration(in steps: [WorkflowStep]) -> TimeInterval {
        let path = findCriticalPath(in: steps)
        return path.reduce(0) { $0 + $1.estimatedDuration }
    }

    // MARK: - Completion Estimation

    /// Estimate total completion time for a workflow, considering parallelism.
    func estimateCompletion(_ workflow: Workflow) -> TimeInterval {
        let steps = workflow.steps
        guard !steps.isEmpty else { return 0 }

        // Use critical path as baseline estimate
        let criticalDuration = criticalPathDuration(in: steps)

        // Adjust based on historical execution data
        let avgHistoricalOverrun = calculateHistoricalOverrun()
        let adjusted = criticalDuration * (1.0 + avgHistoricalOverrun)

        // Account for remaining steps only
        let completedSteps = Set(steps.filter { $0.state == .succeeded || $0.state == .skipped }.map(\.id))
        let remainingSteps = steps.filter { !completedSteps.contains($0.id) }

        if remainingSteps.isEmpty { return 0 }

        let remainingRatio = Double(remainingSteps.count) / Double(steps.count)
        return adjusted * remainingRatio
    }

    /// Estimate completion for a specific step based on historical data.
    func estimateStepDuration(_ step: WorkflowStep) -> TimeInterval {
        // Check historical averages for similar tool calls
        let relevantHistory = executionHistory.filter { record in
            step.toolCalls.contains { $0.toolName == record.stepName }
        }

        if !relevantHistory.isEmpty {
            let avgDuration = relevantHistory.reduce(0.0) { $0 + $1.duration } / Double(relevantHistory.count)
            return avgDuration
        }

        return step.estimatedDuration
    }

    // MARK: - Priority Calculation

    /// Calculate execution priority for a workflow (higher = more urgent).
    private func calculatePriority(_ workflow: Workflow) -> Int {
        var priority = 50 // base priority

        // Workflows with fewer steps are quicker = slightly higher priority
        if workflow.steps.count <= 3 {
            priority += 10
        }

        // Bug fixes are higher priority than features
        if workflow.name.lowercased().contains("fix") || workflow.name.lowercased().contains("bug") {
            priority += 20
        }

        // Deployments are highest priority
        if workflow.name.lowercased().contains("deploy") {
            priority += 30
        }

        // Tests are medium priority
        if workflow.name.lowercased().contains("test") {
            priority += 15
        }

        // Paused workflows that resume get a boost
        if workflow.state == .paused {
            priority += 10
        }

        return priority
    }

    // MARK: - Execution History

    private func recordExecution(_ record: StepExecutionRecord) {
        executionHistory.append(record)
        if executionHistory.count > historyLimit {
            executionHistory = Array(executionHistory.suffix(historyLimit))
        }
    }

    /// Average overrun ratio: how much longer steps take vs estimates.
    private func calculateHistoricalOverrun() -> Double {
        guard !executionHistory.isEmpty else { return 0.2 } // default 20% buffer

        // This is a simplified version; in production you'd match by step name/tool
        let overruns = executionHistory.filter { $0.duration > 0 }
        guard !overruns.isEmpty else { return 0.2 }

        // Cap at 100% overrun to prevent extreme estimates
        return min(1.0, 0.15)
    }

    /// Get success rate for steps by tool name.
    func successRate(for toolName: String) -> Double {
        let relevant = executionHistory.filter { $0.stepName == toolName }
        guard !relevant.isEmpty else { return 1.0 }
        let successful = relevant.filter(\.success).count
        return Double(successful) / Double(relevant.count)
    }

    /// Get average duration for a tool.
    func averageDuration(for toolName: String) -> TimeInterval? {
        let relevant = executionHistory.filter { $0.stepName == toolName && $0.success }
        guard !relevant.isEmpty else { return nil }
        return relevant.reduce(0.0) { $0 + $1.duration } / Double(relevant.count)
    }

    // MARK: - Execution Plan

    /// Generate an execution plan showing the order and parallelism of steps.
    func generateExecutionPlan(_ steps: [WorkflowStep]) -> ExecutionPlan {
        let graph = buildDependencyGraph(steps)
        let stepMap = Dictionary(uniqueKeysWithValues: steps.map { ($0.id, $0) })

        guard let sorted = graph.topologicalSort() else {
            return ExecutionPlan(waves: [], totalEstimate: 0, criticalPath: [], isValid: false)
        }

        // Group into waves: steps that can execute in parallel
        var waves: [[WorkflowStep]] = []
        var scheduled: Set<UUID> = []

        while scheduled.count < sorted.count {
            var wave: [WorkflowStep] = []

            for id in sorted {
                guard !scheduled.contains(id) else { continue }
                guard let step = stepMap[id] else { continue }

                // All dependencies must be in previously scheduled waves
                let depsScheduled = step.dependencySet.isSubset(of: scheduled)
                if depsScheduled && wave.count < maxConcurrentSteps {
                    wave.append(step)
                }
            }

            if wave.isEmpty { break } // safety valve

            for step in wave {
                scheduled.insert(step.id)
            }
            waves.append(wave)
        }

        let criticalPath = findCriticalPath(in: steps)
        let totalEstimate = waves.reduce(0.0) { total, wave in
            let waveDuration = wave.map(\.estimatedDuration).max() ?? 0
            return total + waveDuration
        }

        return ExecutionPlan(
            waves: waves,
            totalEstimate: totalEstimate,
            criticalPath: criticalPath,
            isValid: true
        )
    }

    // MARK: - Rebalancing

    /// Suggest step reordering to minimize total execution time.
    func suggestOptimization(_ steps: [WorkflowStep]) -> [WorkflowOptimization] {
        var suggestions: [WorkflowOptimization] = []

        let plan = generateExecutionPlan(steps)

        // Check for single-step waves that could be parallelized
        for (index, wave) in plan.waves.enumerated() {
            if wave.count == 1 && index > 0 {
                let step = wave[0]
                // Check if this step's dependencies are in waves earlier than the previous one
                let depWaves = step.dependencies.compactMap { depId in
                    plan.waves.firstIndex(where: { $0.contains(where: { $0.id == depId }) })
                }
                if let maxDepWave = depWaves.max(), maxDepWave < index - 1 {
                    suggestions.append(WorkflowOptimization(
                        type: .parallelizable,
                        stepIds: [step.id],
                        description: "Step '\(step.name)' can be moved to an earlier wave for better parallelism",
                        estimatedTimeSaving: step.estimatedDuration * 0.5
                    ))
                }
            }
        }

        // Check for steps with many dependencies that could be split
        for step in steps {
            if step.toolCalls.count > 3 {
                suggestions.append(WorkflowOptimization(
                    type: .splitStep,
                    stepIds: [step.id],
                    description: "Step '\(step.name)' has \(step.toolCalls.count) tool calls and could be split for better granularity",
                    estimatedTimeSaving: step.estimatedDuration * 0.3
                ))
            }
        }

        // Check for unnecessary sequential dependencies
        let criticalPath = findCriticalPath(in: steps)
        if criticalPath.count > steps.count / 2 {
            suggestions.append(WorkflowOptimization(
                type: .reduceDependencies,
                stepIds: criticalPath.map(\.id),
                description: "Critical path is \(criticalPath.count)/\(steps.count) steps long. Consider removing unnecessary sequential dependencies.",
                estimatedTimeSaving: criticalPathDuration(in: steps) * 0.2
            ))
        }

        return suggestions
    }
}

// MARK: - Supporting Types

struct DependencyValidation: Sendable {
    let isValid: Bool
    let cycles: [[UUID]]
    let unreachableSteps: [UUID]
    let warnings: [String]

    var description: String {
        if isValid && warnings.isEmpty {
            return "Dependency graph is valid"
        }
        var parts: [String] = []
        if !cycles.isEmpty { parts.append("\(cycles.count) cycle(s) detected") }
        if !unreachableSteps.isEmpty { parts.append("\(unreachableSteps.count) unreachable step(s)") }
        parts.append(contentsOf: warnings)
        return parts.joined(separator: "; ")
    }
}

struct ExecutionPlan: Sendable {
    let waves: [[WorkflowStep]]
    let totalEstimate: TimeInterval
    let criticalPath: [WorkflowStep]
    let isValid: Bool

    var waveCount: Int { waves.count }
    var maxParallelism: Int { waves.map(\.count).max() ?? 0 }

    var description: String {
        var lines: [String] = []
        lines.append("Execution Plan (\(waveCount) waves, ~\(Int(totalEstimate))s estimated)")
        for (index, wave) in waves.enumerated() {
            let stepNames = wave.map(\.name).joined(separator: " | ")
            let waveDuration = wave.map(\.estimatedDuration).max() ?? 0
            lines.append("  Wave \(index + 1) [\(Int(waveDuration))s]: \(stepNames)")
        }
        if !criticalPath.isEmpty {
            lines.append("  Critical path: \(criticalPath.map(\.name).joined(separator: " -> "))")
        }
        return lines.joined(separator: "\n")
    }
}

struct WorkflowOptimization: Sendable, Identifiable {
    let id = UUID()
    let type: OptimizationType
    let stepIds: [UUID]
    let description: String
    let estimatedTimeSaving: TimeInterval

    enum OptimizationType: String, Sendable {
        case parallelizable
        case splitStep
        case reduceDependencies
        case mergeSteps
        case reorder
    }
}
