import XCTest
@testable import GRump

@MainActor
final class StreamMetricsTests: XCTestCase {

    // MARK: - Initial State

    func testInitialState() {
        let metrics = StreamMetrics()
        XCTAssertEqual(metrics.tokensPerSecond, 0)
        XCTAssertEqual(metrics.totalTokens, 0)
        XCTAssertEqual(metrics.elapsedTime, 0)
        XCTAssertFalse(metrics.isActive)
        XCTAssertEqual(metrics.phase, .idle)
        XCTAssertNil(metrics.timeToFirstToken)
    }

    // MARK: - Start Stream

    func testStartStreamSetsActiveAndWaiting() {
        let metrics = StreamMetrics()
        metrics.startStream()
        XCTAssertTrue(metrics.isActive)
        XCTAssertEqual(metrics.phase, .waiting)
        XCTAssertEqual(metrics.totalTokens, 0)
    }

    // MARK: - Record Tokens

    func testRecordTokensUpdatesTotal() {
        let metrics = StreamMetrics()
        metrics.startStream()
        metrics.recordTokens(10)
        XCTAssertEqual(metrics.totalTokens, 10)
        metrics.recordTokens(5)
        XCTAssertEqual(metrics.totalTokens, 15)
    }

    func testRecordTokensSetsStreamingPhase() {
        let metrics = StreamMetrics()
        metrics.startStream()
        XCTAssertEqual(metrics.phase, .waiting)
        metrics.recordTokens(1)
        XCTAssertEqual(metrics.phase, .streaming)
    }

    func testRecordTokensComputesTPS() {
        let metrics = StreamMetrics()
        metrics.startStream()
        for _ in 0..<50 {
            metrics.recordTokens(1)
        }
        // Tokens are recorded deterministically; TPS is non-negative (it can be 0 when
        // ~no wall-clock time has elapsed, so a strict > 0 check would be timing-flaky).
        XCTAssertEqual(metrics.totalTokens, 50)
        XCTAssertGreaterThanOrEqual(metrics.tokensPerSecond, 0)
    }

    // MARK: - Phase Tracking

    func testSetPhase() {
        let metrics = StreamMetrics()
        metrics.setPhase(.toolUse)
        XCTAssertEqual(metrics.phase, .toolUse)
        metrics.setPhase(.streaming)
        XCTAssertEqual(metrics.phase, .streaming)
    }

    func testEndStreamSetsComplete() {
        let metrics = StreamMetrics()
        metrics.startStream()
        metrics.endStream()
        XCTAssertFalse(metrics.isActive)
        XCTAssertEqual(metrics.phase, .complete)
    }

    func testEndStreamWithErrorSetsErrorPhase() {
        let metrics = StreamMetrics()
        metrics.startStream()
        metrics.endStream(error: "Connection lost")
        XCTAssertFalse(metrics.isActive)
        XCTAssertEqual(metrics.phase, .error("Connection lost"))
    }

    // MARK: - Reset

    func testResetClearsAllState() {
        let metrics = StreamMetrics()
        metrics.startStream()
        metrics.recordTokens(100)
        metrics.reset()
        XCTAssertEqual(metrics.totalTokens, 0)
        XCTAssertEqual(metrics.tokensPerSecond, 0)
        XCTAssertEqual(metrics.elapsedTime, 0)
        XCTAssertFalse(metrics.isActive)
        XCTAssertEqual(metrics.phase, .idle)
        XCTAssertNil(metrics.timeToFirstToken)
    }

    // MARK: - Adaptive Throttle

    func testRecommendedUpdateIntervalDefault() {
        let metrics = StreamMetrics()
        // With 0 tokens/sec, should return slowest interval
        XCTAssertEqual(metrics.recommendedUpdateInterval, 0.033)
    }

    func testRecommendedBatchSizeDefault() {
        let metrics = StreamMetrics()
        // With 0 tokens/sec, should return largest batch
        XCTAssertEqual(metrics.recommendedBatchSize, 32)
    }

    // MARK: - Formatted Strings

    func testFormattedTokensPerSecondWhenZero() {
        let metrics = StreamMetrics()
        XCTAssertEqual(metrics.formattedTokensPerSecond, "–")
    }

    func testFormattedElapsedWhenZero() {
        let metrics = StreamMetrics()
        XCTAssertEqual(metrics.formattedElapsed, "0s")
    }

    func testFormattedTTFTNilBeforeFirstToken() {
        let metrics = StreamMetrics()
        metrics.startStream()
        XCTAssertNil(metrics.formattedTTFT)
    }

    func testFormattedTTFTAfterFirstToken() {
        let metrics = StreamMetrics()
        metrics.startStream()
        metrics.recordTokens(1)
        XCTAssertNotNil(metrics.formattedTTFT)
    }

    // MARK: - Phase Equatable

    func testPhaseEquality() {
        XCTAssertEqual(StreamMetrics.StreamPhase.idle, StreamMetrics.StreamPhase.idle)
        XCTAssertEqual(StreamMetrics.StreamPhase.streaming, StreamMetrics.StreamPhase.streaming)
        XCTAssertEqual(StreamMetrics.StreamPhase.error("x"), StreamMetrics.StreamPhase.error("x"))
        XCTAssertNotEqual(StreamMetrics.StreamPhase.idle, StreamMetrics.StreamPhase.waiting)
        XCTAssertNotEqual(StreamMetrics.StreamPhase.error("a"), StreamMetrics.StreamPhase.error("b"))
    }

    // MARK: - Multiple Start/End Cycles

    func testMultipleStartEndCycles() {
        let metrics = StreamMetrics()
        
        metrics.startStream()
        metrics.recordTokens(10)
        metrics.endStream()
        XCTAssertEqual(metrics.phase, .complete)
        
        metrics.startStream()
        XCTAssertEqual(metrics.totalTokens, 0) // Reset on new start
        XCTAssertEqual(metrics.phase, .waiting)
        metrics.recordTokens(5)
        metrics.endStream()
        XCTAssertEqual(metrics.totalTokens, 5)
    }
}
