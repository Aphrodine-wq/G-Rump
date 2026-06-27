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

    /// Optional slim-backend base URL. When non-empty, chat requests route through
    /// the backend proxy (Bearer = appAPIKey) instead of calling Qwen directly.
    @AppStorage("BackendURL") var backendURL: String = ""

    /// Shared backend API key (APP_API_KEY). Stored in Keychain, not UserDefaults.
    /// Empty is valid: the backend runs open in local dev.
    var appAPIKey: String {
        get { KeychainStorage.get(account: "AppAPIKey") ?? "" }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                KeychainStorage.delete(account: "AppAPIKey")
            } else {
                KeychainStorage.set(account: "AppAPIKey", value: trimmed)
            }
        }
    }
    #if os(iOS)
    @AppStorage("HapticFeedbackEnabled") var hapticFeedbackEnabled: Bool = true
    #endif
    #if os(macOS)
    @AppStorage("ShowMenuBarExtra") var showMenuBarExtra: Bool = false
    #endif
}
