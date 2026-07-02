import Foundation
import AppIntents
import SwiftUI

// MARK: - Focus Filter Service
//
// Integrates G-Rump with iOS/macOS Focus modes through App Intents.
// Automatically adjusts G-Rump's behavior based on the current Focus mode.
//

@MainActor
final class FocusFilterService: ObservableObject {

    static let shared = FocusFilterService()

    @Published var currentFocusMode: FocusMode = .none
    @Published var isFocusModeActive = false

    private init() {
        startObservingFocusChanges()
    }

    deinit {
        focusObservationTimer?.invalidate()
    }

    private var focusObservationTimer: Timer?

    private func startObservingFocusChanges() {
        // Poll system Focus state periodically
        // INFocusStatusCenter is iOS-only; on macOS we detect via Do Not Disturb defaults
        #if os(macOS)
        focusObservationTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkCurrentFocusMode()
            }
        }
        checkCurrentFocusMode()
        #endif
    }

    #if os(macOS)
    private func checkCurrentFocusMode() {
        // Read DND/Focus state from defaults
        // macOS stores Focus state in com.apple.controlcenter and com.apple.ncprefs
        let defaults = UserDefaults(suiteName: "com.apple.controlcenter")
        let dndEnabled = defaults?.bool(forKey: "NSStatusItem Visible FocusModes") ?? false

        // Also check via assertions database for active Focus
        let assertionStore = UserDefaults(suiteName: "com.apple.ncprefs")
        let activeMode: FocusMode

        if let modeData = assertionStore?.data(forKey: "activeFocusMode"),
           let modeStr = String(data: modeData, encoding: .utf8),
           let mode = FocusMode(rawValue: modeStr) {
            activeMode = mode
        } else if dndEnabled {
            activeMode = .work
        } else {
            activeMode = .none
        }

        if activeMode != currentFocusMode {
            let oldMode = currentFocusMode
            currentFocusMode = activeMode
            isFocusModeActive = activeMode != .none

            if activeMode != .none {
                let config = getConfiguration(for: activeMode)
                applyFocusConfiguration(config)
            }

            NotificationCenter.default.post(
                name: .focusModeDidChange,
                object: nil,
                userInfo: [
                    "oldMode": oldMode.rawValue,
                    "newMode": activeMode.rawValue
                ]
            )
        }
    }
    #endif

    // MARK: - Focus Mode Configuration

    func getConfiguration(for focusMode: FocusMode) -> FocusConfiguration {
        switch focusMode {
        case .work:
            return FocusConfiguration(
                allowedNotifications: [.taskComplete, .buildResult],
                agentModeId: "build",
                autoStartAgent: true,
                showDistractions: false,
                enableSounds: false,
                suggestedSkills: ["swiftui-migration", "async-await", "code-review-pr"]
            )
        case .personal:
            return FocusConfiguration(
                allowedNotifications: [.taskComplete],
                agentModeId: "chat",
                autoStartAgent: false,
                showDistractions: true,
                enableSounds: true,
                suggestedSkills: ["prompt-engineering", "regex", "git"]
            )
        case .reading:
            return FocusConfiguration(
                allowedNotifications: [.taskComplete],
                agentModeId: "spec",
                autoStartAgent: false,
                showDistractions: false,
                enableSounds: false,
                suggestedSkills: ["technical-dd", "competitive-analysis"]
            )
        case .gaming:
            return FocusConfiguration(
                allowedNotifications: [],
                agentModeId: "chat",
                autoStartAgent: false,
                showDistractions: true,
                enableSounds: true,
                suggestedSkills: []
            )
        case .none, .sleep, .driving, .exercise, .mindfulness:
            return FocusConfiguration.default
        }
    }

    // MARK: - Apply Focus Configuration

    func applyFocusConfiguration(_ config: FocusConfiguration) {
        NotificationCenter.default.post(
            name: .focusConfigurationChanged,
            object: nil,
            userInfo: ["configuration": config]
        )
    }
}

// MARK: - Focus Mode Enum

enum FocusMode: String, CaseIterable, Identifiable, Codable {
    case none, work, personal, sleep, driving, exercise, mindfulness, reading, gaming

    var id: String { rawValue }

    var displayName: String {
        rawValue.capitalized
    }

    var icon: String {
        switch self {
        case .none: return "circle"
        case .work: return "briefcase"
        case .personal: return "person"
        case .sleep: return "bed.double"
        case .driving: return "car"
        case .exercise: return "figure.run"
        case .mindfulness: return "brain.head.profile"
        case .reading: return "book"
        case .gaming: return "gamecontroller"
        }
    }

    var color: Color {
        switch self {
        case .none: return .gray
        case .work: return .blue
        case .personal: return .green
        case .sleep: return .purple
        case .driving: return .orange
        case .exercise: return .red
        case .mindfulness: return .teal
        case .reading: return .indigo
        case .gaming: return .pink
        }
    }
}

// MARK: - Focus Configuration

struct FocusConfiguration: Codable {
    let allowedNotifications: [FocusNotificationCategory]
    let agentModeId: String
    let autoStartAgent: Bool
    let showDistractions: Bool
    let enableSounds: Bool
    let suggestedSkills: [String]

    static let `default` = FocusConfiguration(
        allowedNotifications: FocusNotificationCategory.allCases,
        agentModeId: "chat",
        autoStartAgent: false,
        showDistractions: true,
        enableSounds: true,
        suggestedSkills: []
    )
}

enum FocusNotificationCategory: String, CaseIterable, Codable {
    case taskComplete = "GRUMP_TASK_COMPLETE"
    case taskFailed = "GRUMP_TASK_FAILED"
    case approvalNeeded = "GRUMP_APPROVAL_NEEDED"
    case buildResult = "GRUMP_BUILD_RESULT"

