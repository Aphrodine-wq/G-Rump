import Foundation
import SwiftUI
#if os(macOS)
import AppKit
import UserNotifications
#endif

// MARK: - Live Activity Models
//
// ActivityKit attributes and content state for G-Rump agent tasks.
// Shows agent progress on the iOS Lock Screen and Dynamic Island.
//
// These models are defined in the main target so they can be shared
// with a future Widget Extension target. ActivityKit itself requires
// iOS 16.1+ and is only available on iPhone.
//
// On macOS, these are compile-time stubs that allow shared code to
// reference the types without #if os(iOS) guards everywhere.

#if os(iOS)
import ActivityKit

// MARK: - Agent Task Live Activity

struct AgentTaskAttributes: ActivityAttributes {
    /// Static context that doesn't change during the activity.
    let conversationId: String
    let conversationTitle: String
    let modelName: String
    let startedAt: Date

    /// Dynamic state that updates as the agent progresses.
    struct ContentState: Codable, Hashable {
        let currentStep: String
        let stepNumber: Int
        let totalSteps: Int
        let status: AgentStatus
        let elapsedSeconds: Int

        enum AgentStatus: String, Codable, Hashable {
            case running
            case paused
            case completed
            case failed
        }

        var progressFraction: Double {
            guard totalSteps > 0 else { return 0 }
            return Double(stepNumber) / Double(totalSteps)
        }

        var statusIcon: String {
            switch status {
            case .running:   return "bolt.circle.fill"
            case .paused:    return "pause.circle.fill"
            case .completed: return "checkmark.circle.fill"
            case .failed:    return "xmark.circle.fill"
            }
        }

        var statusColor: Color {
            switch status {
            case .running:   return .orange
            case .paused:    return .yellow
            case .completed: return .green
            case .failed:    return .red
            }
        }
    }
}

// MARK: - Live Activity Manager

@MainActor
final class LiveActivityManager: ObservableObject {

    static let shared = LiveActivityManager()

    @Published private(set) var isActivityActive: Bool = false
    private var currentActivity: Activity<AgentTaskAttributes>?

    private init() {}

    /// Start a new Live Activity for an agent task.
    func startAgentActivity(
        conversationId: UUID,
        conversationTitle: String,
        modelName: String,
        initialStep: String
    ) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            GRumpLogger.liveActivity.info("Activities not enabled")
            return
        }

        let attributes = AgentTaskAttributes(
            conversationId: conversationId.uuidString,
            conversationTitle: conversationTitle,
            modelName: modelName,
            startedAt: Date()
        )

        let initialState = AgentTaskAttributes.ContentState(
            currentStep: initialStep,
            stepNumber: 0,
            totalSteps: 0,
            status: .running,
            elapsedSeconds: 0
        )

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: nil),
                pushType: nil
            )
            currentActivity = activity
            isActivityActive = true
            GRumpLogger.liveActivity.info("Started: \(activity.id)")
        } catch {
            GRumpLogger.liveActivity.error("Failed to start: \(error.localizedDescription)")
        }
    }

    /// Update the Live Activity with new progress.
    func updateProgress(
        currentStep: String,
        stepNumber: Int,
        totalSteps: Int,
        elapsedSeconds: Int
    ) {
        guard let activity = currentActivity else { return }

        let state = AgentTaskAttributes.ContentState(
            currentStep: currentStep,
            stepNumber: stepNumber,
            totalSteps: totalSteps,
            status: .running,
            elapsedSeconds: elapsedSeconds
        )

        Task {
            await activity.update(.init(state: state, staleDate: nil))
        }
    }

    /// Mark the activity as paused.
    func pauseActivity(currentStep: String, stepNumber: Int, totalSteps: Int, elapsedSeconds: Int) {
        guard let activity = currentActivity else { return }

        let state = AgentTaskAttributes.ContentState(
            currentStep: currentStep,
            stepNumber: stepNumber,
            totalSteps: totalSteps,
            status: .paused,
            elapsedSeconds: elapsedSeconds
        )

        Task {
            await activity.update(.init(state: state, staleDate: nil))
        }
    }

    /// End the Live Activity (completed or failed).
    func endActivity(
        finalStep: String,
        stepNumber: Int,
        totalSteps: Int,
        success: Bool,
        elapsedSeconds: Int
    ) {
        guard let activity = currentActivity else { return }

        let state = AgentTaskAttributes.ContentState(
            currentStep: finalStep,
            stepNumber: stepNumber,
            totalSteps: totalSteps,
            status: success ? .completed : .failed,
            elapsedSeconds: elapsedSeconds
        )

        Task {
            await activity.end(.init(state: state, staleDate: nil), dismissalPolicy: .default)
            await MainActor.run {
                self.currentActivity = nil
                self.isActivityActive = false
            }
        }
    }

    /// Cancel the current activity immediately.
    func cancelActivity() {
        guard let activity = currentActivity else { return }

        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
            await MainActor.run {
                self.currentActivity = nil
                self.isActivityActive = false
            }
        }
    }
}

