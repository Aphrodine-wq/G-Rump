import XCTest
@testable import GRump

final class EyesTests: XCTestCase {

    // MARK: - PerceptualHash

    func testHashDistance() {
        XCTAssertEqual(PerceptualHash.distance(0xFFFF_FFFF_FFFF_FFFF, 0xFFFF_FFFF_FFFF_FFFF), 0)
        XCTAssertEqual(PerceptualHash.distance(0x0000_0000_0000_00FF, 0x0000_0000_0000_0000), 8)
        XCTAssertEqual(PerceptualHash.distance(0xFFFF_FFFF_FFFF_FFFF, 0x0000_0000_0000_0000), 64)
    }

    // MARK: - Privacy filter

    func testRedaction() {
        let f = EyesPrivacyFilter()
        XCTAssertTrue(f.redact("token sk-abc123def456ghi789jkl").contains("[REDACTED_KEY]"))
        XCTAssertTrue(f.redact("email me at jim@example.com").contains("[REDACTED_EMAIL]"))
        XCTAssertTrue(f.redact("card 4111 1111 1111 1111 please").contains("[REDACTED_CARD]"))
        XCTAssertTrue(f.redact("ghp_0123456789abcdefghijABCDEFGHIJ").contains("[REDACTED_GH_TOKEN]"))
        XCTAssertFalse(f.redact("just normal prose here").contains("REDACTED"))
    }

    func testSensitiveAppIgnored() {
        let f = EyesPrivacyFilter(extraIgnoredBundleIDs: ["com.acme.secretvault"])
        XCTAssertTrue(f.shouldIgnore(bundleId: "com.1password.1password7", appName: "1Password 7"))
        XCTAssertTrue(f.shouldIgnore(bundleId: "com.apple.keychainaccess", appName: "Keychain Access"))
        XCTAssertTrue(f.shouldIgnore(bundleId: "com.acme.secretvault", appName: "Vault"))
        XCTAssertTrue(f.shouldIgnore(bundleId: "com.unknown.app", appName: "My Banking App"))
        XCTAssertFalse(f.shouldIgnore(bundleId: "com.apple.Safari", appName: "Safari"))
    }

    // MARK: - Activity classifier

    func testActivityClassification() {
        let c = ActivityClassifier()
        XCTAssertEqual(c.classify(appName: "Visual Studio Code", bundleId: "com.microsoft.VSCode", text: "").activity, "coding")
        XCTAssertEqual(c.classify(appName: "Safari", bundleId: "com.apple.Safari", text: "").activity, "browsing")
        XCTAssertEqual(c.classify(appName: "Slack", bundleId: "com.tinyspeck.slackmacgap", text: "").activity, "comms")
        XCTAssertEqual(c.classify(appName: "Figma", bundleId: "com.figma.Desktop", text: "").activity, "design")
        XCTAssertEqual(c.classify(appName: "WeirdApp", bundleId: "com.x.y", text: "").activity, "other")
    }

    func testEntityExtraction() {
        let entities = ActivityClassifier.extractEntities(from: "See https://example.com and edit Sources/Foo.swift — got an Error here")
        XCTAssertTrue(entities.contains(where: { $0.contains("example.com") }))
        XCTAssertTrue(entities.contains(where: { $0.hasSuffix("Foo.swift") }))
        XCTAssertTrue(entities.contains("Error"))
    }
}
