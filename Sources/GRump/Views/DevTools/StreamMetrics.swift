import Foundation
import Combine

/// Tracks real-time streaming performance metrics: tokens/sec, elapsed time, total tokens.
/// Used by the streaming UI to display a minimal status line and by the adaptive throttle
/// to tune update frequency based on model speed.
@MainActor
final class StreamMetrics: ObservableObject {

    // MARK: - Published State

    @Published private(set) var tokensPerSecond: Double = 0
    @Published private(set) var totalTokens: Int = 0
    @Published private(set) var elapsedTime: TimeInterval = 0
    @Published private(set) var isActive: Bool = false
    @Published private(set) var phase: StreamPhase = .idle

    enum StreamPhase: Equatable, Sendable {
        case idle
        case waiting       // Request sent, no tokens yet
        case streaming     // Tokens arriving
        case toolUse       // Executing tool calls
        case complete
        case error(String)
    }

    // MARK: - Adaptive Throttle

    /// Recommended UI update interval based on observed throughput.
    /// Fast models (>80 tok/s) → 8ms (~120Hz), slow models (<20 tok/s) → 33ms (~30Hz).
    var recommendedUpdateInterval: TimeInterval {
        if tokensPerSecond > 80 {
            return 0.008   // 120Hz for fast models
        } else if tokensPerSecond > 40 {
            return 0.016   // 60Hz
        } else if tokensPerSecond > 20 {
            return 0.025   // 40Hz
        } else {
            return 0.033   // 30Hz for slow models — batch more to avoid jank
        }
    }

    /// Recommended character batch size for UI updates.
    var recommendedBatchSize: Int {
        if tokensPerSecond > 80 {
            return 8
        } else if tokensPerSecond > 40 {
            return 16
        } else {
            return 32
        }
    }

    // MARK: - Internal State

    private var streamStartTime: Date?
    private var firstTokenTime: Date?
    private var lastTokenTime: Date?
    private var recentTokenTimestamps: [Date] = []
    private var elapsedTimer: Timer?

    /// Window size for rolling tokens/sec calculation (last N seconds).
    private let rollingWindowSeconds: TimeInterval = 2.0

    // MARK: - Lifecycle

    func startStream() {
        streamStartTime = Date()
        firstTokenTime = nil
        lastTokenTime = nil
        totalTokens = 0
        tokensPerSecond = 0
        elapsedTime = 0
        recentTokenTimestamps = []
        isActive = true
        phase = .waiting

        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let start = self.streamStartTime else { return }
                self.elapsedTime = Date().timeIntervalSince(start)
            }
        }
    }

    func recordTokens(_ count: Int) {
        let now = Date()
        if firstTokenTime == nil {
            firstTokenTime = now
            phase = .streaming
        }
        lastTokenTime = now
        totalTokens += count

        for _ in 0..<count {
            recentTokenTimestamps.append(now)
        }

        // Prune timestamps outside rolling window
        let cutoff = now.addingTimeInterval(-rollingWindowSeconds)
        recentTokenTimestamps.removeAll { $0 < cutoff }

        // Calculate rolling tokens/sec
        if recentTokenTimestamps.count > 1,
           let oldest = recentTokenTimestamps.first {
            let window = now.timeIntervalSince(oldest)
            if window > 0.05 {
                tokensPerSecond = Double(recentTokenTimestamps.count) / window
            }
        }
    }

    func setPhase(_ newPhase: StreamPhase) {
        phase = newPhase
    }

    func endStream(error: String? = nil) {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        isActive = false

        if let error {
            phase = .error(error)
        } else {
            phase = .complete
        }

        // Final elapsed calculation
        if let start = streamStartTime {
            elapsedTime = Date().timeIntervalSince(start)
        }
    }

    func reset() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        streamStartTime = nil
        firstTokenTime = nil
        lastTokenTime = nil
        totalTokens = 0
        tokensPerSecond = 0
        elapsedTime = 0
        recentTokenTimestamps = []
        isActive = false
        phase = .idle
    }

    // MARK: - Formatted Strings

    var formattedTokensPerSecond: String {
        if tokensPerSecond < 1 { return "–" }
        return String(format: "%.0f tok/s", tokensPerSecond)
    }

    var formattedElapsed: String {
        if elapsedTime < 1 { return "0s" }
        if elapsedTime < 60 {
            return String(format: "%.0fs", elapsedTime)
        }
        let mins = Int(elapsedTime) / 60
        let secs = Int(elapsedTime) % 60
        return "\(mins)m \(secs)s"
    }

    /// Time to first token (TTFT) — key latency metric.
    var timeToFirstToken: TimeInterval? {
        guard let start = streamStartTime, let first = firstTokenTime else { return nil }
        return first.timeIntervalSince(start)
    }

    var formattedTTFT: String? {
        guard let ttft = timeToFirstToken else { return nil }
        return String(format: "%.1fs", ttft)
    }
}
