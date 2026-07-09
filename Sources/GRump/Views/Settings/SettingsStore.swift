import SwiftUI

@MainActor
final class SettingsStore: ObservableObject {
    @AppStorage("MaxAgentSteps") var maxAgentSteps: Int = 200
    @AppStorage("CompactToolResults") var compactToolResults: Bool = false
    @AppStorage("AllowSystemNotifications") var allowSystemNotifications: Bool = true
    @AppStorage("NotificationSoundEnabled") var notificationSoundEnabled: Bool = true
    @AppStorage("CheckUpdatesOnLaunch") var checkUpdatesOnLaunch: Bool = false
    @AppStorage("ShowTokenCount") var showTokenCount: Bool = false
    @AppStorage("ProjectMemoryEnabled") var projectMemoryEnabled: Bool = true

    #if os(iOS)
    @AppStorage("HapticFeedbackEnabled") var hapticFeedbackEnabled: Bool = true
    #endif
    #if os(macOS)
    @AppStorage("ShowMenuBarExtra") var showMenuBarExtra: Bool = false
    #endif
}
