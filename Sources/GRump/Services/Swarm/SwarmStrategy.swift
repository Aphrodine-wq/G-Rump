// ╔══════════════════════════════════════════════════════════════╗
// ║  SwarmStrategy.swift                                        ║
// ║  Multi-Agent Swarm — strategy execution helpers             ║
// ╚══════════════════════════════════════════════════════════════╝

import Foundation

// MARK: - Swarm Strategy Executor

/// Static methods implementing the coordination logic for each swarm strategy.
/// These are higher-level orchestration patterns that can be used outside the
/// main SwarmOrchestrator when more customization is needed.
struct SwarmStrategyExecutor {

    // MARK: - Divide and Conquer

    /// Decompose the task into independent subtasks, assign each to an agent, merge.
    static func executeDivideAndConquer(
        task: String,
        agents: [MicroAgentConfig],
        orchestrator: SwarmOrchestrator,
        providerStream: @escaping ProviderStreamFn
    ) async throws -> SwarmResult {
        let agentCount = agents.count
        let startTime = Date()

        // Decompose
        var subtasks = try await orchestrator.decomposeTask(
            task, into: agentCount, providerStream: providerStream
        )

        // Assign agents
        for i in subtasks.indices {
            subtasks[i].assignedAgent = agents[i % agents.count].id
            subtasks[i].status = .assigned
        }

        // Execute all in parallel
        let results = await withTaskGroup(of: AgentResult.self, returning: [AgentResult].self) { group in
            for (i, subtask) in subtasks.enumerated() {
                let agent = agents[i % agents.count]
                group.addTask {
                    await orchestrator.runAgent(
                        agent,
                        task: subtask,
                        context: "Parent task: \(task)\nYou are handling subtask \(i + 1) of \(agentCount).",
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

        // Merge: concatenate results ordered by task priority
        let sortedResults = results.sorted { a, b in
            let taskA = subtasks.first(where: { $0.id == a.taskId })
            let taskB = subtasks.first(where: { $0.id == b.taskId })
            return (taskA?.priority ?? 0) < (taskB?.priority ?? 0)
        }

        let mergedResult = sortedResults.enumerated().map { i, r in
            "## Subtask \(i + 1): \(subtasks[i].description)\n\n\(r.result)"
        }.joined(separator: "\n\n---\n\n")

        let completed = results.filter { $0.confidence > 0.1 }.count
        let elapsed = Date().timeIntervalSince(startTime)

        return SwarmResult(
            swarmId: UUID(),
            strategy: .divideAndConquer,
            totalAgents: agentCount,
            completedTasks: completed,
            failedTasks: results.count - completed,
            consensusReached: true,
            finalResult: mergedResult,
            agentResults: results,
            executionTime: elapsed,
            tokenUsage: 0
        )
    }

    // MARK: - Debate

    /// Agents argue approaches in multiple rounds; best argument wins.
    static func executeDebate(
        task: String,
        agents: [MicroAgentConfig],
        rounds: Int = 3,
        orchestrator: SwarmOrchestrator,
        providerStream: @escaping ProviderStreamFn
    ) async throws -> SwarmResult {
        let startTime = Date()
        let threshold = 0.7
        var allResults: [AgentResult] = []
        var previousRoundSummary = ""

        for round in 1...rounds {
            let roundPrompt: String
            if round == 1 {
                roundPrompt = task
            } else {
                roundPrompt = """
                Round \(round) of debate. Consider the previous arguments and either \
                strengthen your position or concede to a better argument.

                Previous round positions:
                \(previousRoundSummary)

                Original task: \(task)
                """
            }

            let roundTask = SwarmTask(
                description: roundPrompt,
                metadata: ["round": "\(round)"]
            )

            // All agents debate in parallel
            let roundResults = await withTaskGroup(of: AgentResult.self, returning: [AgentResult].self) { group in
                for agent in agents {
                    group.addTask {
                        await orchestrator.runAgent(
                            agent,
                            task: roundTask,
                            context: "Debate round \(round)/\(rounds). Argue persuasively with evidence.",
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

            allResults = roundResults

            // Check for consensus
            let consensus = SwarmConsensus()
            let result = consensus.buildConsensus(roundResults, strategy: .weightedVote, threshold: threshold)

            if result.agreed {
                let elapsed = Date().timeIntervalSince(startTime)
                return SwarmResult(
                    swarmId: UUID(),
                    strategy: .debate,
                    totalAgents: agents.count,
                    completedTasks: roundResults.count,
                    failedTasks: 0,
                    consensusReached: true,
                    finalResult: result.winningResult,
                    agentResults: roundResults,
                    executionTime: elapsed,
                    tokenUsage: 0
                )
            }

            // Build summary for next round
            previousRoundSummary = roundResults.enumerated().map { i, r in
                "Agent \(i + 1) (\(r.role.displayName), confidence: \(String(format: "%.2f", r.confidence))):\n\(String(r.result.prefix(500)))"
            }.joined(separator: "\n\n")
        }

        // No consensus after all rounds; pick the best
        let best = allResults.max(by: { $0.confidence < $1.confidence })
        let elapsed = Date().timeIntervalSince(startTime)

        return SwarmResult(
            swarmId: UUID(),
            strategy: .debate,
            totalAgents: agents.count,
            completedTasks: allResults.count,
            failedTasks: 0,
            consensusReached: false,
            finalResult: best?.result ?? "",
            agentResults: allResults,
            executionTime: elapsed,
            tokenUsage: 0
        )
    }

    // MARK: - Ensemble

    /// All agents solve the same problem independently; results merged via voting.
    static func executeEnsemble(
        task: String,
        agents: [MicroAgentConfig],
        orchestrator: SwarmOrchestrator,
        providerStream: @escaping ProviderStreamFn
    ) async throws -> SwarmResult {
        let startTime = Date()
        let sharedTask = SwarmTask(description: task)

        // All agents solve independently
        let results = await withTaskGroup(of: AgentResult.self, returning: [AgentResult].self) { group in
            for (i, agent) in agents.enumerated() {
                group.addTask {
                    await orchestrator.runAgent(
                        agent,
                        task: sharedTask,
                        context: "You are solver \(i + 1) of \(agents.count). Solve independently.",
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

        // Build consensus using synthesis (since all solve the same problem)
        let consensus = SwarmConsensus()
        let result = consensus.buildConsensus(results, strategy: .synthesize, threshold: 0.6)

        let elapsed = Date().timeIntervalSince(startTime)

        return SwarmResult(
            swarmId: UUID(),
            strategy: .ensemble,
            totalAgents: agents.count,
            completedTasks: results.count,
            failedTasks: 0,
            consensusReached: result.agreed,
            finalResult: result.winningResult,
            agentResults: results,
            executionTime: elapsed,
            tokenUsage: 0
        )
    }

    // MARK: - Pipeline

    /// Agents pass output sequentially, each refining the previous result.
    static func executePipeline(
        task: String,
        agents: [MicroAgentConfig],
        orchestrator: SwarmOrchestrator,
        providerStream: @escaping ProviderStreamFn
    ) async throws -> SwarmResult {
        let startTime = Date()
        var previousOutput = ""
        var allResults: [AgentResult] = []
        var abortReason: String?

        for (i, agent) in agents.enumerated() {
            let stageDescription: String
            if i == 0 {
                stageDescription = task
            } else {
                stageDescription = """
                Continue from the previous stage's output. Refine and improve it.

                Previous stage output:
                \(String(previousOutput.prefix(4000)))

                Original task: \(task)
                """
            }

            let stageTask = SwarmTask(
                description: stageDescription,
                priority: i,
                metadata: ["stage": "\(i + 1)", "total_stages": "\(agents.count)"]
            )

            let result = await orchestrator.runAgent(
                agent,
                task: stageTask,
                context: "Pipeline stage \(i + 1)/\(agents.count). Your role: \(agent.role.displayName).",
                providerStream: providerStream
            )

            allResults.append(result)
            previousOutput = result.result

            // Abort if a stage produces very low confidence
            if result.confidence < 0.05 {
                abortReason = "Stage \(i + 1) (\(agent.role.displayName)) produced critically low confidence output."
                break
            }
        }

        let elapsed = Date().timeIntervalSince(startTime)
        let failed = abortReason != nil ? 1 : 0

        return SwarmResult(
            swarmId: UUID(),
            strategy: .pipeline,
            totalAgents: agents.count,
            completedTasks: allResults.count - failed,
            failedTasks: failed,
            consensusReached: abortReason == nil,
            finalResult: previousOutput,
            agentResults: allResults,
            executionTime: elapsed,
            tokenUsage: 0
        )
    }

    // MARK: - Hierarchical

    /// A lead coordinator delegates to specialized workers, then synthesizes.
    static func executeHierarchical(
        task: String,
        coordinator: MicroAgentConfig,
        workers: [MicroAgentConfig],
        orchestrator: SwarmOrchestrator,
        providerStream: @escaping ProviderStreamFn
    ) async throws -> SwarmResult {
        let startTime = Date()

        // Phase 1: Coordinator creates plan
        let planTask = SwarmTask(
            description: """
            Create a detailed work plan for this task. You have \(workers.count) workers:
            \(workers.enumerated().map { "\($0.offset + 1). \($0.element.name) (\($0.element.role.displayName))" }.joined(separator: "\n"))

            For each worker, write a specific assignment on its own line.
            Format: "Worker N: <assignment>"

            Task: \(task)
            """,
            metadata: ["phase": "planning"]
        )

        let planResult = await orchestrator.runAgent(
            coordinator,
            task: planTask,
            context: "You are the coordinator. Create a clear plan.",
            providerStream: providerStream
        )

        // Phase 2: Parse assignments from plan
        let planLines = planResult.result.components(separatedBy: .newlines)
        var assignments: [String] = []
        for line in planLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("worker") {
                // Strip "Worker N:" prefix
                if let colonIdx = trimmed.firstIndex(of: ":") {
                    let assignment = String(trimmed[trimmed.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
                    if !assignment.isEmpty {
                        assignments.append(assignment)
                    }
                }
            } else if !trimmed.isEmpty && trimmed.first?.isNumber == true {
                // Also handle "1. assignment" format
                if let dotIdx = trimmed.firstIndex(of: ".") {
                    let assignment = String(trimmed[trimmed.index(after: dotIdx)...]).trimmingCharacters(in: .whitespaces)
                    if !assignment.isEmpty {
                        assignments.append(assignment)
                    }
                }
            }
        }

        // Ensure we have enough assignments
        while assignments.count < workers.count {
            assignments.append("Help with: \(task)")
        }

        // Phase 3: Workers execute in parallel
        let workerResults = await withTaskGroup(of: AgentResult.self, returning: [AgentResult].self) { group in
            for (i, worker) in workers.enumerated() {
                let assignment = assignments[i % assignments.count]
                let workerTask = SwarmTask(
                    description: assignment,
                    priority: i,
                    metadata: ["worker_index": "\(i)"]
                )
                group.addTask {
                    await orchestrator.runAgent(
                        worker,
                        task: workerTask,
                        context: "Coordinator's plan:\n\(planResult.result)\n\nYour assignment: \(assignment)",
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

        // Phase 4: Coordinator synthesizes
        let workerSummary = workerResults.enumerated().map { i, r in
            "Worker \(i + 1) (\(r.role.displayName), confidence: \(String(format: "%.2f", r.confidence))):\n\(r.result)"
        }.joined(separator: "\n\n---\n\n")

        let synthesisTask = SwarmTask(
            description: """
            Synthesize the worker results into a single coherent answer.

            Worker outputs:
            \(workerSummary)

            Original task: \(task)
            """,
            metadata: ["phase": "synthesis"]
        )

        let synthesisResult = await orchestrator.runAgent(
            coordinator,
            task: synthesisTask,
            context: "Combine all worker outputs. Resolve conflicts. Produce final answer.",
            providerStream: providerStream
        )

        let allResults = [planResult] + workerResults + [synthesisResult]
        let failed = workerResults.filter { $0.confidence < 0.1 }.count
        let elapsed = Date().timeIntervalSince(startTime)

        return SwarmResult(
            swarmId: UUID(),
            strategy: .hierarchical,
            totalAgents: 1 + workers.count,
            completedTasks: allResults.count - failed,
            failedTasks: failed,
            consensusReached: failed == 0,
            finalResult: synthesisResult.result,
            agentResults: allResults,
            executionTime: elapsed,
            tokenUsage: 0
        )
    }

    // MARK: - Evolutionary

    /// Generate solution variations, evaluate fitness, select best, mutate, repeat.
    static func executeEvolutionary(
        task: String,
        agents: [MicroAgentConfig],
        generations: Int = 3,
        orchestrator: SwarmOrchestrator,
        providerStream: @escaping ProviderStreamFn
    ) async throws -> SwarmResult {
        let startTime = Date()
        let populationSize = agents.count
        var allResults: [AgentResult] = []
        var currentPopulation = agents
        var bestSolution = ""
        var bestFitness: Double = 0

        for generation in 1...generations {
            let genPrompt: String
            if generation == 1 {
                genPrompt = task
            } else {
                genPrompt = """
                Generation \(generation): Improve upon this solution. Find weaknesses, \
                fix them, and produce a strictly better version.

                Current best solution (fitness: \(String(format: "%.2f", bestFitness))):
                \(String(bestSolution.prefix(3000)))

                Original task: \(task)
                """
            }

            let genTask = SwarmTask(
                description: genPrompt,
                metadata: ["generation": "\(generation)"]
            )

            // Generate solutions in parallel
            let genResults = await withTaskGroup(of: AgentResult.self, returning: [AgentResult].self) { group in
                for (i, agent) in currentPopulation.enumerated() {
                    group.addTask {
                        await orchestrator.runAgent(
                            agent,
                            task: genTask,
                            context: "Generation \(generation)/\(generations). Candidate \(i + 1)/\(populationSize).",
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

            allResults.append(contentsOf: genResults)

            // Evaluate fitness: confidence-weighted, penalize short results
            let evaluated = genResults.map { result -> (AgentResult, Double) in
                var fitness = result.confidence
                // Bonus for substantial results
                let length = Double(result.result.count)
                if length > 200 { fitness += 0.05 }
                if length > 500 { fitness += 0.05 }
                // Penalty for very short results
                if length < 50 { fitness *= 0.5 }
                return (result, min(1.0, fitness))
            }.sorted { $0.1 > $1.1 }

            // Select top half (elitism)
            let survivors = Array(evaluated.prefix(max(populationSize / 2, 1)))

            // Update best
            if let topCandidate = survivors.first, topCandidate.1 > bestFitness {
                bestFitness = topCandidate.1
                bestSolution = topCandidate.0.result
            }

            // Mutate for next generation: create new agents with specializations
            // derived from the best solutions
            if generation < generations {
                var nextGen: [MicroAgentConfig] = []
                for i in 0..<populationSize {
                    let survivor = survivors[i % survivors.count].0
                    let mutation = MicroAgentConfig(
                        name: "Gen\(generation + 1)-Candidate-\(i + 1)",
                        role: currentPopulation[i].role,
                        specialization: """
                        Evolve from this solution (fitness \(String(format: "%.2f", survivors[i % survivors.count].1))):
                        \(String(survivor.result.prefix(300)))
                        """
                    )
                    nextGen.append(mutation)
                }
                currentPopulation = nextGen
            }
        }

        let elapsed = Date().timeIntervalSince(startTime)

        return SwarmResult(
            swarmId: UUID(),
            strategy: .evolutionary,
            totalAgents: populationSize,
            completedTasks: allResults.count,
            failedTasks: 0,
            consensusReached: bestFitness > 0.5,
            finalResult: bestSolution,
            agentResults: allResults,
            executionTime: elapsed,
            tokenUsage: 0
        )
    }
}

// MARK: - Strategy Utilities

extension SwarmStrategyExecutor {

    /// Estimate the number of LLM calls a strategy will make for given parameters.
    static func estimateCost(
        strategy: SwarmStrategy,
        agentCount: Int,
        debateRounds: Int = 3,
        evolutionGenerations: Int = 3
    ) -> Int {
        switch strategy {
        case .divideAndConquer:
            // 1 decomposition + N agent calls
            return 1 + agentCount
        case .debate:
            // N agents * R rounds
            return agentCount * debateRounds
        case .ensemble:
            // N agents (single round)
            return agentCount
        case .pipeline:
            // N stages (sequential)
            return agentCount
        case .hierarchical:
            // 1 plan + N worker calls + 1 synthesis
            return 2 + agentCount
        case .evolutionary:
            // N agents * G generations
            return agentCount * evolutionGenerations
        }
    }

    /// Suggest the best strategy for a given task type.
    static func suggestStrategy(for taskDescription: String) -> SwarmStrategy {
        let lower = taskDescription.lowercased()

        // Code review tasks -> debate
        if lower.contains("review") || lower.contains("evaluate") || lower.contains("compare") {
            return .debate
        }

        // Implementation tasks -> divide and conquer
        if lower.contains("implement") || lower.contains("build") || lower.contains("create") {
            return .divideAndConquer
        }

        // Optimization tasks -> evolutionary
        if lower.contains("optimize") || lower.contains("improve") || lower.contains("refactor") {
            return .evolutionary
        }

        // Research tasks -> ensemble
        if lower.contains("research") || lower.contains("analyze") || lower.contains("investigate") {
            return .ensemble
        }

        // Multi-step tasks -> pipeline
        if lower.contains("step") || lower.contains("then") || lower.contains("process") {
            return .pipeline
        }

        // Complex tasks -> hierarchical
        if lower.contains("plan") || lower.contains("coordinate") || lower.contains("manage") {
            return .hierarchical
        }

        // Default
        return .divideAndConquer
    }

    /// Build a default set of agents for a strategy.
    static func defaultAgents(for strategy: SwarmStrategy, count: Int) -> [MicroAgentConfig] {
        let roles: [AgentRole]
        switch strategy {
        case .divideAndConquer:
            roles = [.researcher, .implementer, .architect, .reviewer, .tester, .optimizer]
        case .debate:
            roles = [.architect, .reviewer, .implementer, .debugger]
        case .ensemble:
            roles = [.implementer, .architect, .researcher, .optimizer, .reviewer]
        case .pipeline:
            roles = [.researcher, .architect, .implementer, .reviewer]
        case .hierarchical:
            roles = [.coordinator, .researcher, .implementer, .tester, .reviewer]
        case .evolutionary:
            roles = [.implementer, .architect, .optimizer, .researcher, .debugger, .tester]
        }

        return (0..<count).map { i in
            let role = roles[i % roles.count]
            return MicroAgentConfig(
                name: "\(strategy.displayName)-\(role.displayName)-\(i + 1)",
                role: role,
                specialization: "\(strategy.displayName) participant"
            )
        }
    }
}
