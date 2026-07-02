// ╔══════════════════════════════════════════════════════════════╗
// ║  SwarmConsensus.swift                                       ║
// ║  Multi-Agent Swarm — consensus building algorithms          ║
// ╚══════════════════════════════════════════════════════════════╝

import Foundation

// MARK: - Consensus Result

/// The outcome of a consensus-building process.
struct ConsensusResult: Sendable {
    let agreed: Bool
    let winningResult: String
    let confidence: Double
    let dissent: [String]
    let rounds: Int
    let strategy: ConsensusStrategy

    /// Human-readable summary of the consensus outcome.
    var summary: String {
        if agreed {
            return "Consensus reached (confidence: \(String(format: "%.1f%%", confidence * 100))) using \(strategy.rawValue)"
        } else {
            return "No consensus (\(dissent.count) dissenting views). Best result selected by confidence."
        }
    }
}

// MARK: - Consensus Strategy

/// The algorithm used to build consensus from multiple agent results.
enum ConsensusStrategy: String, Sendable {
    case majorityVote
    case weightedVote
    case rankedChoice
    case synthesize
}

// MARK: - Result Cluster

/// A group of similar agent results.
private struct ResultCluster {
    var results: [AgentResult]
    var centroid: String

    var totalConfidence: Double {
        results.map(\.confidence).reduce(0, +)
    }

    var averageConfidence: Double {
        guard !results.isEmpty else { return 0 }
        return totalConfidence / Double(results.count)
    }

    var bestResult: AgentResult? {
        results.max(by: { $0.confidence < $1.confidence })
    }
}

// MARK: - Swarm Consensus

/// Implements multiple consensus-building strategies for aggregating
/// results from multiple micro-agents.
struct SwarmConsensus: Sendable {

    // MARK: - Public API

    /// Build consensus from agent results using the specified strategy.
    func buildConsensus(
        _ results: [AgentResult],
        strategy: ConsensusStrategy,
        threshold: Double
    ) -> ConsensusResult {
        guard !results.isEmpty else {
            return ConsensusResult(
                agreed: false,
                winningResult: "",
                confidence: 0,
                dissent: [],
                rounds: 0,
                strategy: strategy
            )
        }

        // Single result: trivial consensus
        if results.count == 1 {
            return ConsensusResult(
                agreed: true,
                winningResult: results[0].result,
                confidence: results[0].confidence,
                dissent: [],
                rounds: 1,
                strategy: strategy
            )
        }

        switch strategy {
        case .majorityVote:
            return majorityVote(results, threshold: threshold)
        case .weightedVote:
            return weightedVote(results, threshold: threshold)
        case .rankedChoice:
            return rankedChoice(results, threshold: threshold)
        case .synthesize:
            return synthesize(results, threshold: threshold)
        }
    }

    // MARK: - Majority Vote

    /// Simple majority: cluster results by similarity, largest cluster wins.
    func majorityVote(_ results: [AgentResult], threshold: Double) -> ConsensusResult {
        let clusters = clusterResults(results)

        guard let largestCluster = clusters.max(by: { $0.results.count < $1.results.count }) else {
            return noConsensus(results, strategy: .majorityVote)
        }

        let majorityRatio = Double(largestCluster.results.count) / Double(results.count)
        let agreed = majorityRatio >= threshold
        let best = selectBestFromCluster(largestCluster)

        // Dissent: results not in the winning cluster
        let winnerIds = Set(largestCluster.results.map(\.id))
        let dissent = results
            .filter { !winnerIds.contains($0.id) }
            .map { "\($0.role.displayName): \(String($0.result.prefix(200)))" }

        return ConsensusResult(
            agreed: agreed,
            winningResult: best.result,
            confidence: majorityRatio * best.confidence,
            dissent: dissent,
            rounds: 1,
            strategy: .majorityVote
        )
    }

    // MARK: - Weighted Vote

