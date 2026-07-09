import XCTest
@testable import GRump

final class BuildServiceTests: XCTestCase {

    // MARK: - Chunk line-buffering

    func testChunksSplitMidLineReassemble() {
        var buffer = ChunkLineBuffer()
        XCTAssertEqual(buffer.consume("Compiling Fo"), [])
        XCTAssertEqual(buffer.consume("o.swift\nLinking"), ["Compiling Foo.swift"])
        XCTAssertEqual(buffer.consume(" GRump\n"), ["Linking GRump"])
        XCTAssertNil(buffer.flushRemainder())
    }

    func testMultipleLinesInOneChunk() {
        var buffer = ChunkLineBuffer()
        XCTAssertEqual(buffer.consume("a\nb\nc\n"), ["a", "b", "c"])
    }

    func testFlushRemainderReturnsTrailingPartialLine() {
        var buffer = ChunkLineBuffer()
        _ = buffer.consume("no newline yet")
        XCTAssertEqual(buffer.flushRemainder(), "no newline yet")
        XCTAssertNil(buffer.flushRemainder(), "remainder must clear after flush")
    }

    // MARK: - Transition legality

    func testLegalTransitions() {
        XCTAssertTrue(BuildPhase.isLegalTransition(from: .idle, to: .building))
        XCTAssertTrue(BuildPhase.isLegalTransition(from: .building, to: .succeeded(duration: 1, warnings: 0)))
        XCTAssertTrue(BuildPhase.isLegalTransition(from: .building, to: .failed(errors: 1, warnings: 0)))
        XCTAssertTrue(BuildPhase.isLegalTransition(from: .building, to: .cancelled))
        XCTAssertTrue(BuildPhase.isLegalTransition(from: .failed(errors: 1, warnings: 0), to: .building))
        XCTAssertTrue(BuildPhase.isLegalTransition(from: .cancelled, to: .idle))
    }

    func testIllegalTransitions() {
        XCTAssertFalse(BuildPhase.isLegalTransition(from: .idle, to: .succeeded(duration: 1, warnings: 0)))
        XCTAssertFalse(BuildPhase.isLegalTransition(from: .idle, to: .cancelled))
        XCTAssertFalse(BuildPhase.isLegalTransition(from: .building, to: .building))
        XCTAssertFalse(BuildPhase.isLegalTransition(from: .building, to: .idle))
        XCTAssertFalse(BuildPhase.isLegalTransition(from: .idle, to: .idle))
    }

    // MARK: - Exit-code mapping

    func testExitCodeZeroMapsToSucceeded() {
        let phase = BuildPhase.terminal(exitCode: 0, cancelled: false, duration: 2.5, errors: 0, warnings: 3)
        XCTAssertEqual(phase, .succeeded(duration: 2.5, warnings: 3))
    }

    func testNonZeroExitMapsToFailed() {
        let phase = BuildPhase.terminal(exitCode: 65, cancelled: false, duration: 1, errors: 2, warnings: 1)
        XCTAssertEqual(phase, .failed(errors: 2, warnings: 1))
    }

    func testCancelWinsOverExitCode() {
        XCTAssertEqual(BuildPhase.terminal(exitCode: 15, cancelled: true, duration: 1, errors: 0, warnings: 0), .cancelled)
        XCTAssertEqual(BuildPhase.terminal(exitCode: 0, cancelled: true, duration: 1, errors: 0, warnings: 0), .cancelled)
    }

    // MARK: - Destination default

    func testDefaultDestinationPrefersBootedSimulator() {
        let destinations: [BuildDestination] = [
            .mac,
            .simulator(udid: "A", name: "iPhone 16", booted: false),
            .simulator(udid: "B", name: "iPad Pro", booted: true)
        ]
        XCTAssertEqual(
            BuildDestination.defaultDestination(from: destinations),
            .simulator(udid: "B", name: "iPad Pro", booted: true)
        )
    }

    func testDefaultDestinationFallsBackToFirstIPhone() {
        let destinations: [BuildDestination] = [
            .mac,
            .simulator(udid: "A", name: "iPad Pro", booted: false),
            .simulator(udid: "B", name: "iPhone 16", booted: false)
        ]
        XCTAssertEqual(
            BuildDestination.defaultDestination(from: destinations),
            .simulator(udid: "B", name: "iPhone 16", booted: false)
        )
    }

