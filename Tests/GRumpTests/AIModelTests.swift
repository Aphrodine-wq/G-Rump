import XCTest
@testable import GRump

final class AIModelTests: XCTestCase {

    // MARK: - Model Enum Completeness

    func testAllModelsHaveDisplayNames() {
        for model in AIModel.allCases {
            XCTAssertFalse(model.displayName.isEmpty, "\(model.rawValue) missing displayName")
        }
    }

    func testAllModelsHaveDescriptions() {
        for model in AIModel.allCases {
            XCTAssertFalse(model.description.isEmpty, "\(model.rawValue) missing description")
        }
    }

    func testAllModelsHaveContextWindows() {
        for model in AIModel.allCases {
            XCTAssertGreaterThan(model.contextWindow, 0, "\(model.rawValue) has invalid contextWindow")
        }
    }

    func testAllModelsHaveMaxOutput() {
        for model in AIModel.allCases {
            XCTAssertGreaterThan(model.maxOutput, 0, "\(model.rawValue) has invalid maxOutput")
        }
    }

    func testMaxOutputNeverExceedsContextWindow() {
        for model in AIModel.allCases {
            XCTAssertLessThanOrEqual(model.maxOutput, model.contextWindow,
                "\(model.rawValue) maxOutput exceeds contextWindow")
        }
    }

    func testAllModelsHaveTier() {
        // Single provider now — every model reports the "Qwen" tier.
        let validTiers = Set(["Qwen"])
        for model in AIModel.allCases {
            XCTAssertTrue(validTiers.contains(model.tier),
                "\(model.rawValue) has unexpected tier: \(model.tier)")
        }
    }

    func testModelIdMatchesRawValue() {
        for model in AIModel.allCases {
            XCTAssertEqual(model.id, model.rawValue)
        }
    }

    // MARK: - Tier Filtering

    func testModelsForFreeTier() {
        let freeModels = AIModel.modelsForTier(nil)
        XCTAssertFalse(freeModels.isEmpty)
        for model in freeModels {
            XCTAssertFalse(model.requiresPaidTier,
                "\(model.rawValue) requires paid tier but is in free list")
        }
    }

    func testModelsForFreeTierExplicit() {
        let models = AIModel.modelsForTier("free")
        XCTAssertFalse(models.isEmpty)
        for model in models {
            XCTAssertFalse(model.requiresPaidTier)
        }
    }

    func testModelsForProTier() {
        // Billing removed — every tier returns all Qwen models.
        let proModels = AIModel.modelsForTier("pro")
        XCTAssertEqual(Set(proModels), Set(AIModel.allCases))
    }

    func testModelsForTeamTier() {
        let teamModels = AIModel.modelsForTier("team")
        XCTAssertEqual(Set(teamModels), Set(AIModel.allCases))
    }

    func testProAndTeamTiersReturnSameModels() {
        let pro = AIModel.modelsForTier("pro")
        let team = AIModel.modelsForTier("team")
        XCTAssertEqual(pro.count, team.count)
        XCTAssertEqual(Set(pro.map(\.rawValue)), Set(team.map(\.rawValue)))
    }

    // MARK: - Default Model

    func testDefaultForFreeTier() {
        let model = AIModel.defaultForTier(nil)
        XCTAssertFalse(model.requiresPaidTier)
    }

    func testDefaultForProTier() {
        let model = AIModel.defaultForTier("pro")
        // Just verify it returns something valid
        XCTAssertFalse(model.displayName.isEmpty)
    }

    func testDefaultIsAlwaysInModelsForTier() {
        let tiers: [String?] = [nil, "free", "pro", "team"]
        for tier in tiers {
            let defaultModel = AIModel.defaultForTier(tier)
            let available = AIModel.modelsForTier(tier)
            XCTAssertTrue(available.contains(defaultModel),
                "Default model for tier \(tier ?? "nil") is not in available models")
        }
    }

    // MARK: - Paid Tier Classification

    func testNoModelRequiresPaidTier() {
        // Billing tiers were removed in the Qwen build — nothing is paid-gated.
        let paidModels = AIModel.allCases.filter { $0.requiresPaidTier }
        XCTAssertTrue(paidModels.isEmpty, "No model should require a paid tier")
    }

    func testFreeModelsDoNotRequirePaidTier() {
        let freeModels = AIModel.allCases.filter { $0.tier == "Free" }
        for model in freeModels {
            XCTAssertFalse(model.requiresPaidTier, "\(model.rawValue) is Free tier but requiresPaidTier")
        }
    }

    // MARK: - Model Count Regression

    func testModelCount() {
        // Qwen-only build ships exactly 4 models.
        XCTAssertEqual(AIModel.allCases.count, 4, "Expected the 4 Qwen models")
    }

    func testUniqueRawValues() {
        let rawValues = AIModel.allCases.map(\.rawValue)
        let uniqueValues = Set(rawValues)
        XCTAssertEqual(rawValues.count, uniqueValues.count, "Duplicate model raw values found")
    }

    func testUniqueDisplayNames() {
        let names = AIModel.allCases.map(\.displayName)
        let uniqueNames = Set(names)
        XCTAssertEqual(names.count, uniqueNames.count, "Duplicate display names found")
    }
}