    /// Each agent's vote is weighted by their confidence score.
    func weightedVote(_ results: [AgentResult], threshold: Double) -> ConsensusResult {
        let clusters = clusterResults(results)

        // Weight each cluster by sum of member confidences
        var clusterWeights: [(cluster: ResultCluster, weight: Double)] = []
        let totalWeight = results.map(\.confidence).reduce(0, +)

        for cluster in clusters {
            let weight = cluster.totalConfidence / max(totalWeight, 0.001)
            clusterWeights.append((cluster, weight))
        }

        clusterWeights.sort { $0.weight > $1.weight }

        guard let topCluster = clusterWeights.first else {
            return noConsensus(results, strategy: .weightedVote)
        }

        let agreed = topCluster.weight >= threshold
        let best = selectBestFromCluster(topCluster.cluster)

        let winnerIds = Set(topCluster.cluster.results.map(\.id))
        let dissent = results
            .filter { !winnerIds.contains($0.id) }
            .map { "\($0.role.displayName) (conf: \(String(format: "%.2f", $0.confidence))): \(String($0.result.prefix(200)))" }

        return ConsensusResult(
            agreed: agreed,
            winningResult: best.result,
            confidence: topCluster.weight,
            dissent: dissent,
            rounds: 1,
            strategy: .weightedVote
        )
    }

    // MARK: - Ranked Choice

    /// Agents implicitly rank results by similarity. Aggregate rankings via Borda count.
    func rankedChoice(_ results: [AgentResult], threshold: Double) -> ConsensusResult {
        guard results.count >= 2 else {
            return majorityVote(results, threshold: threshold)
        }

        // For each result, compute a "Borda score" based on how similar it is
        // to all other results. Higher average similarity = higher rank.
        var scores: [(index: Int, score: Double)] = []

        for i in results.indices {
            var totalSimilarity: Double = 0
            for j in results.indices where i != j {
                totalSimilarity += calculateSimilarity(results[i].result, results[j].result)
            }
            // Weighted by the result's own confidence
            let avgSimilarity = totalSimilarity / Double(results.count - 1)
            let bordaScore = avgSimilarity * 0.6 + results[i].confidence * 0.4
            scores.append((i, bordaScore))
        }

        scores.sort { $0.score > $1.score }

        guard let topIdx = scores.first?.index else {
            return noConsensus(results, strategy: .rankedChoice)
        }

        let topScore = scores[0].score
        let secondScore = scores.count > 1 ? scores[1].score : 0
        let margin = topScore - secondScore
        let agreed = topScore >= threshold

        let winner = results[topIdx]
        let dissent = results.enumerated()
            .filter { $0.offset != topIdx }
            .map { "\($0.element.role.displayName): \(String($0.element.result.prefix(200)))" }

        return ConsensusResult(
            agreed: agreed,
            winningResult: winner.result,
            confidence: topScore,
            dissent: dissent,
            rounds: 1,
            strategy: .rankedChoice
        )
    }

    // MARK: - Synthesis

    /// Merge complementary results into a unified answer (for ensemble strategy).
    func synthesize(_ results: [AgentResult], threshold: Double) -> ConsensusResult {
        let clusters = clusterResults(results)

        if clusters.count == 1 {
            // All results are similar; pick the best one
            let best = selectBestFromCluster(clusters[0])
            return ConsensusResult(
                agreed: true,
                winningResult: best.result,
                confidence: clusters[0].averageConfidence,
                dissent: [],
                rounds: 1,
                strategy: .synthesize
            )
        }

        // Multiple clusters: try to merge them
        // Sort clusters by size (largest first) then by confidence
        let sortedClusters = clusters.sorted { a, b in
            if a.results.count != b.results.count {
                return a.results.count > b.results.count
            }
            return a.averageConfidence > b.averageConfidence
        }

        // Take the best result from each cluster and merge
        var mergedParts: [String] = []
        var totalConfidence: Double = 0
        var partCount = 0

        for cluster in sortedClusters {
            if let best = cluster.bestResult {
                mergedParts.append(best.result)
                totalConfidence += best.confidence
                partCount += 1
            }
        }

        let merged: String
        if mergedParts.count == 1 {
            merged = mergedParts[0]
        } else {
            merged = mergedParts.enumerated().map { i, part in
                "--- Part \(i + 1) ---\n\(part)"
            }.joined(separator: "\n\n")
        }

        let avgConfidence = partCount > 0 ? totalConfidence / Double(partCount) : 0
        let agreed = avgConfidence >= threshold && clusters.count <= 2

        return ConsensusResult(
            agreed: agreed,
            winningResult: merged,
            confidence: avgConfidence,
            dissent: [],
            rounds: 1,
            strategy: .synthesize
        )
    }

    // MARK: - Similarity

