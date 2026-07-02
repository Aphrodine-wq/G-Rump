import Foundation
#if os(macOS)
import AppKit
#endif
import UserNotifications

// MARK: - Channel Capabilities
//
// Adapted from OpenClaw's `src/channels/plugins/types.adapters.ts`.

struct ChannelCapabilities: OptionSet, Sendable {
    let rawValue: Int

    static let richContent = ChannelCapabilities(rawValue: 1 << 0)
    static let actions     = ChannelCapabilities(rawValue: 1 << 1)
    static let persistent  = ChannelCapabilities(rawValue: 1 << 2)
    static let background  = ChannelCapabilities(rawValue: 1 << 3)
}

// MARK: - Delivery Result

enum DeliveryResult: Sendable {
    case delivered
    case failed(String)
    case unavailable
}

// MARK: - Suggestion Channel Protocol

/// Protocol for delivery adapters, mirroring OpenClaw's `ChannelPlugin` type.
protocol SuggestionChannel: Identifiable, Sendable {
    var id: String { get }
    var priority: Int { get }
    var capabilities: ChannelCapabilities { get }
    func deliver(_ suggestion: ProactiveSuggestion) async -> DeliveryResult
    func canDeliver(urgency: UrgencyLevel) -> Bool
}

// MARK: - Channel Registry

/// Manages registered channels with deduplication and priority sorting.
/// Mirrors OpenClaw's `registerChannelPlugin()` with `pluginsByNormalizedId`.
actor SuggestionChannelRegistry {

    private var channels: [String: any SuggestionChannel] = [:]

    func register(_ channel: any SuggestionChannel) {
        channels[channel.id] = channel
        GRumpLogger.proactive.debug("Channel registered: \(channel.id) (priority: \(channel.priority))")
    }

    func unregister(id: String) {
        channels.removeValue(forKey: id)
    }

    /// Get channels sorted by priority (highest first).
    func sortedChannels() -> [any SuggestionChannel] {
        channels.values.sorted { $0.priority > $1.priority }
    }

    /// Resolve which channels to use based on urgency and app state.
    /// Mirrors OpenClaw's `resolveOutboundAdapter()`.
    func resolveChannels(for urgency: UrgencyLevel, appInForeground: Bool) -> [any SuggestionChannel] {
        let sorted = sortedChannels()

        return sorted.filter { channel in
            guard channel.canDeliver(urgency: urgency) else { return false }

            if !appInForeground && !channel.capabilities.contains(.background) {
                return false
            }

            return true
        }
    }
}

// MARK: - Banner Channel

/// In-app banner overlay delivery. Capabilities: richContent, actions, persistent.
struct BannerChannel: SuggestionChannel {
    let id = "banner"
    let priority = 100
    let capabilities: ChannelCapabilities = [.richContent, .actions, .persistent]

    func deliver(_ suggestion: ProactiveSuggestion) async -> DeliveryResult {
        // Post notification for SuggestionBannerView to pick up
        await MainActor.run {
            NotificationCenter.default.post(
                name: .init("GRumpProactiveSuggestion"),
                object: nil,
                userInfo: ["suggestionId": suggestion.id, "title": suggestion.title, "detail": suggestion.detail, "icon": suggestion.icon]
            )
        }
        return .delivered
    }

    func canDeliver(urgency: UrgencyLevel) -> Bool {
        true
    }
}

// MARK: - Notification Channel

/// System notification delivery via UNUserNotificationCenter.
/// Capabilities: actions, background.
struct NotificationChannel: SuggestionChannel {
    let id = "notification"
    let priority = 80
    let capabilities: ChannelCapabilities = [.actions, .background]

    func deliver(_ suggestion: ProactiveSuggestion) async -> DeliveryResult {
        let content = UNMutableNotificationContent()
        content.title = suggestion.title
        content.body = suggestion.detail
        content.sound = suggestion.urgency.tier == .critical ? .default : nil
        content.categoryIdentifier = "GRUMP_PROACTIVE_SUGGESTION"
        content.userInfo = [
            "suggestionId": suggestion.id,
            "suggestionType": suggestion.type.rawValue,
            "prompt": suggestion.prompt
        ]
        content.threadIdentifier = "proactive-\(suggestion.type.rawValue)"

        let request = UNNotificationRequest(
            identifier: "proactive-\(suggestion.id)",
            content: content,
            trigger: nil
        )

        guard GRumpRuntime.notificationsAvailable else { return .failed("notifications unavailable") }
        do {
            try await UNUserNotificationCenter.current().add(request)
            return .delivered
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func canDeliver(urgency: UrgencyLevel) -> Bool {
        // Only deliver notifications for medium+ urgency
        urgency.score >= 40
    }
}

// MARK: - Menu Bar Channel

/// Badge + dropdown in menu bar agent. Capabilities: richContent, persistent.
struct MenuBarChannel: SuggestionChannel {
    let id = "menubar"
    let priority = 60
    let capabilities: ChannelCapabilities = [.richContent, .persistent]

    func deliver(_ suggestion: ProactiveSuggestion) async -> DeliveryResult {
        await MainActor.run {
            NotificationCenter.default.post(
                name: .init("GRumpMenuBarSuggestion"),
                object: nil,
                userInfo: ["suggestionId": suggestion.id, "title": suggestion.title, "icon": suggestion.icon]
            )
        }
        return .delivered
    }

    func canDeliver(urgency: UrgencyLevel) -> Bool {
        true
    }
}

// MARK: - Popover Channel

/// Inline display in QuickChatPopover. Capabilities: richContent, actions.
struct PopoverChannel: SuggestionChannel {
    let id = "popover"
    let priority = 40
    let capabilities: ChannelCapabilities = [.richContent, .actions]

    func deliver(_ suggestion: ProactiveSuggestion) async -> DeliveryResult {
        await MainActor.run {
            NotificationCenter.default.post(
                name: .init("GRumpPopoverSuggestion"),
                object: nil,
                userInfo: ["suggestionId": suggestion.id, "title": suggestion.title, "prompt": suggestion.prompt]
            )
        }
        return .delivered
    }

    func canDeliver(urgency: UrgencyLevel) -> Bool {
        true
    }
}
