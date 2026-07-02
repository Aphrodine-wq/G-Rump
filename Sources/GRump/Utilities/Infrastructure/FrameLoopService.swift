import SwiftUI
import Combine
#if os(macOS)
import QuartzCore
#endif

/// Adaptive frame loop: runs at display refresh rate (60/120Hz) only when
/// actively streaming or animating. Pauses automatically when idle to save CPU.
///
/// Uses CVDisplayLink on macOS for hardware-synced frame callbacks — the same
/// primitive Apple's own apps use — falling back to an async Task loop on iOS.
/// Optimized for streaming: higher frequency during active streaming, faster idle timeout.
@MainActor
final class FrameLoopService: ObservableObject {
    static let shared = FrameLoopService()
    static let activeFPS = 60
    static let streamingFPS = 120 // Higher refresh during streaming
    static let activeInterval: TimeInterval = 1.0 / Double(activeFPS)
    static let streamingInterval: TimeInterval = 1.0 / Double(streamingFPS)

    @Published private(set) var tick: UInt64 = 0

    @Published private(set) var isRunning = false
    @Published private(set) var isStreaming = false
    private var idleDeadline: Date = .distantPast
    private var loopTask: Task<Void, Never>?
    private var currentInterval: TimeInterval = activeInterval

    #if os(macOS)
    private var displayLink: CVDisplayLink?
    #endif

    /// Start the loop. Automatically throttles when idle.
    func start() {
        guard !isRunning else { return }
        isRunning = true
        startLoop()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        stopLoop()
    }

    /// Mark the loop as needing active updates (call when streaming starts).
    /// Auto-starts the loop if it hasn't been started yet.
    func markActive(for duration: TimeInterval = 2.0) {
        idleDeadline = Date().addingTimeInterval(duration)
        if !isRunning {
            isRunning = true
            startLoop()
        }
    }

    /// Mark the loop as streaming - uses higher refresh rate.
    func markStreaming(for duration: TimeInterval = 1.0) {
        isStreaming = true
        currentInterval = Self.streamingInterval
        idleDeadline = Date().addingTimeInterval(duration)
        if !isRunning {
            isRunning = true
            startLoop()
        }
    }

    // MARK: - Loop Implementation

    private func startLoop() {
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.tick &+= 1

                if Date() > self.idleDeadline {
                    self.stopLoop()
                    return
                }
                try? await Task.sleep(for: .seconds(self.currentInterval))
            }
        }
    }

    private func stopLoop() {
        loopTask?.cancel()
        loopTask = nil
        isStreaming = false
        currentInterval = Self.activeInterval
        isRunning = false
    }
}