#else
// MARK: - macOS Stubs

struct AgentTaskAttributes {
    let conversationId: String
    let conversationTitle: String
    let modelName: String
    let startedAt: Date

    struct ContentState {
        let currentStep: String
        let stepNumber: Int
        let totalSteps: Int
        let status: AgentStatus
        let elapsedSeconds: Int

        enum AgentStatus: String {
            case running, paused, completed, failed
        }

        var progressFraction: Double {
            guard totalSteps > 0 else { return 0 }
            return Double(stepNumber) / Double(totalSteps)
        }
    }
}

@MainActor
final class LiveActivityManager: ObservableObject {
    static let shared = LiveActivityManager()
    @Published private(set) var isActivityActive: Bool = false
    @Published private(set) var currentStep: String = ""
    @Published private(set) var stepNumber: Int = 0
    @Published private(set) var totalSteps: Int = 0
    @Published private(set) var status: AgentTaskAttributes.ContentState.AgentStatus = .running
    @Published private(set) var elapsedSeconds: Int = 0
    @Published private(set) var modelName: String = ""
    @Published private(set) var conversationTitle: String = ""

    private var startTime: Date?

    func startAgentActivity(conversationId: UUID, conversationTitle: String, modelName: String, initialStep: String) {
        self.conversationTitle = conversationTitle
        self.modelName = modelName
        self.currentStep = initialStep
        self.stepNumber = 0
        self.totalSteps = 0
        self.status = .running
        self.elapsedSeconds = 0
        self.startTime = Date()
        self.isActivityActive = true

        deliverNotification(
            title: "Agent Started",
            body: "\(modelName): \(initialStep)",
            identifier: "agent-start-\(conversationId.uuidString)"
        )
    }

    func updateProgress(currentStep: String, stepNumber: Int, totalSteps: Int, elapsedSeconds: Int) {
        self.currentStep = currentStep
        self.stepNumber = stepNumber
        self.totalSteps = totalSteps
        self.elapsedSeconds = elapsedSeconds
    }

    func pauseActivity(currentStep: String, stepNumber: Int, totalSteps: Int, elapsedSeconds: Int) {
        self.currentStep = currentStep
        self.stepNumber = stepNumber
        self.totalSteps = totalSteps
        self.status = .paused
        self.elapsedSeconds = elapsedSeconds
    }

    func endActivity(finalStep: String, stepNumber: Int, totalSteps: Int, success: Bool, elapsedSeconds: Int) {
        self.currentStep = finalStep
        self.stepNumber = stepNumber
        self.totalSteps = totalSteps
        self.status = success ? .completed : .failed
        self.elapsedSeconds = elapsedSeconds
        self.isActivityActive = false

        let icon = success ? "✓" : "✗"
        deliverNotification(
            title: "Agent \(success ? "Completed" : "Failed") \(icon)",
            body: "\(modelName): \(finalStep) (\(elapsedSeconds)s)",
            identifier: "agent-end-\(UUID().uuidString)"
        )
    }

    func cancelActivity() {
        self.status = .failed
        self.isActivityActive = false
    }

    /// Progress fraction for UI bindings
    var progressFraction: Double {
        guard totalSteps > 0 else { return 0 }
        return Double(stepNumber) / Double(totalSteps)
    }

    private func deliverNotification(title: String, body: String, identifier: String) {
        guard GRumpRuntime.notificationsAvailable else { return }
        // Only deliver when app is not frontmost
        guard !NSApplication.shared.isActive else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}
#endif
