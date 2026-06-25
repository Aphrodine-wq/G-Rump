import Foundation

/// Lightweight self-awareness: tracks recent tool usage and surfaces a focus-drift signal
/// (tool variety over a short window). Read-only and fail-soft — it never blocks work.
@MainActor
final class AwarenessMonitor: ObservableObject {
    static let shared = AwarenessMonitor()

    @Published private(set) var recentTools: [String] = []
    @Published private(set) var focusDrift: Double = 0   // 0 = focused, 1 = thrashing

    private let window = 12

    private init() {}

    func record(tool: String) {
        recentTools.append(tool)
        if recentTools.count > window {
            recentTools.removeFirst(recentTools.count - window)
        }
        let distinct = Set(recentTools).count
        focusDrift = recentTools.count >= 4 ? Double(distinct) / Double(recentTools.count) : 0
    }

    var summary: String {
        guard recentTools.count >= 4 else { return "Focus: warming up." }
        let pct = Int(focusDrift * 100)
        let label = focusDrift > 0.7 ? "high drift" : (focusDrift > 0.4 ? "some drift" : "focused")
        return "Focus: \(label) (\(pct)% tool variety over last \(recentTools.count))"
    }
}
