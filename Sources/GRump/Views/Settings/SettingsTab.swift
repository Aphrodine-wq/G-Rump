// MARK: - SettingsTab Enum
//
// Navigation structure for the Settings view. Used by SettingsView
// and any caller that opens settings to a specific tab.

import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case account
    case providers
    case presets
    case behavior
    case streaming
    case advanced
    case project
    case appearance
    case tools
    case mcp
    case openClaw
    case skills
    case soul
    case brain
    #if os(macOS)
    case security
    #endif
    case notifications
    case shortcuts
    case updates
    case data
    case memory
    case privacy
    case about

    var id: String { rawValue }

    /// Two-level navigation: top-level categories with sub-pages.
    /// Each category is (icon, label, tabs). If tabs has only 1 item, it shows directly; otherwise drill-down.
    static var categories: [(icon: String, label: String, tabs: [SettingsTab])] {
        var list: [(icon: String, label: String, tabs: [SettingsTab])] = [
            ("person.crop.circle.fill", "Account", [.account]),
            ("cpu", "AI", [.providers, .presets, .behavior, .streaming, .advanced]),
            ("folder.fill", "Workspace", [.project, .tools, .mcp, .openClaw, .skills, .soul, .brain]),
            ("paintbrush.fill", "Appearance", [.appearance]),
            ("gearshape", "General", [.notifications, .shortcuts, .updates, .data, .memory, .privacy]),
            ("info.circle.fill", "About", [.about])
        ]
        #if os(macOS)
        if let idx = list.firstIndex(where: { $0.label == "Workspace" }) {
            list[idx] = ("folder.fill", "Workspace", [.project, .tools, .mcp, .openClaw, .skills, .soul, .brain, .security])
        }
        #endif
        return list
    }

    /// Flat sections for backward compatibility.
    static var sections: [(String, [SettingsTab])] {
        categories.map { ($0.label, $0.tabs) }
    }

    var label: String {
        switch self {
        case .account: return "Account"
        case .appearance: return "Appearance"
        case .providers: return "Providers"
        case .presets: return "Workflow Presets"
        case .project: return "Project"
        case .behavior: return "Behavior"
        case .streaming: return "Streaming"
        case .advanced: return "Advanced"
        case .notifications: return "Notifications"
        case .shortcuts: return "Shortcuts"
        case .updates: return "Updates"
        case .tools: return "Tools"
        case .mcp: return "MCP Servers"
        case .openClaw: return "OpenClaw"
        case .skills: return "Skills"
        case .soul: return "Soul"
        case .brain: return "Brain"
        case .data: return "Data"
        case .memory: return "Project Memory"
        case .privacy: return "Privacy & On-Device"
        #if os(macOS)
        case .security: return "Security"
        #endif
        case .about: return "About"
        }
    }

    var icon: String {
        switch self {
        case .account: return "key.fill"
        case .appearance: return "paintbrush.fill"
        case .providers: return "cpu"
        case .presets: return "square.stack.3d.up.fill"
        case .project: return "folder.fill"
        case .behavior: return "text.bubble.fill"
        case .streaming: return "waveform"
        case .advanced: return "gearshape.2"
        case .notifications: return "bell.badge.fill"
        case .shortcuts: return "command"
        case .updates: return "arrow.down.circle.fill"
        case .tools: return "wrench.and.screwdriver.fill"
        case .mcp: return "cylinder.split.1x2.fill"
        case .openClaw: return "antenna.radiowaves.left.and.right"
        case .skills: return "brain.head.profile"
        case .soul: return "person.text.rectangle.fill"
        case .brain: return "brain.filled.head.profile"
        case .data: return "square.and.arrow.up"
        case .memory: return "brain"
        case .privacy: return "lock.shield.fill"
        #if os(macOS)
        case .security: return "lock.shield.fill"
        #endif
        case .about: return "info.circle.fill"
        }
    }

    /// Top-level tab groups for horizontal tab bar. (Label, tabs in group)
    static var tabGroups: [(String, [SettingsTab])] {
        var list: [(String, [SettingsTab])] = [
            ("Account", [.account]),
            ("AI & Providers", [.providers, .presets, .behavior, .streaming]),
            ("Advanced", [.advanced]),
            ("Workspace", [.project]),
            ("Appearance", [.appearance]),
            ("Tools", [.tools]),
            ("General", [.notifications, .shortcuts, .updates, .data, .memory, .privacy]),
            ("About", [.about])
        ]
        #if os(macOS)
        if let idx = list.firstIndex(where: { $0.0 == "Tools" }) {
            list[idx] = ("Tools & Security", [.tools, .mcp, .openClaw, .skills, .soul, .brain, .security])
        }
        #else
        if let idx = list.firstIndex(where: { $0.0 == "Tools" }) {
            list[idx] = ("Tools", [.tools, .mcp, .openClaw, .skills, .soul, .brain])
        }
        #endif
        return list
    }
}

// MARK: - Notification & Updates UserDefaults Keys

enum SettingsKeys {
    static let allowSystemNotifications = "AllowSystemNotifications"
    static let notificationSoundEnabled = "NotificationSoundEnabled"
    static let checkUpdatesOnLaunch = "CheckUpdatesOnLaunch"
    static let maxAgentSteps = "MaxAgentSteps"
    static let streamingAnimationStyle = "StreamingAnimationStyle"
    static let streamDebounceMs = "StreamDebounceMs"
    static let showTokenCount = "ShowTokenCount"
    static let compactToolResults = "CompactToolResults"
    static let modelTemperature = "ModelTemperature"
    static let autoScrollBehavior = "AutoScrollBehavior"
    static let hapticFeedbackEnabled = "HapticFeedbackEnabled"
    static let showMenuBarExtra = "ShowMenuBarExtra"
    static let projectMemoryEnabled = "ProjectMemoryEnabled"
    static let semanticMemoryEnabled = "SemanticMemoryEnabled"
    static let returnToSend = "ReturnToSend"
}
