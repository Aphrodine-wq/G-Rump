import Foundation
import OSLog

// MARK: - Confidence Calibration System
//
// The agent reports a calibrated confidence score on its responses and decisions.
// High confidence → agent proceeds autonomously.
// Low confidence → agent flags uncertainty and asks before proceeding.
//
// No AI coding tool has a calibrated confidence system that adapts behavior
// based on how sure the agent actually is. They either always proceed (and break
// things) or always ask (and annoy users).

// MARK: - Confidence Level

enum ConfidenceLevel: Comparable {
    case veryLow    // 0.0–0.25: Stop and ask the user
    case low        // 0.25–0.5: Proceed with warnings
    case moderate   // 0.5–0.75: Proceed normally
    case high       // 0.75–0.9: Proceed autonomously
    case veryHigh   // 0.9–1.0: Full autonomy

    var label: String {
        switch self {
        case .veryLow:  return "Very Low"
        case .low:      return "Low"
        case .moderate: return "Moderate"
        case .high:     return "High"
        case .veryHigh: return "Very High"
        }
    }

    var icon: String {
        switch self {
        case .veryLow:  return "exclamationmark.triangle.fill"
        case .low:      return "exclamationmark.triangle"
        case .moderate: return "gauge.with.dots.needle.50percent"
        case .high:     return "gauge.with.dots.needle.67percent"
        case .veryHigh: return "checkmark.shield.fill"
        }
    }

    var colorName: String {
        switch self {
        case .veryLow:  return "red"
        case .low:      return "orange"
        case .moderate: return "yellow"
        case .high:     return "green"
        case .veryHigh: return "blue"
        }
    }

    /// Whether this confidence level should trigger a user confirmation prompt.
    var shouldConfirmWithUser: Bool {
        self <= .low
    }

    init(score: Double) {
        switch score {
        case ..<0.25:   self = .veryLow
        case 0.25..<0.5: self = .low
        case 0.5..<0.75: self = .moderate
        case 0.75..<0.9: self = .high
        default:         self = .veryHigh
        }
    }
}

// MARK: - Confidence Signal

/// Individual signals that contribute to the overall confidence score.
struct ConfidenceSignal: Identifiable {
    let id = UUID()
    let source: Source
    let score: Double   // 0.0–1.0
    let weight: Double  // How much this signal matters (0.0–1.0)
    let reason: String

    enum Source: String {
        case toolSuccess        // Recent tool call success rate
        case patternMatch       // Task matches known successful patterns
        case testCoverage       // Area being modified has test coverage
        case lspDiagnostics     // LSP reports no errors in target files
        case memoryMatch        // Similar task succeeded in memory
        case fileStability      // Target file is stable (low volatility)
        case errorRecovery      // Recent error recovery success
        case taskComplexity     // Estimated complexity of the task
    }
}

// MARK: - Confidence Report

struct ConfidenceReport {
    let signals: [ConfidenceSignal]
    let overallScore: Double
    let level: ConfidenceLevel
    let timestamp: Date

    /// Human-readable summary of confidence assessment.
    var summary: String {
        let lowSignals = signals.filter { $0.score < 0.5 }.sorted { $0.score < $1.score }
        if lowSignals.isEmpty {
            return "High confidence — proceeding autonomously."
        }
        let concerns = lowSignals.prefix(2).map(\.reason).joined(separator: "; ")
        return "Confidence: \(level.label). Concerns: \(concerns)"
    }
}

// MARK: - Confidence Calibration

@MainActor
final class ConfidenceCalibration: ObservableObject {

    @Published private(set) var currentReport: ConfidenceReport?
    @Published private(set) var currentLevel: ConfidenceLevel = .moderate

    private let logger = GRumpLogger.general

    // Calibration history for self-improvement — persisted so the correction
    // survives restarts instead of resetting to uncalibrated every launch.
    private var calibrationHistory: [(predicted: ConfidenceLevel, actualSuccess: Bool)] = []
    private let maxHistorySize = 200
    private let historyFileURL: URL

