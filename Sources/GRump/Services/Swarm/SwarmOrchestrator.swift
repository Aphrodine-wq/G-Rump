// ╔══════════════════════════════════════════════════════════════╗
// ║  SwarmOrchestrator.swift                                    ║
// ║  Multi-Agent Swarm — central orchestrator actor             ║
// ╚══════════════════════════════════════════════════════════════╝

import Foundation

// MARK: - Provider Stream Signature

/// A closure that produces a streaming response from an AI provider.
/// The system prompt and user prompt are passed in; the closure returns
/// an async throwing stream of `StreamEvent` chunks.
typealias ProviderStreamFn = @Sendable (
    _ systemPrompt: String,
    _ userPrompt: String,
    _ tools: [String]?
) async throws -> AsyncThrowingStream<StreamEvent, Error>

// MARK: - Swarm Orchestrator

/// Manages the lifecycle of multi-agent swarms. Each swarm is identified
/// by a UUID and runs a set of micro-agents according to a chosen strategy.
actor SwarmOrchestrator {

    // MARK: - State

    private(set) var activeSwarms: [UUID: SwarmSession] = [:]
    private var eventContinuations: [UUID: AsyncStream<SwarmEvent>.Continuation] = [:]
    private let concurrencyLimit: Int
    private var activeSemaphoreCount: Int = 0

    init(concurrencyLimit: Int = 8) {
        self.concurrencyLimit = concurrencyLimit
    }

    // MARK: - Public API

    /// Spawn a new swarm to solve the given task using the specified strategy.
    /// Returns the final `SwarmResult` when all agents are done.
    func spawnSwarm(
        task: String,
        config: SwarmConfig,
        providerStream: @escaping ProviderStreamFn
    ) async throws -> SwarmResult {
        let session = SwarmSession(config: config)
        activeSwarms[session.id] = session

        defer {
            session.isComplete = true
            eventContinuations[session.id]?.finish()
            eventContinuations.removeValue(forKey: session.id)
            activeSwarms.removeValue(forKey: session.id)
        }

        let result: SwarmResult
        switch config.strategy {
        case .divideAndConquer:
            result = try await executeDivideAndConquer(
                task: task, session: session, providerStream: providerStream
            )
        case .debate:
            result = try await executeDebate(
                task: task, session: session, providerStream: providerStream
            )
        case .ensemble:
            result = try await executeEnsemble(
                task: task, session: session, providerStream: providerStream
            )
        case .pipeline:
            result = try await executePipeline(
                task: task, session: session, providerStream: providerStream
            )
        case .hierarchical:
            result = try await executeHierarchical(
                task: task, session: session, providerStream: providerStream
            )
        case .evolutionary:
            result = try await executeEvolutionary(
                task: task, session: session, providerStream: providerStream
            )
        }

        emitEvent(session.id, .swarmCompleted(result))
        return result
    }

    /// Returns an async stream of events for the given swarm.
    func eventStream(for swarmId: UUID) -> AsyncStream<SwarmEvent> {
        AsyncStream { continuation in
            eventContinuations[swarmId] = continuation
        }
    }

    /// Cancel a running swarm.
    func cancelSwarm(_ swarmId: UUID) {
        guard let session = activeSwarms[swarmId] else { return }
        session.isComplete = true
        emitEvent(swarmId, .swarmFailed("Cancelled by user"))
        eventContinuations[swarmId]?.finish()
        eventContinuations.removeValue(forKey: swarmId)
        activeSwarms.removeValue(forKey: swarmId)
    }

    /// Returns a list of active swarm IDs.
    var activeSwarmIds: [UUID] {
        Array(activeSwarms.keys)
    }

    // MARK: - Task Decomposition

    /// Use the LLM to decompose a high-level task into N subtasks.
    func decomposeTask(
        _ task: String,
        into count: Int,
        providerStream: @escaping ProviderStreamFn
    ) async throws -> [SwarmTask] {
        let systemPrompt = """
        You are a task decomposition engine. Given a high-level task, break it into \
        exactly \(count) independent subtasks. Return each subtask on its own line, \
        prefixed with a number and period (e.g., "1. Analyze the data model"). \
        Be specific and actionable. Do not add commentary.
        """

        let fullResponse = try await collectStreamResponse(
            providerStream: providerStream,
            systemPrompt: systemPrompt,
            userPrompt: task,
            tools: nil
        )

        let lines = fullResponse
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var tasks: [SwarmTask] = []
        for line in lines {
            // Strip leading number/bullet
            var description = line
            if let dotIndex = line.firstIndex(of: ".") {
                let prefix = line[line.startIndex..<dotIndex]
                if prefix.allSatisfy(\.isNumber) {
                    description = String(line[line.index(after: dotIndex)...])
                        .trimmingCharacters(in: .whitespaces)
                }
            }
            if !description.isEmpty {
                tasks.append(SwarmTask(
                    description: description,
                    priority: tasks.count
                ))
            }
        }

        // Pad or trim to requested count
        while tasks.count < count {
            tasks.append(SwarmTask(
                description: "Additional subtask \(tasks.count + 1) for: \(task)",
                priority: tasks.count
            ))
        }
        if tasks.count > count {
            tasks = Array(tasks.prefix(count))
        }

        return tasks
    }

    /// Assign agents to tasks based on role matching.
    func assignAgents(_ tasks: inout [SwarmTask], roles: [AgentRole]) -> [MicroAgentConfig] {
        var agents: [MicroAgentConfig] = []
        let roleCount = roles.count

        for i in tasks.indices {
            let role = roles[i % roleCount]
            let agent = MicroAgentConfig(
                name: "\(role.displayName)-\(i + 1)",
                role: role,
                specialization: tasks[i].description
            )
            tasks[i].assignedAgent = agent.id
            tasks[i].status = .assigned
            agents.append(agent)
        }

        return agents
    }

    // MARK: - Single Agent Execution

    /// Run a single micro-agent on a task. Returns the agent's result.
    func runAgent(
        _ config: MicroAgentConfig,
        task: SwarmTask,
        context: String,
        providerStream: @escaping ProviderStreamFn
    ) async -> AgentResult {
        let startTime = Date()

        // Acquire semaphore slot
        while activeSemaphoreCount >= concurrencyLimit {
            try? await Task.sleep(for: .milliseconds(100))
        }
        activeSemaphoreCount += 1
        defer { activeSemaphoreCount -= 1 }

        let agent = MicroAgent(config: config)
        emitEvent(nil, .agentSpawned(config.id, config.role))

        let result = await agent.execute(
            task: task,
            context: context,
            providerStream: providerStream
        )

        let elapsed = Date().timeIntervalSince(startTime)
        let finalResult = AgentResult(
            agentId: config.id,
            role: config.role,
            taskId: task.id,
            result: result.result,
            confidence: result.confidence,
            reasoning: result.reasoning,
            toolCallCount: result.toolCallCount,
            executionTime: elapsed
        )

        emitEvent(nil, .agentCompleted(config.id, finalResult))
        return finalResult
    }

    // MARK: - Consensus

    /// Build consensus from agent results using the configured threshold.
    func buildConsensus(
        _ results: [AgentResult],
        threshold: Double
    ) -> ConsensusResult {
        let consensus = SwarmConsensus()
        return consensus.buildConsensus(results, strategy: .weightedVote, threshold: threshold)
    }

    // MARK: - Strategy: Divide and Conquer

    private func executeDivideAndConquer(
        task: String,
        session: SwarmSession,
        providerStream: @escaping ProviderStreamFn
    ) async throws -> SwarmResult {
        let agentCount = min(session.config.maxAgents, 6)
        var subtasks = try await decomposeTask(task, into: agentCount, providerStream: providerStream)
        let agents = assignAgents(&subtasks, roles: [.researcher, .implementer, .architect, .reviewer])
        session.tasks = subtasks
        session.agents = agents

        // Execute all subtasks in parallel
        let results = await withTaskGroup(of: AgentResult.self, returning: [AgentResult].self) { group in
            for (i, subtask) in subtasks.enumerated() {
                let agentConfig = agents[i]
                let ctx = "Parent task: \(task)"
                group.addTask {
                    await self.runAgent(agentConfig, task: subtask, context: ctx, providerStream: providerStream)
                }
            }
            var collected: [AgentResult] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }

        session.results = results

        // Merge results
        let mergedResult = results.map(\.result).joined(separator: "\n\n---\n\n")
        let completed = results.filter { $0.confidence > 0 }.count
        let failed = results.count - completed

        return SwarmResult(
            swarmId: session.id,
            strategy: .divideAndConquer,
            totalAgents: agents.count,
            completedTasks: completed,
            failedTasks: failed,
            consensusReached: true,
            finalResult: mergedResult,
            agentResults: results,
            executionTime: session.elapsed,
            tokenUsage: 0
        )
    }

    // MARK: - Strategy: Debate

    private func executeDebate(
        task: String,
        session: SwarmSession,
        providerStream: @escaping ProviderStreamFn
    ) async throws -> SwarmResult {
        let agentCount = min(session.config.maxAgents, 4)
        let roles: [AgentRole] = [.architect, .reviewer, .implementer, .debugger]
        var agents: [MicroAgentConfig] = []
        for i in 0..<agentCount {
            agents.append(MicroAgentConfig(
                name: "Debater-\(i + 1)",
                role: roles[i % roles.count],
                specialization: "Debate participant"
            ))
        }
        session.agents = agents

        let maxRounds = 3
        var roundResults: [AgentResult] = []
        var previousArguments = ""

        for round in 1...maxRounds {
            let roundTask = SwarmTask(
                description: round == 1
                    ? task
                    : "Consider the previous arguments and refine your position:\n\(previousArguments)\n\nOriginal task: \(task)"
            )

            let results = await withTaskGroup(of: AgentResult.self, returning: [AgentResult].self) { group in
                for agent in agents {
                    group.addTask {
                        await self.runAgent(
                            agent,
                            task: roundTask,
                            context: "Debate round \(round)/\(maxRounds). Argue your position clearly.",
                            providerStream: providerStream
                        )
                    }
                }
                var collected: [AgentResult] = []
                for await result in group {
                    collected.append(result)
                }
                return collected
            }

            roundResults = results

            let votes = results.map { ConsensusVote(
                agentId: $0.agentId,
                proposedResult: $0.result,
                confidence: $0.confidence,
                reasoning: $0.reasoning
            ) }
            emitEvent(session.id, .consensusRound(round, votes))

            // Check consensus
            let consensus = buildConsensus(results, threshold: session.config.consensusThreshold)
            if consensus.agreed {
                session.results = results
                return SwarmResult(
                    swarmId: session.id,
                    strategy: .debate,
                    totalAgents: agents.count,
                    completedTasks: results.count,
                    failedTasks: 0,
                    consensusReached: true,
                    finalResult: consensus.winningResult,
                    agentResults: results,
                    executionTime: session.elapsed,
                    tokenUsage: 0
                )
            }

            // Build summary for next round
            previousArguments = results.enumerated().map { i, r in
                "Agent \(i + 1) (\(r.role.displayName)): \(r.result)"
            }.joined(separator: "\n\n")
        }

        // No consensus reached -- use highest confidence result
        session.results = roundResults
        let best = roundResults.max(by: { $0.confidence < $1.confidence })

        return SwarmResult(
            swarmId: session.id,
            strategy: .debate,
            totalAgents: agents.count,
            completedTasks: roundResults.count,
            failedTasks: 0,
            consensusReached: false,
            finalResult: best?.result ?? "No result produced",
            agentResults: roundResults,
            executionTime: session.elapsed,
            tokenUsage: 0
        )
    }

    // MARK: - Strategy: Ensemble

    private func executeEnsemble(
        task: String,
        session: SwarmSession,
        providerStream: @escaping ProviderStreamFn
    ) async throws -> SwarmResult {
        let agentCount = min(session.config.maxAgents, 5)
        let roles: [AgentRole] = [.implementer, .architect, .researcher, .optimizer, .reviewer]
        var agents: [MicroAgentConfig] = []
        for i in 0..<agentCount {
            agents.append(MicroAgentConfig(
                name: "Ensemble-\(i + 1)",
                role: roles[i % roles.count],
                specialization: "Independent solver"
            ))
        }
        session.agents = agents

        let sharedTask = SwarmTask(description: task)

        let results = await withTaskGroup(of: AgentResult.self, returning: [AgentResult].self) { group in
            for agent in agents {
                group.addTask {
                    await self.runAgent(
                        agent,
                        task: sharedTask,
                        context: "Solve this independently. Provide your best answer.",
                        providerStream: providerStream
                    )
                }
            }
            var collected: [AgentResult] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }

        session.results = results

        // Merge via consensus
        let consensus = buildConsensus(results, threshold: session.config.consensusThreshold)

        return SwarmResult(
            swarmId: session.id,
            strategy: .ensemble,
            totalAgents: agents.count,
            completedTasks: results.count,
            failedTasks: 0,
            consensusReached: consensus.agreed,
            finalResult: consensus.winningResult,
            agentResults: results,
            executionTime: session.elapsed,
            tokenUsage: 0
        )
    }

    // MARK: - Strategy: Pipeline

    private func executePipeline(
        task: String,
        session: SwarmSession,
        providerStream: @escaping ProviderStreamFn
    ) async throws -> SwarmResult {
        let stages: [(AgentRole, String)] = [
            (.researcher, "Research and gather information about the task."),
            (.architect, "Design a solution based on the research findings."),
            (.implementer, "Implement the solution based on the design."),
            (.reviewer, "Review the implementation for correctness and quality.")
        ]

        let stageCount = min(session.config.maxAgents, stages.count)
        var agents: [MicroAgentConfig] = []
        for i in 0..<stageCount {
            agents.append(MicroAgentConfig(
                name: "Stage-\(i + 1)-\(stages[i].0.displayName)",
                role: stages[i].0,
                specialization: stages[i].1
            ))
        }
        session.agents = agents

        var previousOutput = ""
        var allResults: [AgentResult] = []

        for (i, agent) in agents.enumerated() {
            let stageTask = SwarmTask(
                description: i == 0
                    ? task
                    : "\(stages[i].1)\n\nPrevious stage output:\n\(previousOutput)\n\nOriginal task: \(task)",
                priority: i
            )

            emitEvent(session.id, .agentProgress(agent.id, "Starting pipeline stage \(i + 1)"))

            let result = await runAgent(
                agent,
                task: stageTask,
                context: "Pipeline stage \(i + 1)/\(agents.count). \(stages[i].1)",
                providerStream: providerStream
            )

            allResults.append(result)
            previousOutput = result.result

            if result.confidence < 0.1 {
                // Stage produced garbage; abort pipeline
                emitEvent(session.id, .swarmFailed("Pipeline stage \(i + 1) failed with low confidence"))
                break
            }
        }

        session.results = allResults
        let failed = allResults.filter { $0.confidence < 0.1 }.count

        return SwarmResult(
            swarmId: session.id,
            strategy: .pipeline,
            totalAgents: agents.count,
            completedTasks: allResults.count - failed,
            failedTasks: failed,
            consensusReached: failed == 0,
            finalResult: previousOutput,
            agentResults: allResults,
            executionTime: session.elapsed,
            tokenUsage: 0
        )
    }

    // MARK: - Strategy: Hierarchical

    private func executeHierarchical(
        task: String,
        session: SwarmSession,
        providerStream: @escaping ProviderStreamFn
    ) async throws -> SwarmResult {
        // Create coordinator
        let coordinator = MicroAgentConfig(
            name: "Coordinator",
            role: .coordinator,
            specialization: "Lead agent: plan work, delegate to workers, synthesize."
        )

        // Create workers
        let workerCount = min(session.config.maxAgents - 1, 4)
        let workerRoles: [AgentRole] = [.researcher, .implementer, .tester, .reviewer]
        var workers: [MicroAgentConfig] = []
        for i in 0..<workerCount {
            workers.append(MicroAgentConfig(
                name: "Worker-\(i + 1)-\(workerRoles[i % workerRoles.count].displayName)",
                role: workerRoles[i % workerRoles.count],
                specialization: "Worker agent"
            ))
        }

        session.agents = [coordinator] + workers

        // Step 1: Coordinator creates plan
        let planTask = SwarmTask(
            description: "Create a work plan for this task. List \(workerCount) specific sub-assignments, one per line. Be concise.\n\nTask: \(task)"
        )
        let planResult = await runAgent(
            coordinator, task: planTask,
            context: "You have \(workerCount) workers available. Create a plan.",
            providerStream: providerStream
        )

        // Step 2: Parse plan into subtasks
        var subtasks = try await decomposeTask(task, into: workerCount, providerStream: providerStream)

        // Step 3: Workers execute in parallel
        let workerResults = await withTaskGroup(of: AgentResult.self, returning: [AgentResult].self) { group in
            for (i, worker) in workers.enumerated() {
                let st = subtasks[i]
                group.addTask {
                    await self.runAgent(
                        worker,
                        task: st,
                        context: "Coordinator's plan:\n\(planResult.result)\n\nYour assignment: \(st.description)",
                        providerStream: providerStream
                    )
                }
            }
            var collected: [AgentResult] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }

        // Step 4: Coordinator synthesizes
        let workerSummary = workerResults.enumerated().map { i, r in
            "Worker \(i + 1) (\(r.role.displayName)):\n\(r.result)"
        }.joined(separator: "\n\n---\n\n")

        let synthesisTask = SwarmTask(
            description: "Synthesize the worker results into a final answer.\n\nWorker outputs:\n\(workerSummary)\n\nOriginal task: \(task)"
        )
        let synthesisResult = await runAgent(
            coordinator, task: synthesisTask,
            context: "Combine all worker outputs into one coherent result.",
            providerStream: providerStream
        )

        var allResults = [planResult] + workerResults + [synthesisResult]
        session.results = allResults

        let failed = workerResults.filter { $0.confidence < 0.1 }.count

        return SwarmResult(
            swarmId: session.id,
            strategy: .hierarchical,
            totalAgents: session.agents.count,
            completedTasks: workerResults.count - failed + 2,
            failedTasks: failed,
            consensusReached: failed == 0,
            finalResult: synthesisResult.result,
            agentResults: allResults,
            executionTime: session.elapsed,
            tokenUsage: 0
        )
    }

    // MARK: - Strategy: Evolutionary

    private func executeEvolutionary(
        task: String,
        session: SwarmSession,
        providerStream: @escaping ProviderStreamFn
    ) async throws -> SwarmResult {
        let populationSize = min(session.config.maxAgents, 6)
        let generations = 3

        // Create initial population
        var agents: [MicroAgentConfig] = []
        let roles: [AgentRole] = [.implementer, .architect, .optimizer, .researcher, .debugger, .tester]
        for i in 0..<populationSize {
            agents.append(MicroAgentConfig(
                name: "Candidate-\(i + 1)",
                role: roles[i % roles.count],
                specialization: "Evolutionary candidate generation 1"
            ))
        }
        session.agents = agents

        var allResults: [AgentResult] = []
        var currentBestResult = ""

        for generation in 1...generations {
            let genTask = SwarmTask(
                description: generation == 1
                    ? task
                    : "Improve upon this solution. Find flaws and fix them:\n\(currentBestResult)\n\nOriginal task: \(task)"
            )

            // Generate solutions
            let results = await withTaskGroup(of: AgentResult.self, returning: [AgentResult].self) { group in
                for agent in agents {
                    group.addTask {
                        await self.runAgent(
                            agent,
                            task: genTask,
                            context: "Generation \(generation)/\(generations). Produce your best solution.",
                            providerStream: providerStream
                        )
                    }
                }
                var collected: [AgentResult] = []
                for await result in group {
                    collected.append(result)
                }
                return collected
            }

            allResults.append(contentsOf: results)

            // Evaluate fitness (confidence-based)
            let sorted = results.sorted { $0.confidence > $1.confidence }
            let topHalf = Array(sorted.prefix(max(populationSize / 2, 1)))

            // Select best
            currentBestResult = topHalf.first?.result ?? ""

            // Mutate: update agent specializations for next generation
            if generation < generations {
                for i in agents.indices {
                    agents[i] = MicroAgentConfig(
                        id: agents[i].id,
                        name: "Candidate-\(i + 1)",
                        role: agents[i].role,
                        specialization: "Evolutionary candidate generation \(generation + 1). Improve on: \(topHalf[i % topHalf.count].result.prefix(200))"
                    )
                }
            }
        }

        session.results = allResults
        let bestOverall = allResults.max(by: { $0.confidence < $1.confidence })

        return SwarmResult(
            swarmId: session.id,
            strategy: .evolutionary,
            totalAgents: agents.count,
            completedTasks: allResults.count,
            failedTasks: 0,
            consensusReached: true,
            finalResult: bestOverall?.result ?? currentBestResult,
            agentResults: allResults,
            executionTime: session.elapsed,
            tokenUsage: 0
        )
    }

    // MARK: - Helpers

    /// Emit a swarm event to any listening continuations.
    private func emitEvent(_ swarmId: UUID?, _ event: SwarmEvent) {
        if let swarmId {
            eventContinuations[swarmId]?.yield(event)
        }
        // Also emit to all active swarm continuations for broadcast events
        for (_, continuation) in eventContinuations {
            continuation.yield(event)
        }
    }

    /// Collect the full text from a provider stream.
    func collectStreamResponse(
        providerStream: @escaping ProviderStreamFn,
        systemPrompt: String,
        userPrompt: String,
        tools: [String]?
    ) async throws -> String {
        let stream = try await providerStream(systemPrompt, userPrompt, tools)
        var fullText = ""
        for try await event in stream {
            switch event {
            case .text(let chunk):
                fullText += chunk
            case .done(let final):
                if !final.isEmpty { fullText = final }
            case .toolCallDelta:
                break
            }
        }
        return fullText
    }
}
