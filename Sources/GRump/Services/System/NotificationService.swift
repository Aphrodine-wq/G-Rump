import Foundation
import UserNotifications
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - G-Rump Notification Service
//
// Structured notification system using UNUserNotificationCenter.
// Delivers rich, actionable notifications for agent events:
//   - Task completion (with result preview)
//   - Task failure (with error details)
//   - Approval-required tool calls
//   - Build success/failure
//
// Notifications are grouped by conversation thread ID and respect
// Do Not Disturb / Focus modes automatically via the system.

// MARK: - Notification Categories & Actions

enum GRumpNotificationCategory {
    static let taskComplete = "GRUMP_TASK_COMPLETE"
    static let taskFailed = "GRUMP_TASK_FAILED"
    static let approvalNeeded = "GRUMP_APPROVAL_NEEDED"
    static let buildResult = "GRUMP_BUILD_RESULT"
    static let agentProgress = "GRUMP_AGENT_PROGRESS"
}

enum GRumpNotificationAction {
    static let viewResult = "VIEW_RESULT"
    static let runAgain = "RUN_AGAIN"
    static let openConversation = "OPEN_CONVERSATION"
    static let approveAction = "APPROVE_ACTION"
    static let denyAction = "DENY_ACTION"
    static let viewBuildLog = "VIEW_BUILD_LOG"
}

// MARK: - Notification Service

@MainActor
final class GRumpNotificationService: NSObject, ObservableObject {

    static let shared = GRumpNotificationService()

    @Published private(set) var isAuthorized: Bool = false
    @Published private(set) var pendingApprovalId: String?

    private var center: UNUserNotificationCenter?

    private override init() {
        // UNUserNotificationCenter.current() traps under the XCTest / SPM command-line
        // runner (no app registration), even when a bundle identifier is present.
        if GRumpRuntime.notificationsAvailable {
            self.center = UNUserNotificationCenter.current()
        } else {
            self.center = nil
        }
        super.init()
        if let center = center {
            center.delegate = self
            registerCategories()
            checkAuthorization()
        }
    }

    // MARK: - Authorization

    func requestAuthorization() {
        guard let center = center else { return }
        center.requestAuthorization(options: [.alert, .sound, .badge, .provisional]) { [weak self] granted, error in
            DispatchQueue.main.async {
                self?.isAuthorized = granted
                if let error {
                    GRumpLogger.notifications.error("Auth error: \(error.localizedDescription)")
                }
            }
        }
    }

