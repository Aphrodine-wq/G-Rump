import Foundation
import Combine
import OSLog
#if os(macOS)
import AppKit
#endif

// MARK: - Proactive Engine
//
// Central orchestrator wiring together all OpenClaw-adapted subsystems:
//   - ProactiveHookRegistry (event bus)
//   - ProactiveCronScheduler (job scheduler)
//   - SuggestionChannelRegistry (delivery adapters)
//   - SuggestionDispatcher (dispatch pipeline)
//   - SuggestionLifecycleManager (state machine)
//   - PreferenceLearner (adaptation)

@MainActor
final class ProactiveEngine: ObservableObject {

    // MARK: - Sub-systems

    let hookRegistry = ProactiveHookRegistry()
    let cronScheduler = ProactiveCronScheduler()
    let channelRegistry = SuggestionChannelRegistry()
    private(set) var dispatcher: SuggestionDispatcher!
    let lifecycleManager = SuggestionLifecycleManager()
    let preferenceLearner = PreferenceLearner()

    // MARK: - Published State

    @Published var pendingSuggestions: [ProactiveSuggestion] = []
    @Published var activeSuggestion: ProactiveSuggestion?
    @Published var isEnabled: Bool = UserDefaults.standard.object(forKey: "ProactiveEngineEnabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "ProactiveEngineEnabled")
            if isEnabled { start() } else { stop() }
        }
    }
    @Published var suggestionBadgeCount: Int = 0

    // MARK: - Private

    private let logger = GRumpLogger.proactive
    private var cancellables = Set<AnyCancellable>()
    private var stalenessTimers: [String: Task<Void, Never>] = [:]
    private var isRunning = false

    // Weak references to data sources
    private weak var activityStore: ActivityStore?
    private weak var ambientMonitor: AmbientMonitor?

    // MARK: - Init

    init() {
        dispatcher = SuggestionDispatcher(channelRegistry: channelRegistry, hookRegistry: hookRegistry)
    }

    // MARK: - Bootstrap

    /// Initialize and wire up all subsystems.
    /// Call after app launch when all dependencies are available.
    func bootstrap(activityStore: ActivityStore, ambientMonitor: AmbientMonitor) {
        self.activityStore = activityStore
        self.ambientMonitor = ambientMonitor

        Task {
            // 1. Register delivery channels
            await registerChannels()

            // 2. Register built-in hooks
            await registerHooks()

            // 3. Register cron jobs
            await registerCronJobs()

            // 4. Wire ambient monitor events to hooks
            wireAmbientMonitor()

            // 5. Wire activity store to hooks
            wireActivityStore()

            // 6. Start if enabled
            if isEnabled {
                start()
            }

            logger.info("ProactiveEngine bootstrapped")
        }
    }

    // MARK: - Start / Stop

    func start() {
        guard !isRunning else { return }
        isRunning = true

        Task {
            await cronScheduler.start()
        }

        logger.info("ProactiveEngine started")
    }

    func stop() {
        isRunning = false

        Task {
            await cronScheduler.stop()
        }

        // Cancel all staleness timers
        for (_, task) in stalenessTimers {
            task.cancel()
        }
        stalenessTimers.removeAll()

        logger.info("ProactiveEngine stopped")
    }

    // MARK: - Enqueue Suggestion

    /// Add a suggestion to the priority queue.
    /// Handles dedup, staleness timer, and dispatch.
    func enqueue(_ suggestion: ProactiveSuggestion) {
        guard isEnabled else { return }

        // Check cooldown
        Task {
            let inCooldown = await preferenceLearner.isInCooldown(type: suggestion.type)
            guard !inCooldown else {
                logger.debug("Suggestion \(suggestion.type.rawValue) skipped (cooldown)")
                return
            }

            // Dedup: don't enqueue if same type is already pending
            if pendingSuggestions.contains(where: { $0.type == suggestion.type && !$0.state.isTerminal }) {
                logger.debug("Suggestion \(suggestion.type.rawValue) skipped (already pending)")
                return
            }

            // Track in lifecycle manager
            await lifecycleManager.track(suggestion)

            // Add to pending list (sorted by urgency)
            await MainActor.run {
                pendingSuggestions.append(suggestion)
                pendingSuggestions.sort { $0.urgency > $1.urgency }
                suggestionBadgeCount = pendingSuggestions.count
            }

            // Start staleness timer
            startStalenessTimer(for: suggestion)

            // Dispatch to channels
            let appInForeground: Bool
            #if os(macOS)
            appInForeground = await MainActor.run { NSApp.isActive }
            #else
            appInForeground = true
            #endif

            let result = await dispatcher.dispatch(
                suggestion,
                preferenceLearner: preferenceLearner,
                appInForeground: appInForeground
            )

            switch result {
            case .delivered:
                _ = await lifecycleManager.transition(id: suggestion.id, to: .dispatched(channel: "auto"))
                logger.info("Suggestion dispatched: \(suggestion.type.rawValue)")
            case .skipped(let reason):
                logger.debug("Suggestion dispatch skipped: \(reason.rawValue)")
            }
        }
    }

    // MARK: - User Actions

    /// User accepted a suggestion.
    func accept(_ suggestion: ProactiveSuggestion) {
        Task {
            _ = await lifecycleManager.transition(id: suggestion.id, to: .accepted)
            await preferenceLearner.record(type: suggestion.type, action: .accepted)
            await preferenceLearner.setCooldown(type: suggestion.type)

            await MainActor.run {
                pendingSuggestions.removeAll { $0.id == suggestion.id }
                suggestionBadgeCount = pendingSuggestions.count
                activeSuggestion = suggestion
            }

            logger.info("Suggestion accepted: \(suggestion.type.rawValue)")

            // Fire accepted hook
            await hookRegistry.triggerHook(event: ProactiveEvent(
                type: .agent,
                action: .completed,
                payload: ["suggestionId": suggestion.id, "action": "accepted"]
            ))
        }
    }

    /// User snoozed a suggestion.
    func snooze(_ suggestion: ProactiveSuggestion, duration: TimeInterval = 1800) {
        Task {
            let snoozeUntil = Date().addingTimeInterval(duration)
            _ = await lifecycleManager.transition(id: suggestion.id, to: .snoozed(until: snoozeUntil))
            await preferenceLearner.record(type: suggestion.type, action: .snoozed)

            await MainActor.run {
                pendingSuggestions.removeAll { $0.id == suggestion.id }
                suggestionBadgeCount = pendingSuggestions.count
            }

            // Re-enqueue after snooze duration
            Task {
                try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                var resurfaced = suggestion
                resurfaced.state = .pending
                await MainActor.run {
                    self.enqueue(resurfaced)
                }
            }

            logger.info("Suggestion snoozed for \(Int(duration))s: \(suggestion.type.rawValue)")
        }
    }

    /// User dismissed a suggestion.
    func dismiss(_ suggestion: ProactiveSuggestion) {
        Task {
            _ = await lifecycleManager.transition(id: suggestion.id, to: .dismissed)
            await preferenceLearner.record(type: suggestion.type, action: .dismissed)
            await preferenceLearner.setCooldown(type: suggestion.type)

            await MainActor.run {
                pendingSuggestions.removeAll { $0.id == suggestion.id }
                suggestionBadgeCount = pendingSuggestions.count
            }

            cancelStalenessTimer(for: suggestion.id)

            logger.info("Suggestion dismissed: \(suggestion.type.rawValue)")
        }
    }

    /// Complete a suggestion with an outcome (after execution).
    func complete(_ suggestion: ProactiveSuggestion, outcome: SuggestionOutcome) {
        Task {
            _ = await lifecycleManager.setOutcome(id: suggestion.id, outcome: outcome)

            await MainActor.run {
                activeSuggestion = nil
            }

            // Handle chaining
            if outcome.status == .ok, let chainType = suggestion.chainOnSuccess {
                spawnChainedSuggestion(type: chainType, parentId: suggestion.id)
            } else if outcome.status == .error, let chainType = suggestion.chainOnFailure {
                spawnChainedSuggestion(type: chainType, parentId: suggestion.id)
            }

            logger.info("Suggestion completed: \(suggestion.type.rawValue) → \(outcome.status.rawValue)")
        }
    }

    // MARK: - Chaining

    private func spawnChainedSuggestion(type: ProactiveSuggestionType, parentId: String) {
        let suggestion = ProactiveSuggestion(
            type: type,
            title: type.displayName,
            detail: "Follow-up from previous action.",
            prompt: "Continue from the previous step: \(type.displayName.lowercased()).",
            icon: type.icon,
            urgency: UrgencyLevel(score: type.defaultUrgency),
            expiresAt: Date().addingTimeInterval(type.expiryInterval)
        )

        Task {
            _ = await lifecycleManager.transition(id: parentId, to: .chained(nextId: suggestion.id))
        }

        enqueue(suggestion)
        logger.info("Chained suggestion spawned: \(type.rawValue) from \(parentId)")
    }

    // MARK: - Staleness Management

    private func startStalenessTimer(for suggestion: ProactiveSuggestion) {
        guard let expiresAt = suggestion.expiresAt else { return }
        let delay = max(0, expiresAt.timeIntervalSince(Date()))

        let task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }

            await MainActor.run {
                self.pendingSuggestions.removeAll { $0.id == suggestion.id }
                self.suggestionBadgeCount = self.pendingSuggestions.count
            }

            _ = await self.lifecycleManager.transition(id: suggestion.id, to: .expired)
            self.logger.debug("Suggestion expired: \(suggestion.type.rawValue)")
        }
        stalenessTimers[suggestion.id] = task
    }

    private func cancelStalenessTimer(for id: String) {
        stalenessTimers[id]?.cancel()
        stalenessTimers.removeValue(forKey: id)
    }

    // MARK: - Channel Registration

    private func registerChannels() async {
        await channelRegistry.register(BannerChannel())
        await channelRegistry.register(NotificationChannel())
        await channelRegistry.register(MenuBarChannel())
        await channelRegistry.register(PopoverChannel())
    }

    // MARK: - Hook Registration

    private func registerHooks() async {
        // Activity hooks: tool completions/failures
        await hookRegistry.register(type: .activity, action: .toolFailed) { [weak self] event in
            guard let toolName = event.payload["toolName"] else { return }
            if toolName == "run_tests" {
                let error = event.payload["error"] ?? "Unknown error"
                let suggestion = SuggestionFactory.testFailure(testName: "test suite", error: error)
                await MainActor.run { self?.enqueue(suggestion) }
            }
        }

        // Git hooks: uncommitted changes
        await hookRegistry.register(type: .git, action: .uncommitted) { [weak self] event in
            let fileCount = Int(event.payload["fileCount"] ?? "0") ?? 0
            let hours = Int(event.payload["hours"] ?? "0") ?? 0
            guard hours >= 2 else { return }
            let suggestion = SuggestionFactory.uncommittedChanges(fileCount: fileCount, hours: hours)
            await MainActor.run { self?.enqueue(suggestion) }
        }

        // Git hooks: branch behind
        await hookRegistry.register(type: .git, action: .behind) { [weak self] event in
            let behindBy = Int(event.payload["behindBy"] ?? "0") ?? 0
            guard behindBy >= 5 else { return }
            let suggestion = SuggestionFactory.branchStale(behindBy: behindBy)
            await MainActor.run { self?.enqueue(suggestion) }
        }

        // Ambient hooks: app switch (context switch detection)
        await hookRegistry.register(type: .ambient, action: .appSwitch) { [weak self] event in
            guard let from = event.payload["from"], let to = event.payload["to"] else { return }
            // Only fire for IDE/terminal switches
            let devApps = ["Xcode", "Terminal", "iTerm2", "VS Code", "G-Rump"]
            if devApps.contains(from) && devApps.contains(to) && from != to {
                let suggestion = SuggestionFactory.contextSwitch(fromProject: from, toProject: to)
                await MainActor.run { self?.enqueue(suggestion) }
            }
        }

        logger.info("Built-in hooks registered")
    }

    // MARK: - Cron Job Registration

    private func registerCronJobs() async {
        // Git poll: every 5 minutes
        await cronScheduler.addJob(id: "git-poll", label: "Git Status Poll", schedule: .interval(300)) { [weak self] in
            guard let self else { return .skip }
            await self.pollGitStatus()
            return .success
        }

        // End of day review: daily at 5:30 PM
        await cronScheduler.addJob(id: "daily-review", label: "End of Day Review", schedule: .dailyAt(hour: 17, minute: 30)) { [weak self] in
            guard let self else { return .skip }
            let suggestion = SuggestionFactory.endOfDayReview()
            await MainActor.run { self.enqueue(suggestion) }
            return .success
        }

        // Morning brief: daily at 8:30 AM
        await cronScheduler.addJob(id: "morning-brief", label: "Morning Brief", schedule: .dailyAt(hour: 8, minute: 30)) { [weak self] in
            guard let self else { return .skip }
            let suggestion = SuggestionFactory.morningBrief()
            await MainActor.run { self.enqueue(suggestion) }
            return .success
        }

        // Focus check: every 30 minutes
        await cronScheduler.addJob(id: "focus-check", label: "Focus Check", schedule: .interval(1800)) { [weak self] in
            guard let self else { return .skip }
            await self.checkFocusState()
            return .success
        }

        // Orphan cleanup: every hour
        await cronScheduler.addJob(id: "orphan-cleanup", label: "Orphan Cleanup", schedule: .interval(3600)) { [weak self] in
            guard let self else { return .skip }
            await self.lifecycleManager.cleanupOrphans()
            return .success
        }

        // Heartbeat: every 15 minutes
        await cronScheduler.addJob(id: "heartbeat", label: "Scheduler Heartbeat", schedule: .interval(900)) { [weak self] in
            guard let self else { return .skip }
            await self.cronScheduler.heartbeat()
            return .success
        }

        // Autonomous daemon cycle: every 60s (self-gates on BrainConfig.daemonEnabled).
        await cronScheduler.addJob(id: "daemon-cycle", label: "Autonomous Daemon", schedule: .interval(60)) {
            await AutonomousLoop.shared.tick()
            return .success
        }

        // Daemon immune self-heal: hourly.
        await cronScheduler.addJob(id: "daemon-immune", label: "Daemon Immune Check", schedule: .interval(3600)) {
            await AutonomousLoop.shared.immuneTick()
            return .success
        }

        logger.info("Cron jobs registered")
    }

    // MARK: - Wiring

    private func wireAmbientMonitor() {
        ambientMonitor?.onContextEvent = { [weak self] event in
            guard let self else { return }
            let proactiveEvent: ProactiveEvent
            switch event.type {
            case .appSwitch:
                proactiveEvent = ProactiveEvent(type: .ambient, action: .appSwitch, payload: event.data)
            case .clipboardChange:
                proactiveEvent = ProactiveEvent(type: .ambient, action: .clipboardChange, payload: event.data)
            default:
                return
            }
            Task {
                await self.hookRegistry.triggerHook(event: proactiveEvent)
            }
        }
    }

    private func wireActivityStore() {
        // Observe activity store entries via Combine
        activityStore?.$entries
            .dropFirst()
            .sink { [weak self] entries in
                guard let self, let latest = entries.first else { return }
                let action: ProactiveEventAction = latest.success ? .toolCompleted : .toolFailed
                let event = ProactiveEvent(
                    type: .activity,
                    action: action,
                    payload: [
                        "toolName": latest.toolName,
                        "success": "\(latest.success)",
                        "summary": latest.summary
                    ]
                )
                Task {
                    await self.hookRegistry.triggerHook(event: event)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Cron Job Handlers

    private func pollGitStatus() async {
        // Simple git status check using shell
        #if os(macOS)
        guard let activityStore, !activityStore.entries.isEmpty else { return }

        // Check for uncommitted changes
        let recentEdits = activityStore.entries.prefix(30).filter { e in
            ["write_file", "edit_file", "create_file"].contains(e.toolName) && e.success
        }
        let lastCommit = activityStore.entries.first { $0.toolName == "git_commit" && $0.success }
        let hoursSinceCommit: Int
        if let commit = lastCommit {
            hoursSinceCommit = Int(Date().timeIntervalSince(commit.timestamp) / 3600)
        } else {
            hoursSinceCommit = 0
        }

        if recentEdits.count >= 3 && hoursSinceCommit >= 2 {
            await hookRegistry.triggerHook(event: ProactiveEvent(
                type: .git,
                action: .uncommitted,
                payload: [
                    "fileCount": "\(recentEdits.count)",
                    "hours": "\(hoursSinceCommit)"
                ]
            ))
        }
        #endif
    }

    private func checkFocusState() async {
        // Check ambient monitor for prolonged focus on one file
        // This is a simplified check — real implementation would track file focus time
        #if os(macOS)
        let events = await MainActor.run { ambientMonitor?.recentEvents ?? [] }
        let appSwitches = events.filter { $0.type == .appSwitch }

        // If no app switches in last 30 minutes, user is focused
        let recentSwitches = appSwitches.filter { Date().timeIntervalSince($0.timestamp) < 1800 }
        if recentSwitches.isEmpty && !events.isEmpty {
            let suggestion = SuggestionFactory.focusReminder(fileName: "current file", minutes: 120)
            await MainActor.run { self.enqueue(suggestion) }
        }
        #endif
    }
}
