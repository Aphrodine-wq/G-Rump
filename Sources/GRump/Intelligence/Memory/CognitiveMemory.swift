import Foundation

// MARK: - Cognitive Memory
//
// The Track-1 (MemoryAgent) differentiator: G-Rump's memory does not just store
// and vector-search — it RANKS by relevance × recency × salience, RECALLS within
// a fixed token budget (the "limited context window" requirement), and FORGETS
// on purpose (decay, near-duplicate merge, prune) instead of growing forever.
//
// Everything here is pure and deterministic over `MemoryRecord` values, so it is
// unit-testable offline with no embedding model, network, or filesystem. The
// stores map their entries to MemoryRecord to use it.

/// A single memory, decoupled from storage and embedding details.
struct MemoryRecord {
    let id: UUID
    let conversationId: String
    let timestamp: Date          // when the memory was formed
    let text: String
    let vector: [Float]          // semantic embedding (any backend)
    var strength: Double         // 0…1 importance/consolidation weight
    var lastAccess: Date         // last time this memory was recalled
    var accessCount: Int

    var estimatedTokens: Int { max(1, text.count / 4) }
}

/// A memory paired with the score that earned its place in the recall set.
struct ScoredMemory {
    let record: MemoryRecord
    let relevance: Double         // cosine(query, record) mapped to 0…1
    let recency: Double           // time-decay factor 0…1
    let score: Double             // blended ranking score
}

/// Result of a consolidation ("sleep") pass — what was kept and what changed.
struct ConsolidationResult {
    var kept: [MemoryRecord]
    var merged: Int               // near-duplicate memories folded together
    var forgotten: Int            // memories pruned as stale/weak
    var decayedBelowFloor: Int    // memories whose strength fell under the floor
}

enum CognitiveMemory {

    // Tunables (sensible defaults; the daemon/consolidation can override).
    static let recencyHalfLifeDays: Double = 14
    static let duplicateThreshold: Float = 0.92
    static let forgetStrengthFloor: Double = 0.08
    static let defaultTokenBudget: Int = 1500

    // Blend weights for the ranking score. Relevance leads, recency and salience
    // break ties so a slightly-less-similar but fresh, important memory can win.
    static let wRelevance = 0.6
    static let wRecency = 0.25
    static let wSalience = 0.15

    // MARK: - Similarity

    static func cosine(_ a: [Float], _ b: [Float]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        for i in 0..<a.count { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i] }
        let denom = (na.squareRoot()) * (nb.squareRoot())
        return denom > 0 ? Double(dot / denom) : 0
    }

    // MARK: - Scoring

    /// Exponential recency decay in [0,1]; 1.0 at age 0, 0.5 at one half-life.
    static func recencyFactor(age seconds: Double, halfLifeDays: Double = recencyHalfLifeDays) -> Double {
        let ageDays = max(0, seconds) / 86_400
        return pow(0.5, ageDays / max(0.0001, halfLifeDays))
    }

    /// Blend relevance, recency, and salience into one ranking score.
    static func score(_ record: MemoryRecord, queryVector: [Float], now: Date,
                      halfLifeDays: Double = recencyHalfLifeDays) -> ScoredMemory {
        let rel = max(0, cosine(queryVector, record.vector))                  // 0…1
        let rec = recencyFactor(age: now.timeIntervalSince(record.lastAccess), halfLifeDays: halfLifeDays)
        let sal = min(1, max(0, record.strength))
        let s = wRelevance * rel + wRecency * rec + wSalience * sal
        return ScoredMemory(record: record, relevance: rel, recency: rec, score: s)
    }

    // MARK: - Budget-aware recall ("limited context window")

    /// Rank all records and greedily pack the best into `tokenBudget`, so the
    /// most valuable memories are recalled within a fixed context window.
    static func budgetedRecall(_ records: [MemoryRecord], queryVector: [Float], now: Date,
                               tokenBudget: Int = defaultTokenBudget,
                               halfLifeDays: Double = recencyHalfLifeDays) -> [ScoredMemory] {
        let ranked = records
            .map { score($0, queryVector: queryVector, now: now, halfLifeDays: halfLifeDays) }
            .sorted { $0.score > $1.score }
        var out: [ScoredMemory] = []
        var used = 0
        for sm in ranked {
            let t = sm.record.estimatedTokens
            if used + t > tokenBudget { continue }   // skip; a later, smaller one may still fit
            out.append(sm)
            used += t
        }
        return out
    }

    // MARK: - Forgetting / consolidation ("timely forgetting")

    /// A "sleep" pass: decay strengths toward 0 by age, merge near-duplicates
    /// (keeping the stronger, refreshing its strength), then prune anything that
    /// fell under the strength floor or overflows `maxEntries` (weakest first).
    static func consolidate(_ records: [MemoryRecord], now: Date,
                            halfLifeDays: Double = recencyHalfLifeDays,
                            duplicateThreshold: Float = duplicateThreshold,
                            strengthFloor: Double = forgetStrengthFloor,
                            maxEntries: Int = 500) -> ConsolidationResult {
        // 1) Decay strength by time since last access.
        var decayed: [MemoryRecord] = records.map { r in
            var m = r
            let factor = recencyFactor(age: now.timeIntervalSince(r.lastAccess), halfLifeDays: halfLifeDays)
            m.strength = r.strength * factor
            return m
        }
        let belowFloor = decayed.filter { $0.strength < strengthFloor }.count

        // 2) Merge near-duplicates: keep the stronger record, drop the weaker,
        //    and bump the survivor's strength (reinforcement).
        var merged = 0
        var survivors: [MemoryRecord] = []
        // Strongest first so the survivor is the more important memory.
        for cand in decayed.sorted(by: { $0.strength > $1.strength }) {
            if let idx = survivors.firstIndex(where: { cosine($0.vector, cand.vector) >= Double(duplicateThreshold) }) {
                survivors[idx].strength = min(1, survivors[idx].strength + 0.1)
                survivors[idx].accessCount += cand.accessCount
                merged += 1
            } else {
                survivors.append(cand)
            }
        }

        // 3) Forget: prune below-floor memories, then cap to maxEntries (weakest first).
        var kept = survivors.filter { $0.strength >= strengthFloor }
        if kept.count > maxEntries {
            kept = Array(kept.sorted(by: { $0.strength > $1.strength }).prefix(maxEntries))
        }
        let forgotten = decayed.count - kept.count - merged

        return ConsolidationResult(kept: kept, merged: merged,
                                   forgotten: max(0, forgotten),
                                   decayedBelowFloor: belowFloor)
    }

    // MARK: - Rendering

    /// Format a recall set as a system-prompt block.
    static func promptBlock(_ recalled: [ScoredMemory]) -> String? {
        guard !recalled.isEmpty else { return nil }
        let fmt = ISO8601DateFormatter()
        var block = "\n\n## Relevant Memory (recalled within budget)\n"
        for sm in recalled {
            block += "\n---\n[\(fmt.string(from: sm.record.timestamp))] (relevance \(String(format: "%.2f", sm.relevance)))\n\(sm.record.text)"
        }
        return block
    }
}
