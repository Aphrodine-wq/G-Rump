import XCTest
@testable import GRump

final class ProjectStoreTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProjectStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private var storeFileURL: URL {
        tempDir.appendingPathComponent("recent-projects.json")
    }

    /// Creates a project directory under tempDir containing the given entries
    /// (names ending in "/" become directories).
    private func makeProjectDir(named name: String, containing entries: [String] = []) throws -> String {
        let root = tempDir.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for entry in entries {
            if entry.hasSuffix("/") {
                try FileManager.default.createDirectory(
                    at: root.appendingPathComponent(String(entry.dropLast())),
                    withIntermediateDirectories: true
                )
            } else {
                FileManager.default.createFile(atPath: root.appendingPathComponent(entry).path, contents: Data())
            }
        }
        return root.path
    }

    // MARK: - Detection precedence

    func testDetectWorkspaceWinsOverEverything() throws {
        let path = try makeProjectDir(
            named: "App",
            containing: ["App.xcworkspace/", "App.xcodeproj/", "Package.swift"]
        )
        let project = ProjectStore.detect(at: path)
        XCTAssertEqual(project.kind, .xcworkspace)
        XCTAssertEqual(project.containerPath, (path as NSString).appendingPathComponent("App.xcworkspace"))
        XCTAssertEqual(project.name, "App")
    }

    func testDetectXcodeprojBeatsPackage() throws {
        let path = try makeProjectDir(named: "App", containing: ["App.xcodeproj/", "Package.swift"])
        let project = ProjectStore.detect(at: path)
        XCTAssertEqual(project.kind, .xcodeproj)
        XCTAssertEqual(project.containerPath, (path as NSString).appendingPathComponent("App.xcodeproj"))
    }

    func testDetectSpmPackage() throws {
        let path = try makeProjectDir(named: "Lib", containing: ["Package.swift", "Sources/"])
        let project = ProjectStore.detect(at: path)
        XCTAssertEqual(project.kind, .spmPackage)
        XCTAssertNil(project.containerPath)
    }

    func testDetectPlainFolder() throws {
        let path = try makeProjectDir(named: "Notes", containing: ["readme.md"])
        let project = ProjectStore.detect(at: path)
        XCTAssertEqual(project.kind, .plainFolder)
        XCTAssertNil(project.containerPath)
    }

    func testDetectNonexistentPathFallsBackToPlainFolder() {
        let project = ProjectStore.detect(at: tempDir.appendingPathComponent("missing").path)
        XCTAssertEqual(project.kind, .plainFolder)
        XCTAssertEqual(project.name, "missing")
    }

    func testDetectStandardizesPath() throws {
        let path = try makeProjectDir(named: "Std", containing: [])
        let messy = path + "/./"
        let project = ProjectStore.detect(at: messy)
        XCTAssertEqual(project.rootPath, URL(fileURLWithPath: path).standardizedFileURL.path)
    }

    // MARK: - Recents behavior

    @MainActor
    func testNoteProjectOpenedSetsCurrentAndRecents() throws {
        let store = ProjectStore(fileURL: storeFileURL)
        let path = try makeProjectDir(named: "One", containing: ["Package.swift"])
        store.noteProjectOpened(path)
        XCTAssertEqual(store.current?.rootPath, URL(fileURLWithPath: path).standardizedFileURL.path)
        XCTAssertEqual(store.recents.count, 1)
        XCTAssertEqual(store.recents.first?.kind, .spmPackage)
    }

    @MainActor
    func testEmptyPathClosesProjectButKeepsRecents() throws {
        let store = ProjectStore(fileURL: storeFileURL)
        store.noteProjectOpened(try makeProjectDir(named: "One"))
        XCTAssertNotNil(store.current)
        store.noteProjectOpened("")
        XCTAssertNil(store.current)
        XCTAssertEqual(store.recents.count, 1)
    }

    @MainActor
    func testReopenDedupesAndMovesToFront() throws {
        let store = ProjectStore(fileURL: storeFileURL)
        let first = try makeProjectDir(named: "First")
        let second = try makeProjectDir(named: "Second")
        store.noteProjectOpened(first)
        store.noteProjectOpened(second)
        store.noteProjectOpened(first)
        XCTAssertEqual(store.recents.count, 2)
        XCTAssertEqual(store.recents.map(\.name), ["First", "Second"])
    }

    @MainActor
    func testReopenReDetectsKind() throws {
        let store = ProjectStore(fileURL: storeFileURL)
        let path = try makeProjectDir(named: "Evolving")
        store.noteProjectOpened(path)
        XCTAssertEqual(store.recents.first?.kind, .plainFolder)
        FileManager.default.createFile(
            atPath: (path as NSString).appendingPathComponent("Package.swift"),
            contents: Data()
        )
        store.noteProjectOpened(path)
        XCTAssertEqual(store.recents.first?.kind, .spmPackage)
        XCTAssertEqual(store.recents.count, 1)
    }

    @MainActor
    func testUnpinnedCapAtTwenty() throws {
        let store = ProjectStore(fileURL: storeFileURL)
        for index in 0..<25 {
            store.noteProjectOpened(try makeProjectDir(named: "P\(index)"))
        }
        XCTAssertEqual(store.recents.count, 20)
        // The five oldest aged out.
        XCTAssertFalse(store.recents.contains { $0.name == "P0" })
        XCTAssertTrue(store.recents.contains { $0.name == "P24" })
    }

    @MainActor
    func testPinnedEntriesSurviveCapAndSortFirst() throws {
        let store = ProjectStore(fileURL: storeFileURL)
        let pinnedPath = try makeProjectDir(named: "Pinned")
        store.noteProjectOpened(pinnedPath)
        store.togglePin(rootPath: URL(fileURLWithPath: pinnedPath).standardizedFileURL.path)
        for index in 0..<25 {
            store.noteProjectOpened(try makeProjectDir(named: "P\(index)"))
        }
        XCTAssertEqual(store.recents.count, 21)   // 20 unpinned + 1 pinned
        XCTAssertEqual(store.recents.first?.name, "Pinned")
        XCTAssertTrue(store.recents.first?.isPinned == true)
    }

    @MainActor
    func testReopenPreservesPin() throws {
        let store = ProjectStore(fileURL: storeFileURL)
        let path = try makeProjectDir(named: "Keep")
        store.noteProjectOpened(path)
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        store.togglePin(rootPath: standardized)
        store.noteProjectOpened(path)
        XCTAssertTrue(store.recents.first?.isPinned == true)
    }

    @MainActor
    func testRemoveRecentAndRemoveAll() throws {
        let store = ProjectStore(fileURL: storeFileURL)
        let first = try makeProjectDir(named: "First")
        store.noteProjectOpened(first)
        store.noteProjectOpened(try makeProjectDir(named: "Second"))
        store.removeRecent(rootPath: URL(fileURLWithPath: first).standardizedFileURL.path)
        XCTAssertEqual(store.recents.map(\.name), ["Second"])
        store.removeAll()
        XCTAssertTrue(store.recents.isEmpty)
    }

    // MARK: - Persistence

    @MainActor
    func testJSONRoundTripAndHydration() throws {
        let path = try makeProjectDir(named: "Persisted", containing: ["Package.swift"])
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        do {
            let store = ProjectStore(fileURL: storeFileURL)
            store.noteProjectOpened(path)
            store.togglePin(rootPath: standardized)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: storeFileURL.path))

        let rehydrated = ProjectStore(fileURL: storeFileURL)
        XCTAssertEqual(rehydrated.recents.count, 1)
        let project = try XCTUnwrap(rehydrated.recents.first)
        XCTAssertEqual(project.rootPath, standardized)
        XCTAssertEqual(project.kind, .spmPackage)
        XCTAssertTrue(project.isPinned)
        XCTAssertNil(rehydrated.current)   // current is runtime state, never persisted
    }

    @MainActor
    func testHydrationToleratesCorruptFile() throws {
        try Data("not json".utf8).write(to: storeFileURL)
        let store = ProjectStore(fileURL: storeFileURL)
        XCTAssertTrue(store.recents.isEmpty)
    }

    func testProjectCodableRoundTrip() throws {
        let project = Project(
            name: "App",
            rootPath: "/tmp/App",
            kind: .xcworkspace,
            containerPath: "/tmp/App/App.xcworkspace",
            lastOpenedAt: Date(timeIntervalSince1970: 1_700_000_000),
            isPinned: true
        )
        let data = try JSONEncoder().encode(project)
        let decoded = try JSONDecoder().decode(Project.self, from: data)
        XCTAssertEqual(decoded, project)
        XCTAssertEqual(decoded.id, "/tmp/App")
    }
}
