import SwiftUI

// MARK: - Settings Router
//
// Carries "open Settings to this tab" across the scene boundary. Entry points
// set `pendingTab` (via the ContentView showSettings bridge) before the macOS
// `Settings{}` window opens; SettingsView consumes and clears it. The sheet
// path on iOS keeps using `initialTab` directly.
@MainActor
final class SettingsRouter: ObservableObject {
    static let shared = SettingsRouter()

    @Published var pendingTab: SettingsTab?
}
