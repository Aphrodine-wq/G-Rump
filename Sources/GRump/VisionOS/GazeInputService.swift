import Foundation
import SwiftUI

// MARK: - Gaze Input Service
//
// Tracks eye gaze for code navigation and selection in visionOS.
// Enables intuitive code interaction with just your eyes.
// Requires visionOS — stubbed on macOS/iOS.
//

#if os(visionOS)
import ARKit
import RealityKit

@MainActor
final class GazeInputService: ObservableObject {

    @Published var gazePosition: SIMD3<Float>?
    @Published var gazeTarget: Entity?
    @Published var isGazeTrackingAvailable = false
    @Published var gazeConfidence: Float = 0.0
    @Published var dwellProgress: Float = 0.0
    @Published var isDwelling = false

    private var dwellTimer: Timer?

    private let dwellThreshold: TimeInterval = 1.5
    private let confidenceThreshold: Float = 0.7

    init() {}

    // MARK: - Dwell Selection

    func resetDwellTimer() {
        dwellTimer?.invalidate()
        dwellTimer = nil
        dwellProgress = 0.0
        isDwelling = false
    }

    func enableGazeCursor() {
        NotificationCenter.default.post(name: .gazeTargetChanged, object: nil)
    }

    func disableGazeCursor() {
        NotificationCenter.default.post(name: .gazeSelectionPerformed, object: nil)
    }
}

#else

// macOS/iOS stub
@MainActor
final class GazeInputService: ObservableObject {
    @Published var gazePosition: SIMD3<Float>?
    @Published var isGazeTrackingAvailable = false
    @Published var gazeConfidence: Float = 0.0
    @Published var dwellProgress: Float = 0.0
    @Published var isDwelling = false

    init() {}
    func enableGazeCursor() {}
    func disableGazeCursor() {}
}

#endif

// MARK: - Notification Names

extension Notification.Name {
    static let gazeTargetChanged = Notification.Name("GazeTargetChanged")
    static let gazeSelectionPerformed = Notification.Name("GazeSelectionPerformed")
    static let showGazeCursor = Notification.Name("ShowGazeCursor")
    static let hideGazeCursor = Notification.Name("HideGazeCursor")
}