    var displayName: String {
        switch self {
        case .taskComplete: return "Task Complete"
        case .taskFailed: return "Task Failed"
        case .approvalNeeded: return "Approval Needed"
        case .buildResult: return "Build Result"
        }
    }
}

// MARK: - App Intents for Focus Integration

struct SetGRumpFocusIntent: AppIntent {
    static var title: LocalizedStringResource = "Configure G-Rump for Focus"
    static var description = IntentDescription(
        "Set how G-Rump behaves when this Focus mode is active.",
        categoryName: "Productivity"
    )

    @Parameter(title: "Focus Mode")
    var focusMode: FocusModeAppEnum

    @Parameter(title: "Agent Mode", default: .chat)
    var agentMode: FocusAgentModeAppEnum

    @Parameter(title: "Enable Notifications", default: true)
    var enableNotifications: Bool

    @Parameter(title: "Enable Sounds", default: true)
    var enableSounds: Bool

    @Parameter(title: "Auto-start Agent", default: false)
    var autoStartAgent: Bool

    func perform() async throws -> some IntentResult {
        let config = FocusConfiguration(
            allowedNotifications: enableNotifications ? FocusNotificationCategory.allCases : [],
            agentModeId: agentMode.rawValue,
            autoStartAgent: autoStartAgent,
            showDistractions: true,
            enableSounds: enableSounds,
            suggestedSkills: []
        )
        FocusConfigurationStore.shared.save(config, for: focusMode.mode)
        return .result()
    }
}

struct StartGRumpFocusSessionIntent: AppIntent {
    static var title: LocalizedStringResource = "Start G-Rump Focus Session"
    static var description = IntentDescription(
        "Start a focused coding session with G-Rump.",
        categoryName: "Productivity"
    )
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Focus Type", default: .work)
    var focusType: FocusModeAppEnum

    @Parameter(title: "Task Description")
    var taskDescription: String?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let config = await FocusFilterService.shared.getConfiguration(for: focusType.mode)
        await FocusFilterService.shared.applyFocusConfiguration(config)

        var userInfo: [String: Any] = [
            "focusMode": focusType.mode.rawValue,
            "autoStart": config.autoStartAgent
        ]
        if let task = taskDescription {
            userInfo["task"] = task
        }
        NotificationCenter.default.post(name: .startFocusSession, object: nil, userInfo: userInfo)
        return .result(dialog: IntentDialog(stringLiteral: "Started \(focusType.mode.displayName) focus session"))
    }
}

// MARK: - App Intent Enums

enum FocusModeAppEnum: String, AppEnum {
    case none, work, personal, sleep, driving, exercise, mindfulness, reading, gaming

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Focus Mode")
    }

    static var caseDisplayRepresentations: [FocusModeAppEnum: DisplayRepresentation] {
        [
            .none: DisplayRepresentation(title: "None"),
            .work: DisplayRepresentation(title: "Work", image: .init(systemName: "briefcase")),
            .personal: DisplayRepresentation(title: "Personal", image: .init(systemName: "person")),
            .sleep: DisplayRepresentation(title: "Sleep", image: .init(systemName: "bed.double")),
            .driving: DisplayRepresentation(title: "Driving", image: .init(systemName: "car")),
            .exercise: DisplayRepresentation(title: "Exercise", image: .init(systemName: "figure.run")),
            .mindfulness: DisplayRepresentation(title: "Mindfulness", image: .init(systemName: "brain.head.profile")),
            .reading: DisplayRepresentation(title: "Reading", image: .init(systemName: "book")),
            .gaming: DisplayRepresentation(title: "Gaming", image: .init(systemName: "gamecontroller"))
        ]
    }

    var mode: FocusMode {
        FocusMode(rawValue: self.rawValue) ?? .none
    }
}

enum FocusAgentModeAppEnum: String, AppEnum {
    case chat, plan, build, debate, spec

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Agent Mode")
    }

    static var caseDisplayRepresentations: [FocusAgentModeAppEnum: DisplayRepresentation] {
        [
            .chat: DisplayRepresentation(title: "Chat", image: .init(systemName: "message")),
            .plan: DisplayRepresentation(title: "Plan", image: .init(systemName: "list.bullet")),
            .build: DisplayRepresentation(title: "Build", image: .init(systemName: "hammer")),
            .debate: DisplayRepresentation(title: "Debate", image: .init(systemName: "exclamationmark.bubble")),
            .spec: DisplayRepresentation(title: "Spec", image: .init(systemName: "doc.text"))
        ]
    }
}

// MARK: - Configuration Store

class FocusConfigurationStore: ObservableObject {
    static let shared = FocusConfigurationStore()

    private let userDefaults = UserDefaults.standard
    private let configurationsKey = "FocusConfigurations"

    func save(_ configuration: FocusConfiguration, for focusMode: FocusMode) {
        var configurations = loadAll()
        configurations[focusMode.rawValue] = configuration
        if let data = try? JSONEncoder().encode(configurations) {
            userDefaults.set(data, forKey: configurationsKey)
        }
    }

    func load(for focusMode: FocusMode) -> FocusConfiguration {
        loadAll()[focusMode.rawValue] ?? FocusConfiguration.default
    }

    private func loadAll() -> [String: FocusConfiguration] {
        guard let data = userDefaults.data(forKey: configurationsKey),
              let configs = try? JSONDecoder().decode([String: FocusConfiguration].self, from: data) else {
            return [:]
        }
        return configs
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let focusConfigurationChanged = Notification.Name("FocusConfigurationChanged")
    static let startFocusSession = Notification.Name("StartFocusSession")
    static let focusModeDidChange = Notification.Name("FocusModeDidChange")
}