    private func checkAuthorization() {
        guard let center = center else { return }
        center.getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                self?.isAuthorized = settings.authorizationStatus == .authorized ||
                                     settings.authorizationStatus == .provisional
            }
        }
    }

    // MARK: - Register Categories with Actions

    private func registerCategories() {
        guard let center = center else { return }

        let viewAction = UNNotificationAction(
            identifier: GRumpNotificationAction.viewResult,
            title: "View Result",
            options: [.foreground]
        )
        let runAgainAction = UNNotificationAction(
            identifier: GRumpNotificationAction.runAgain,
            title: "Run Again",
            options: [.foreground]
        )
        let openAction = UNNotificationAction(
            identifier: GRumpNotificationAction.openConversation,
            title: "Open Conversation",
            options: [.foreground]
        )
        let approveAction = UNNotificationAction(
            identifier: GRumpNotificationAction.approveAction,
            title: "Approve",
            options: [.foreground]
        )
        let denyAction = UNNotificationAction(
            identifier: GRumpNotificationAction.denyAction,
            title: "Deny",
            options: [.destructive]
        )
        let viewBuildLog = UNNotificationAction(
            identifier: GRumpNotificationAction.viewBuildLog,
            title: "View Build Log",
            options: [.foreground]
        )

        let taskCompleteCategory = UNNotificationCategory(
            identifier: GRumpNotificationCategory.taskComplete,
            actions: [viewAction, runAgainAction],
            intentIdentifiers: [],
            options: []
        )
        let taskFailedCategory = UNNotificationCategory(
            identifier: GRumpNotificationCategory.taskFailed,
            actions: [openAction, runAgainAction],
            intentIdentifiers: [],
            options: []
        )
        let approvalCategory = UNNotificationCategory(
            identifier: GRumpNotificationCategory.approvalNeeded,
            actions: [approveAction, denyAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        let buildCategory = UNNotificationCategory(
            identifier: GRumpNotificationCategory.buildResult,
            actions: [viewBuildLog, openAction],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([
            taskCompleteCategory,
            taskFailedCategory,
            approvalCategory,
            buildCategory
        ])
    }

    // MARK: - Post: Agent Task Complete

    func notifyTaskComplete(
        conversationId: UUID,
        conversationTitle: String,
        modelName: String,
        resultSummary: String
    ) {
        guard isAuthorized else { return }
        guard !isAppFocused else { return }

        let content = UNMutableNotificationContent()
        content.title = "Agent Complete"
        content.subtitle = conversationTitle
        content.body = resultSummary
        content.categoryIdentifier = GRumpNotificationCategory.taskComplete
        content.threadIdentifier = conversationId.uuidString
        content.sound = .default
        content.userInfo = [
            "conversationId": conversationId.uuidString,
            "type": "taskComplete",
            "model": modelName
        ]

        let request = UNNotificationRequest(
            identifier: "task-\(UUID().uuidString)",
            content: content,
            trigger: nil // deliver immediately
        )
        center?.add(request)
    }

    // MARK: - Post: Agent Task Failed

    func notifyTaskFailed(
        conversationId: UUID,
        conversationTitle: String,
        errorMessage: String
    ) {
        guard isAuthorized else { return }
        guard !isAppFocused else { return }

        let content = UNMutableNotificationContent()
        content.title = "Agent Failed"
        content.subtitle = conversationTitle
        content.body = errorMessage
        content.categoryIdentifier = GRumpNotificationCategory.taskFailed
        content.threadIdentifier = conversationId.uuidString
        content.sound = UNNotificationSound.defaultCritical
        content.userInfo = [
            "conversationId": conversationId.uuidString,
            "type": "taskFailed"
        ]

        let request = UNNotificationRequest(
            identifier: "fail-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        center?.add(request)
    }

    // MARK: - Post: Approval Needed

    func notifyApprovalNeeded(
        conversationId: UUID,
        conversationTitle: String,
        command: String,
        approvalId: String
    ) {
        guard isAuthorized else { return }
        guard !isAppFocused else { return }

        let content = UNMutableNotificationContent()
        content.title = "Approval Required"
        content.subtitle = conversationTitle
        content.body = "Run: \(command)"
        content.categoryIdentifier = GRumpNotificationCategory.approvalNeeded
        content.threadIdentifier = conversationId.uuidString
        content.sound = .default
        content.userInfo = [
            "conversationId": conversationId.uuidString,
            "type": "approvalNeeded",
            "approvalId": approvalId,
            "command": command
        ]

        pendingApprovalId = approvalId

        let request = UNNotificationRequest(
            identifier: "approval-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        center?.add(request)
    }

    // MARK: - Post: Build Result

    func notifyBuildResult(
        conversationId: UUID,
        conversationTitle: String,
        success: Bool,
        summary: String
    ) {
        guard isAuthorized else { return }
        guard !isAppFocused else { return }

        let content = UNMutableNotificationContent()
        if success {
            content.title = "Build Succeeded"
            content.sound = .default
        } else {
            content.title = "Build Failed"
            content.sound = UNNotificationSound.defaultCritical
        }
        content.subtitle = conversationTitle
        content.body = summary
        content.categoryIdentifier = GRumpNotificationCategory.buildResult
        content.threadIdentifier = conversationId.uuidString
        content.userInfo = [
            "conversationId": conversationId.uuidString,
            "type": "buildResult",
            "success": success
        ]

        let request = UNNotificationRequest(
            identifier: "build-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        center?.add(request)
    }

    // MARK: - Clear Notifications

    func clearNotifications(for conversationId: UUID) {
        center?.getDeliveredNotifications { [weak self] notifications in
            let matching = notifications
                .filter { $0.request.content.threadIdentifier == conversationId.uuidString }
                .map { $0.request.identifier }
            self?.center?.removeDeliveredNotifications(withIdentifiers: matching)
        }
    }

    func clearAllNotifications() {
        center?.removeAllDeliveredNotifications()
    }

    // MARK: - App Focus Detection

    private var isAppFocused: Bool {
        #if os(macOS)
        return NSApp.isActive
        #else
        return UIApplication.shared.applicationState == .active
        #endif
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension GRumpNotificationService: UNUserNotificationCenterDelegate {

    // Handle notification tapped while app is in foreground
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Show banner even when app is active for approval requests
        let category = notification.request.content.categoryIdentifier
        if category == GRumpNotificationCategory.approvalNeeded {
            return [.banner, .sound]
        }
        // For other notifications, only show if app isn't focused
        return [.banner, .sound, .list]
    }

    // Handle notification action (user tapped or chose an action)
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        let conversationId = userInfo["conversationId"] as? String

        switch response.actionIdentifier {
        case GRumpNotificationAction.viewResult,
             GRumpNotificationAction.openConversation,
             GRumpNotificationAction.viewBuildLog,
             UNNotificationDefaultActionIdentifier:
            // Open the conversation
            if let idString = conversationId {
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: .init("GRumpOpenConversation"),
                        object: nil,
                        userInfo: ["conversationId": idString]
                    )
                }
            }
            #if os(macOS)
            await MainActor.run {
                NSApp.activate(ignoringOtherApps: true)
            }
            #endif

        case GRumpNotificationAction.runAgain:
            if let idString = conversationId {
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: .init("GRumpRunAgain"),
                        object: nil,
                        userInfo: ["conversationId": idString]
                    )
                }
            }

        case GRumpNotificationAction.approveAction:
            if let approvalId = userInfo["approvalId"] as? String {
                await MainActor.run {
                    self.pendingApprovalId = nil
                    NotificationCenter.default.post(
                        name: .init("GRumpApproveAction"),
                        object: nil,
                        userInfo: ["approvalId": approvalId]
                    )
                }
            }

        case GRumpNotificationAction.denyAction:
            if let approvalId = userInfo["approvalId"] as? String {
                await MainActor.run {
                    self.pendingApprovalId = nil
                    NotificationCenter.default.post(
                        name: .init("GRumpDenyAction"),
                        object: nil,
                        userInfo: ["approvalId": approvalId]
                    )
                }
            }

        default:
            break
        }
    }
}