    /// Calculate Jaccard similarity between two strings based on token sets.
    func calculateSimilarity(_ a: String, _ b: String) -> Double {
        let tokensA = tokenize(a)
        let tokensB = tokenize(b)

        guard !tokensA.isEmpty || !tokensB.isEmpty else { return 1.0 }

        let intersection = tokensA.intersection(tokensB)
        let union = tokensA.union(tokensB)

        guard !union.isEmpty else { return 1.0 }

        return Double(intersection.count) / Double(union.count)
    }

    /// Tokenize a string into a set of normalized words.
    private func tokenize(_ text: String) -> Set<String> {
        let words = text.lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .filter { $0.count > 2 } // Skip very short tokens
        return Set(words)
    }

    // MARK: - Clustering

    /// Group similar results into clusters using single-linkage clustering.
    func clusterResults(_ results: [AgentResult]) -> [ResultCluster] {
        guard !results.isEmpty else { return [] }

        let similarityThreshold = 0.3 // Minimum Jaccard similarity to be in same cluster
        var clusters: [ResultCluster] = []
        var assigned = Set<UUID>()

        // Sort by confidence descending so higher-confidence results seed clusters
        let sorted = results.sorted { $0.confidence > $1.confidence }

        for result in sorted {
            if assigned.contains(result.id) { continue }

            // Try to find an existing cluster this result fits into
            var foundCluster = false
            for i in clusters.indices {
                let similarity = calculateSimilarity(result.result, clusters[i].centroid)
                if similarity >= similarityThreshold {
                    clusters[i].results.append(result)
                    // Update centroid to include new result's most common tokens
                    foundCluster = true
                    assigned.insert(result.id)
                    break
                }
            }

            if !foundCluster {
                // Start a new cluster
                clusters.append(ResultCluster(
                    results: [result],
                    centroid: result.result
                ))
                assigned.insert(result.id)
            }
        }

        return clusters
    }

    /// Select the highest-confidence result from a cluster.
    func selectBestFromCluster(_ cluster: ResultCluster) -> AgentResult {
        cluster.results.max(by: { $0.confidence < $1.confidence }) ?? cluster.results[0]
    }

    // MARK: - Helpers

    /// Create a "no consensus" result.
    private func noConsensus(_ results: [AgentResult], strategy: ConsensusStrategy) -> ConsensusResult {
        // Fall back to highest-confidence result
        let best = results.max(by: { $0.confidence < $1.confidence })
        return ConsensusResult(
            agreed: false,
            winningResult: best?.result ?? "",
            confidence: best?.confidence ?? 0,
            dissent: results.map { "\($0.role.displayName): \(String($0.result.prefix(200)))" },
            rounds: 1,
            strategy: strategy
        )
    }
}

// MARK: - Consensus Utilities

extension SwarmConsensus {

    /// Evaluate how "aligned" a set of results are (0.0 = total disagreement, 1.0 = perfect agreement).
    func alignmentScore(_ results: [AgentResult]) -> Double {
        guard results.count >= 2 else { return 1.0 }

        var totalSimilarity: Double = 0
        var pairCount = 0

        for i in results.indices {
            for j in (i + 1)..<results.count {
                totalSimilarity += calculateSimilarity(results[i].result, results[j].result)
                pairCount += 1
            }
        }

        return pairCount > 0 ? totalSimilarity / Double(pairCount) : 0
    }

    /// Identify the most controversial result (least similar to others).
    func findOutlier(_ results: [AgentResult]) -> AgentResult? {
        guard results.count >= 3 else { return nil }

        var minAvgSimilarity: Double = 1.0
        var outlierIdx = 0

        for i in results.indices {
            var totalSim: Double = 0
            for j in results.indices where i != j {
                totalSim += calculateSimilarity(results[i].result, results[j].result)
            }
            let avgSim = totalSim / Double(results.count - 1)
            if avgSim < minAvgSimilarity {
                minAvgSimilarity = avgSim
                outlierIdx = i
            }
        }

        return minAvgSimilarity < 0.3 ? results[outlierIdx] : nil
    }

    /// Compute a confidence-weighted diversity score.
    /// High diversity + high confidence = interesting disagreement worth examining.
    func diversityScore(_ results: [AgentResult]) -> Double {
        let alignment = alignmentScore(results)
        let avgConfidence = results.isEmpty ? 0 : results.map(\.confidence).reduce(0, +) / Double(results.count)
        return (1.0 - alignment) * avgConfidence
    }
}
