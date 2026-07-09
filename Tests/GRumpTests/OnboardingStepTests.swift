import XCTest
@testable import GRump

final class OnboardingStepTests: XCTestCase {

    // MARK: - Step order

    func testStepOrder() {
        XCTAssertEqual(
            OnboardingStep.allCases,
            [.welcome, .provider, .model, .skills, .appearance, .security]
        )
    }

    func testNextAndPreviousChain() {
        XCTAssertNil(OnboardingStep.welcome.previous)
        XCTAssertEqual(OnboardingStep.welcome.next, .provider)
        XCTAssertEqual(OnboardingStep.provider.next, .model)
        XCTAssertEqual(OnboardingStep.model.next, .skills)
        XCTAssertEqual(OnboardingStep.skills.next, .appearance)
        XCTAssertEqual(OnboardingStep.appearance.next, .security)
        XCTAssertNil(OnboardingStep.security.next)
        XCTAssertEqual(OnboardingStep.security.previous, .appearance)
    }

    func testIsLast() {
        XCTAssertTrue(OnboardingStep.security.isLast)
        for step in OnboardingStep.allCases.dropLast() {
            XCTAssertFalse(step.isLast, "\(step) must not be last")
        }
    }

    // MARK: - Gating

    func testWelcomeRequiresConsent() {
        XCTAssertFalse(OnboardingStep.canAdvance(
            from: .welcome, consentGiven: false, hasSavedKey: true, keyEntryDeferred: true))
        XCTAssertTrue(OnboardingStep.canAdvance(
            from: .welcome, consentGiven: true, hasSavedKey: false, keyEntryDeferred: false))
    }

    func testProviderRequiresSavedKeyOrDeferral() {
        XCTAssertFalse(OnboardingStep.canAdvance(
            from: .provider, consentGiven: true, hasSavedKey: false, keyEntryDeferred: false))
        XCTAssertTrue(OnboardingStep.canAdvance(
            from: .provider, consentGiven: true, hasSavedKey: true, keyEntryDeferred: false))
        XCTAssertTrue(OnboardingStep.canAdvance(
            from: .provider, consentGiven: true, hasSavedKey: false, keyEntryDeferred: true))
    }

    func testLaterStepsAlwaysAdvance() {
        for step in [OnboardingStep.model, .skills, .appearance, .security] {
            XCTAssertTrue(OnboardingStep.canAdvance(
                from: step, consentGiven: false, hasSavedKey: false, keyEntryDeferred: false),
                "\(step) must always be passable")
        }
    }

    // MARK: - Featured packs

    func testFeaturedPackIdsExistInBuiltInPacks() {
        let builtInIds = Set(SkillPack.builtInPacks.map(\.id))
        for id in OnboardingView.featuredPackIds {
            XCTAssertTrue(builtInIds.contains(id), "featured pack '\(id)' is not a built-in pack")
        }
    }

    func testFeaturedPacksLeadWithIOSDevAndIncludeCodeQuality() {
        XCTAssertEqual(OnboardingView.featuredPackIds.first, "ios-dev")
        XCTAssertTrue(OnboardingView.featuredPackIds.contains("code-quality"))
        XCTAssertEqual(OnboardingView.featuredPackIds.count, 8)
    }
}
