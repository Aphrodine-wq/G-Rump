import Foundation

/// The supervised autonomous daemon. On each ~60s tick (only when enabled, the Conscience
/// gate is on, and the app is idle) it picks the top pending goal and drives the existing
/// agent loop on a scratch branch. Every mutating tool the agent runs is gated by the
/// Conscience gate AND an explicit user approval (approve-every-write). Never pushes.
@MainActor
final class AutonomousLoop {
    static let shared = AutonomousLoop()

    weak var viewModel: ChatViewModel?
    private let learning = LearningStore()
    private var consecutiveFailures = 0
    private var isRunningGoal = false

    private init() {}

    func configure(viewModel: ChatViewModel) {
        self.viewModel = viewModel
    }

    /// One autonomous cycle.
    func tick() async {
        let config = BrainConfigStore.shared.load()
        guard config.daemonEnabled else { return }
        // Hard safety dependency: never act without the Conscience gate.
        guard config.conscienceEnabled else {
            GRumpLogger.brain.warning("Daemon idle: Conscience gate is off (daemon stays read-only).")
            return
        }
        guard !isRunningGoal, let viewModel, !viewModel.isLoading else { return }

        let goalStore = GoalStore(workingDirectory: viewModel.workingDirectory)
        let pending = await goalStore.pendingGoals()
        guard !pending.isEmpty else { return }

        // Closed loop: score goals by priority + learned success for their task
        // type; park types the daemon has proven bad at (≥3 attempts, <1/3
        // success) with a visible needs-attention status instead of retrying.
        var chosen: Goal?
        var chosenType: TaskType = .general
        var bestScore = -Double.infinity
        for goal in pending {
            let type = TaskType.classify(from: goal.title + " " + goal.body)
            let key = "goal:\(type.rawValue)"
            let attempts = await learning.attempts(for: key)
            let rate = await learning.successRate(for: key)
            if attempts >= 3 && rate < 1.0 / 3.0 {
                await goalStore.markStatus(goal, "needs-attention")
                GRumpLogger.brain.warning("Daemon parked goal \"\(goal.title, privacy: .public)\": task type \(type.rawValue, privacy: .public) succeeds \(Int(rate * 100))% — needs your attention.")
                continue
            }
            let score = Double(goal.priority) + 2.0 * rate
            if score > bestScore {
                bestScore = score
                chosen = goal
                chosenType = type
            }
        }
        guard let goal = chosen else { return }

        isRunningGoal = true
        defer { isRunningGoal = false }

        await goalStore.markStatus(goal, "in-progress")
        let start = Date()
        let ok = await DaemonRunner.run(goal: goal, viewModel: viewModel)
        await goalStore.markStatus(goal, ok ? "done" : "failed")
        await learning.record(key: "goal:\(chosenType.rawValue)", success: ok, duration: Date().timeIntervalSince(start))

        // End-of-goal reflection — the daemon learns from its own work.
        if config.learningEnabled {
            let tail = (viewModel.currentConversation?.messages.suffix(6) ?? [])
                .map { "\($0.role == .user ? "user" : "assistant"): \(String($0.content.prefix(800)))" }
                .joined(separator: "\n---\n")
            let outcome = RunOutcome(
                conversationId: viewModel.currentConversation?.id,
                taskType: chosenType.rawValue, iterations: 0, toolStats: [],
                buildFailures: 0, loopPivots: 0, regressionSummary: nil,
                adversarialCriticals: 0, success: ok
            )
            _ = await ReflectionEngine.shared.reflect(
                outcome: outcome,
                transcriptTail: tail,
                injectedLessons: [],
                rejectedProposalNames: SkillProposalStore.shared.rejectedNames,
                primaryModel: viewModel.effectiveModel,
                trigger: "daemon-goal"
            )
        }

        viewModel.activityStore.append(ActivityEntry(
            toolName: "daemon_cycle",
            summary: "Goal \"\(goal.title)\" \(ok ? "completed" : "failed")",
            success: ok
        ))

        if ok {
            consecutiveFailures = 0
            GRumpNotificationService.shared.notifyTaskComplete(
                conversationId: UUID(),
                conversationTitle: "Autonomous Daemon",
                modelName: "daemon",
                resultSummary: "Worked goal: \(goal.title)"
            )
        } else {
            consecutiveFailures += 1
            if consecutiveFailures >= 3 {
                var c = config
                c.daemonEnabled = false
                BrainConfigStore.shared.save(c)
                consecutiveFailures = 0
                GRumpNotificationService.shared.notifyTaskFailed(
                    conversationId: UUID(),
                    conversationTitle: "Autonomous Daemon",
                    errorMessage: "Auto-disabled after 3 consecutive failures."
                )
            }
        }
    }

    /// Hourly self-heal check.
    func immuneTick() async {
        guard BrainConfigStore.shared.load().daemonEnabled else { return }
        let issues = await ImmuneJob.check()
        if !issues.isEmpty {
            GRumpLogger.brain.error("Daemon immune issues: \(issues.joined(separator: "; "), privacy: .public)")
        }
    }
}

/// Drives one goal through the existing agent loop on a fresh scratch branch.
enum DaemonRunner {
    @MainActor
    static func run(goal: Goal, viewModel: ChatViewModel) async -> Bool {
        let wd = viewModel.workingDirectory
        guard !wd.isEmpty else { return false }

        // Create an isolated scratch branch — daemon work never lands on the user's branch.
        let branch = "grump-daemon/\(goal.id)"
        let branched = await runGit(["checkout", "-B", branch], cwd: wd)
        guard branched else { return false }

        viewModel.isDaemonRunActive = true
        defer { viewModel.isDaemonRunActive = false }

        viewModel.createNewConversation()
        viewModel.workingDirectory = wd
        viewModel.userInput = """
        You are running autonomously on git branch \(branch). Work this goal, run the tests \
        before committing, commit your work to this branch, and NEVER push or touch main:

        \(goal.title)
        \(goal.body)
        """
        viewModel.sendMessage()

        // Wait for the agent loop to finish (cap ~10 min).
        var waited = 0
        while viewModel.isLoading && waited < 600 {
            try? await Task.sleep(for: .seconds(2))
            waited += 2
        }
        return !viewModel.isLoading
    }

    /// Run a git command off the main actor. Returns true on exit code 0.
    private static func runGit(_ args: [String], cwd: String) async -> Bool {
        await Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            p.arguments = ["git"] + args
            p.currentDirectoryURL = URL(fileURLWithPath: cwd)
            p.standardOutput = Pipe()
            p.standardError = Pipe()
            do {
                try p.run()
                p.waitUntilExit()
                return p.terminationStatus == 0
            } catch {
                return false
            }
        }.value
    }
}
