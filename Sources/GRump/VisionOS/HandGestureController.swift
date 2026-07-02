import Foundation
import SwiftUI

// MARK: - Hand Gesture Controller
//
// Processes hand gestures for code editing in 3D space.
// Enables intuitive manipulation of code with air gestures.
// Requires visionOS — stubbed on macOS/iOS.
//

// MARK: - Shared Types

enum GestureType: String, CaseIterable {
    case pinch, swipe, rotate, tap, grab, scroll
}

enum GestureState: String {
    case idle, pinching, swiping, rotating, tapping, grabbing, calibrating
}

enum SwipeDirection {
    case left, right, up, down
}

struct HandGestureInfo {
    let type: GestureType
    let hand: HandChirality
    let properties: [String: Any]
    let confidence: Float
}

enum HandChirality {
    case left, right
}

struct GestureEvent {
    let gesture: HandGestureInfo
    let timestamp: Date
    let leftHandPosition: SIMD3<Float>?
    let rightHandPosition: SIMD3<Float>?
}

// MARK: - Notification Names

extension Notification.Name {
    static let handGestureRecognized = Notification.Name("HandGestureRecognized")
    static let rotationGesturePerformed = Notification.Name("RotationGesturePerformed")
    static let tapGesturePerformed = Notification.Name("TapGesturePerformed")
    static let grabGesturePerformed = Notification.Name("GrabGesturePerformed")
    static let scrollGesturePerformed = Notification.Name("ScrollGesturePerformed")
    static let showGestureVisualization = Notification.Name("ShowGestureVisualization")
    static let hideGestureVisualization = Notification.Name("HideGestureVisualization")
    static let startCalibration = Notification.Name("StartCalibration")
    static let navigatePrevious = Notification.Name("NavigatePrevious")
    static let navigateNext = Notification.Name("NavigateNext")
    static let scrollUp = Notification.Name("ScrollUp")
    static let scrollDown = Notification.Name("ScrollDown")
    static let toggleAIAssistant = Notification.Name("ToggleAIAssistant")
}

// MARK: - Platform Implementation

#if os(visionOS)
import ARKit
import RealityKit

@MainActor
final class HandGestureController: ObservableObject {

    @Published var leftHandPosition: SIMD3<Float>?
    @Published var rightHandPosition: SIMD3<Float>?
    @Published var currentGesture: HandGestureInfo?
    @Published var gestureState: GestureState = .idle
    @Published var isHandTrackingAvailable = false
    @Published var pinchStrength: Float = 0.0
    @Published var isPinching = false

    private var gestureHistory: [GestureEvent] = []
    private let pinchThreshold: Float = 0.8

    var spatialTapGesture: SpatialTapGesture { SpatialTapGesture() }

    init() {
        isHandTrackingAvailable = false
    }

    func enableGestureVisualization() {
        NotificationCenter.default.post(name: .showGestureVisualization, object: nil)
    }

    func disableGestureVisualization() {
        NotificationCenter.default.post(name: .hideGestureVisualization, object: nil)
    }

    func calibrateGestures() {
        gestureState = .calibrating
        NotificationCenter.default.post(name: .startCalibration, object: nil)
    }
}

#else

// macOS/iOS stub
@MainActor
final class HandGestureController: ObservableObject {
    @Published var leftHandPosition: SIMD3<Float>?
    @Published var rightHandPosition: SIMD3<Float>?
    @Published var gestureState: GestureState = .idle
    @Published var isHandTrackingAvailable = false
    @Published var pinchStrength: Float = 0.0
    @Published var isPinching = false

    init() {}
    func enableGestureVisualization() {}
    func disableGestureVisualization() {}
    func calibrateGestures() {}
}

#endif
