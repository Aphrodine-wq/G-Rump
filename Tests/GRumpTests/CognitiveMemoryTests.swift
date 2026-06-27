import XCTest
@testable import GRump

final class CognitiveMemoryTests: XCTestCase {

    private func rec(_ id: UUID = UUID(), text: String, vector: [Float], strength: Double = 1.0,
                     ageDays: Double = 0, accessCount: Int = 0) -> MemoryRecord {
        let now = Date()
        let when = now.addingTimeInterval(-ageDays * 86_400)
        return MemoryRecord(id: id, conversationId: "c", timestamp: when, text: text,
                            vector: vector, strength: strength, lastAccess: when, accessCount: accessCount)
    }

    func testCosine() {
        XCTAssertEqual(CognitiveMemory.cosine([1, 0], [1, 0]), 1.0, accuracy: 1e-6)
        XCTAssertEqual(CognitiveMemory.cosine([1, 0], [0, 1]), 0.0, accuracy: 1e-6)
        XCTAssertEqual(CognitiveMemory.cosine([], [1]), 0.0)
    }

    func testRecencyDecayHalfLife() {
        XCTAssertEqual(CognitiveMemory.recencyFactor(age: 0, halfLifeDays: 14), 1.0, accuracy: 1e-9)
        // One half-life => 0.5
        XCTAssertEqual(CognitiveMemory.recencyFactor(age: 14 * 86_400, halfLifeDays: 14), 0.5, accuracy: 1e-6)
        // Two half-lives => 0.25
        XCTAssertEqual(CognitiveMemory.recencyFactor(age: 28 * 86_400, halfLifeDays: 14), 0.25, accuracy: 1e-6)
    }

    func testBudgetedRecallRespectsTokenBudget() {
        let q: [Float] = [1, 0, 0]
        // Each ~100 chars => ~25 tokens. Budget 60 tokens => at most 2 fit.
        let long = String(repeating: "x", count: 100)
        let records = (0..<5).map { rec(text: long + "\($0)", vector: [1, 0, 0]) }
        let recalled = CognitiveMemory.budgetedRecall(records, queryVector: q, now: Date(), tokenBudget: 60)
        let usedTokens = recalled.reduce(0) { $0 + $1.record.estimatedTokens }
        XCTAssertLessThanOrEqual(usedTokens, 60)
        XCTAssertGreaterThan(recalled.count, 0)
        XCTAssertLessThan(recalled.count, 5)
    }

    func testBudgetedRecallRanksRelevantAndRecentFirst() {
        let q: [Float] = [1, 0, 0]
        let relevantRecent = rec(text: "match-fresh", vector: [1, 0, 0], ageDays: 0)
        let relevantOld = rec(text: "match-stale", vector: [0.9, 0.1, 0], strength: 1.0, ageDays: 60)
        let irrelevant = rec(text: "noise", vector: [0, 1, 0], ageDays: 0)
        let recalled = CognitiveMemory.budgetedRecall([irrelevant, relevantOld, relevantRecent],
                                                      queryVector: q, now: Date(), tokenBudget: 10_000)
        XCTAssertEqual(recalled.first?.record.text, "match-fresh")
        XCTAssertEqual(recalled.last?.record.text, "noise")
    }

    func testConsolidateMergesNearDuplicates() {
        let dupA = rec(text: "the build is failing on CI", vector: [1, 0, 0], strength: 0.9)
        let dupB = rec(text: "CI build failing again", vector: [0.99, 0.01, 0], strength: 0.6)
        let distinct = rec(text: "user prefers tabs", vector: [0, 1, 0], strength: 0.9)
        let result = CognitiveMemory.consolidate([dupA, dupB, distinct], now: Date())
        XCTAssertEqual(result.merged, 1)
        XCTAssertEqual(result.kept.count, 2)            // the two near-dups collapse to one
        // The survivor of the merge is reinforced.
        XCTAssertTrue(result.kept.contains { $0.strength > 0.9 })
    }

    func testConsolidateForgetsStaleWeakMemories() {
        let fresh = rec(text: "keep me", vector: [1, 0, 0], strength: 1.0, ageDays: 0)
        // Old + low strength => decays under the floor and is forgotten.
        let stale = rec(text: "forget me", vector: [0, 1, 0], strength: 0.2, ageDays: 120)
        let result = CognitiveMemory.consolidate([fresh, stale], now: Date())
        XCTAssertTrue(result.kept.contains { $0.text == "keep me" })
        XCTAssertFalse(result.kept.contains { $0.text == "forget me" })
        XCTAssertGreaterThanOrEqual(result.forgotten, 1)
    }
}