    func testDefaultDestinationFallsBackToMac() {
        XCTAssertEqual(BuildDestination.defaultDestination(from: [.mac]), .mac)
        XCTAssertNil(BuildDestination.defaultDestination(from: []))
    }

    func testXcodebuildArgument() {
        XCTAssertEqual(BuildDestination.mac.xcodebuildArgument, "platform=macOS")
        XCTAssertEqual(
            BuildDestination.simulator(udid: "UDID-1", name: "iPhone 16", booted: false).xcodebuildArgument,
            "id=UDID-1"
        )
    }

    // MARK: - Issue accumulation (parser fixture)

    func testIssueAccumulationFromBuildOutput() {
        let output = """
        Compiling GRump BuildService.swift
        /src/App/Foo.swift:12:5: error: cannot find 'bar' in scope
        /src/App/Foo.swift:20:1: warning: variable 'x' was never used
        Linking GRump
        """
        let issues = BuildErrorParserEngine.parse(output)
        XCTAssertEqual(issues.count, 2)
        XCTAssertEqual(issues.first?.severity, .error)
        XCTAssertEqual(issues.first?.line, 12)
        XCTAssertEqual(issues.last?.severity, .warning)
    }

    // MARK: - Ring buffer

    @MainActor
    func testConsoleRingBufferCapsAtLimit() {
        let service = BuildService()
        XCTAssertEqual(service.maxConsoleLines, 10_000)
    }

    // MARK: - showBuildSettings JSON fixture

    func testParseBuildSettingsFixture() throws {
        let fixture = """
        [
          {
            "action": "build",
            "target": "SmokeApp",
            "buildSettings": {
              "TARGET_BUILD_DIR": "/tmp/DerivedData/Build/Products/Debug-iphonesimulator",
              "FULL_PRODUCT_NAME": "SmokeApp.app",
              "PRODUCT_BUNDLE_IDENTIFIER": "com.example.SmokeApp",
              "PRODUCT_NAME": "SmokeApp"
            }
          }
        ]
        """
        let settings = try XCTUnwrap(XcodeProjectInspector.parseBuildSettings(json: Data(fixture.utf8)))
        XCTAssertEqual(settings.targetBuildDir, "/tmp/DerivedData/Build/Products/Debug-iphonesimulator")
        XCTAssertEqual(settings.fullProductName, "SmokeApp.app")
        XCTAssertEqual(settings.bundleId, "com.example.SmokeApp")
        XCTAssertEqual(settings.productName, "SmokeApp")
        XCTAssertEqual(settings.productPath, "/tmp/DerivedData/Build/Products/Debug-iphonesimulator/SmokeApp.app")
    }

    func testParseBuildSettingsRejectsGarbage() {
        XCTAssertNil(XcodeProjectInspector.parseBuildSettings(json: Data("not json".utf8)))
        XCTAssertNil(XcodeProjectInspector.parseBuildSettings(json: Data("[]".utf8)))
        XCTAssertNil(XcodeProjectInspector.parseBuildSettings(json: Data(#"[{"buildSettings": {}}]"#.utf8)))
    }

    // MARK: - simctl device list fixture

    func testParseDeviceListFixture() throws {
        let fixture = """
        {
          "devices": {
            "com.apple.CoreSimulator.SimRuntime.iOS-18-0": [
              {"udid": "AAA", "name": "iPhone 16", "state": "Shutdown", "isAvailable": true},
              {"udid": "BBB", "name": "iPad Pro 11-inch", "state": "Booted", "isAvailable": true},
              {"udid": "CCC", "name": "Broken Device", "state": "Shutdown", "isAvailable": false}
            ]
          }
        }
        """
        let devices = try XCTUnwrap(SimulatorService.parseDeviceList(Data(fixture.utf8)))
        XCTAssertEqual(devices.count, 2, "unavailable devices are excluded")
        XCTAssertEqual(devices.first?.id, "BBB", "booted devices sort first")
        XCTAssertEqual(devices.first?.state, .booted)
        XCTAssertEqual(devices.last?.name, "iPhone 16")
    }

    func testParseDeviceListRejectsGarbage() {
        XCTAssertNil(SimulatorService.parseDeviceList(Data("nope".utf8)))
    }
}
