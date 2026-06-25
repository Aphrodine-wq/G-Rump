import XCTest
@testable import GRump

final class MindTests: XCTestCase {

    // MARK: - SurfaceClassifier

    func testSurfaceClassification() {
        let c = SurfaceClassifier()
        XCTAssertEqual(c.classify("Please enter your card number and CVV"), .payment)
        XCTAssertEqual(c.classify("Your API key is shown below"), .secrets)
        XCTAssertEqual(c.classify("Sign in with your password"), .auth)
        XCTAssertEqual(c.classify("just some ordinary prose about cats"), .neutral)
    }

    func testSurfaceEvidence() {
        let c = SurfaceClassifier()
        let text = "Enter your card number and security code"
        let ev = c.evidence(in: text, for: .payment)
        XCTAssertTrue(ev.contains("card number"))
        XCTAssertTrue(ev.contains("security code"))
    }

    // MARK: - ConscienceGate

    func testRefusesOnSensitiveSurface() async {
        let gate = ConscienceGate.shared
        let v = await gate.evaluate(toolName: "write_file", arguments: "path=notes.txt", surface: .payment, surfaceEvidence: ["card number"], roster: .default)
        XCTAssertFalse(v.approved)
        XCTAssertEqual(v.surface, .payment)
        XCTAssertTrue(v.evidence.contains("card number"))
    }

    func testRefusesProtectedBranchPush() async {
        let gate = ConscienceGate.shared
        let v = await gate.evaluate(toolName: "git_push", arguments: "git push origin main", surface: .neutral, surfaceEvidence: [], roster: .default)
        XCTAssertFalse(v.approved)
    }

    func testAllowsFeatureBranchPush() async {
        let gate = ConscienceGate.shared
        let v = await gate.evaluate(toolName: "git_push", arguments: "git push origin feature/eyes", surface: .neutral, surfaceEvidence: [], roster: .default)
        XCTAssertTrue(v.approved)
    }

    func testRefusesDestructiveCommand() async {
        let gate = ConscienceGate.shared
        let v = await gate.evaluate(toolName: "system_run", arguments: "sudo rm -rf /", surface: .neutral, surfaceEvidence: [], roster: .default)
        XCTAssertFalse(v.approved)
    }

    func testRefusesSecretPathWrite() async {
        let gate = ConscienceGate.shared
        let v = await gate.evaluate(toolName: "write_file", arguments: "write to ~/.ssh/id_rsa", surface: .neutral, surfaceEvidence: [], roster: .default)
        XCTAssertFalse(v.approved)
    }

    func testApprovesNormalWrite() async {
        let gate = ConscienceGate.shared
        let v = await gate.evaluate(toolName: "write_file", arguments: "write to Sources/Foo.swift", surface: .neutral, surfaceEvidence: [], roster: .default)
        XCTAssertTrue(v.approved)
    }

    // MARK: - MindStorage default

    func testDefaultMindIsGeneric() {
        let content = MindStorage.defaultMindContent
        XCTAssertTrue(content.contains("# Self"))
        XCTAssertTrue(content.contains("# Conscience"))
        XCTAssertFalse(content.lowercased().contains("casey"))
        XCTAssertFalse(content.lowercased().contains("josh"))
    }
}