    static var defaultHistoryFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".grump")
            .appendingPathComponent("confidence-calibration.json")
    }

    init(historyFileURL: URL = ConfidenceCalibration.defaultHistoryFileURL) {
        self.historyFileURL = historyFileURL
        loadHistory()
    }

    // MARK: - History persistence

    private struct CalibrationRecord: Codable {
        let predicted: Int      // index into levelOrder
        let success: Bool
    }

    private static let levelOrder: [ConfidenceLevel] = [.veryLow, .low, .moderate, .high, .veryHigh]

    private func loadHistory() {
        guard FileManager.default.fileExists(atPath: historyFileURL.path),
              let data = try? Data(contentsOf: historyFileURL),
              let records = try? JSONDecoder().decode([CalibrationRecord].self, from: data) else {
            return
        }
        calibrationHistory = records.compactMap { record in
            guard Self.levelOrder.indices.contains(record.predicted) else { return nil }
            return (predicted: Self.levelOrder[record.predicted], actualSuccess: record.success)
        }
    }

    private func saveHistory() {
        let records = calibrationHistory.compactMap { entry -> CalibrationRecord? in
            guard let index = Self.levelOrder.firstIndex(of: entry.predicted) else { return nil }
            return CalibrationRecord(predicted: index, success: entry.actualSuccess)
        }
        do {
            try FileManager.default.createDirectory(
                at: historyFileURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try JSONEncoder().encode(records).write(to: historyFileURL)
        } catch {
            logger.error("ConfidenceCalibration history save failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Assessment

    /// Assess confidence for the current agent state.
    /// Call before executing tool calls that modify files.
    func assess(
        recentToolResults: [(name: String, success: Bool)],
        lspDiagnostics: [String: [LSPDiagnostic]],
        targetFiles: [String],
        taskDescription: String,
        memoryHits: Int,
        loopDetectorPivots: Int
    ) -> ConfidenceReport {
        var signals: [ConfidenceSignal] = []

        // Signal 1: Recent tool success rate
        let recentWindow = recentToolResults.suffix(10)
        if !recentWindow.isEmpty {
            let successRate = Double(recentWindow.filter(\.success).count) / Double(recentWindow.count)
            signals.append(ConfidenceSignal(
                source: .toolSuccess,
                score: successRate,
                weight: 0.25,
                reason: successRate < 0.5
                    ? "\(Int((1 - successRate) * 100))% of recent tool calls failed"
                    : "Recent tool calls succeeding"
            ))
        }

        // Signal 2: LSP diagnostics on target files
        if !targetFiles.isEmpty {
            let diagnosticCount = targetFiles.reduce(0) { count, file in
                count + (lspDiagnostics[file]?.count ?? 0)
            }
            let diagScore = diagnosticCount == 0 ? 1.0 : max(0.1, 1.0 - Double(diagnosticCount) * 0.15)
            signals.append(ConfidenceSignal(
                source: .lspDiagnostics,
                score: diagScore,
                weight: 0.2,
                reason: diagnosticCount > 0
                    ? "\(diagnosticCount) LSP diagnostic(s) in target files"
                    : "No LSP diagnostics in target files"
            ))
        }

        // Signal 3: Memory match (similar task succeeded before)
        let memoryScore = min(1.0, Double(memoryHits) * 0.3 + 0.2)
        signals.append(ConfidenceSignal(
            source: .memoryMatch,
            score: memoryHits > 0 ? memoryScore : 0.3,
            weight: 0.15,
            reason: memoryHits > 0
                ? "\(memoryHits) similar task(s) found in project memory"
                : "No similar tasks in project memory"
        ))

        // Signal 4: Loop detector state
        if loopDetectorPivots > 0 {
            let loopScore = max(0.05, 1.0 - Double(loopDetectorPivots) * 0.35)
            signals.append(ConfidenceSignal(
                source: .errorRecovery,
                score: loopScore,
                weight: 0.25,
                reason: "Loop detector triggered \(loopDetectorPivots) pivot(s)"
            ))
        }

        // Signal 5: Task complexity estimate (based on keyword heuristics)
        let complexityScore = estimateTaskComplexity(taskDescription)
        signals.append(ConfidenceSignal(
            source: .taskComplexity,
            score: complexityScore,
            weight: 0.15,
            reason: complexityScore < 0.4
                ? "Task appears complex or ambiguous"
                : "Task appears well-defined"
        ))

        // Compute weighted average
        let totalWeight = signals.reduce(0.0) { $0 + $1.weight }
        let weightedSum = signals.reduce(0.0) { $0 + $1.score * $1.weight }
        let overallScore = totalWeight > 0 ? weightedSum / totalWeight : 0.5

        // Apply calibration correction based on historical accuracy
        let correctedScore = applyCalibrationCorrection(overallScore)

        let report = ConfidenceReport(
            signals: signals,
            overallScore: correctedScore,
            level: ConfidenceLevel(score: correctedScore),
            timestamp: Date()
        )

        currentReport = report
        currentLevel = report.level
        return report
    }

    /// Record whether the confidence prediction was correct.
    /// Call after a task completes (or fails) to improve calibration.
    func recordOutcome(predictedLevel: ConfidenceLevel, actualSuccess: Bool) {
        calibrationHistory.append((predicted: predictedLevel, actualSuccess: actualSuccess))
        if calibrationHistory.count > maxHistorySize {
            calibrationHistory.removeFirst(calibrationHistory.count - maxHistorySize)
        }
        saveHistory()
    }

    /// System prompt fragment injected when confidence is low.
    func lowConfidencePromptFragment() -> String? {
        guard let report = currentReport, report.level.shouldConfirmWithUser else { return nil }
        return """
        CONFIDENCE ALERT: Your confidence for this task is \(report.level.label.lowercased()) \
        (score: \(String(format: "%.0f%%", report.overallScore * 100))). \
        \(report.summary) \
        Before making changes, explain your reasoning and ask the user to confirm your approach. \
        Do not proceed with file modifications until the user approves.
        """
    }

    /// Reset for a new conversation.
    func reset() {
        currentReport = nil
        currentLevel = .moderate
    }

    // MARK: - Private

    /// Estimate task complexity from description keywords.
    private func estimateTaskComplexity(_ description: String) -> Double {
        let lower = description.lowercased()

        // Complexity indicators (lower score = more complex)
        let complexIndicators = [
            "refactor", "migrate", "rewrite", "redesign", "architecture",
            "concurrent", "thread", "async", "race condition", "deadlock",
            "security", "authentication", "encryption", "oauth",
            "complex", "complicated", "tricky", "subtle", "edge case"
        ]

        let simpleIndicators = [
            "add", "create", "simple", "basic", "update", "change",
            "rename", "move", "delete", "remove", "fix typo",
            "comment", "log", "print"
        ]

        let complexHits = complexIndicators.filter { lower.contains($0) }.count
        let simpleHits = simpleIndicators.filter { lower.contains($0) }.count

        if complexHits > simpleHits {
            return max(0.1, 0.7 - Double(complexHits) * 0.1)
        } else if simpleHits > 0 {
            return min(0.95, 0.6 + Double(simpleHits) * 0.1)
        }
        return 0.5 // Neutral
    }

    /// Apply calibration correction based on historical prediction accuracy.
    private func applyCalibrationCorrection(_ rawScore: Double) -> Double {
        guard calibrationHistory.count >= 10 else { return rawScore }

        // Check if we're systematically over- or under-confident
        let recentHistory = calibrationHistory.suffix(50)
        let overconfidentCount = recentHistory.filter { $0.predicted >= .high && !$0.actualSuccess }.count
        let underconfidentCount = recentHistory.filter { $0.predicted <= .low && $0.actualSuccess }.count

        let overconfidentRate = Double(overconfidentCount) / Double(recentHistory.count)
        let underconfidentRate = Double(underconfidentCount) / Double(recentHistory.count)

        // Adjust: if we're often overconfident, lower scores; if underconfident, raise them
        let correction = (underconfidentRate - overconfidentRate) * 0.1
        return max(0.0, min(1.0, rawScore + correction))
    }
}
