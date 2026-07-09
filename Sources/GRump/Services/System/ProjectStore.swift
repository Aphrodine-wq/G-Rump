import Foundation

// MARK: - Project Kind

enum ProjectKind: String, Codable {
    case xcworkspace
    case xcodeproj
    case spmPackage
    case plainFolder
}

// MARK: - Project

struct Project: Codable, Equatable, Identifiable {
    var id: String { rootPath }
    let name: String
    let rootPath: String            // absolute, standardized
    let kind: ProjectKind
    let containerPath: String?      // full path to the .xcworkspace/.xcodeproj when present
    var lastOpenedAt: Date
    var isPinned: Bool = false
}

// MARK: - Project Store

/// Single source of truth for the currently open project and the recents list.
/// The ONE mutation point is `ChatViewModel.setWorkingDirectory`, which calls
/// `noteProjectOpened(_:)` — every open path (NSOpenPanel, sidebar, Settings,
/// Welcome window, onboarding-free launch) funnels through it.
@MainActor
final class ProjectStore: ObservableObject {
    static let shared = ProjectStore()

    @Published private(set) var current: Project?
    @Published private(set) var recents: [Project] = []

    /// Unpinned recents are capped; pinned entries never age out.
    private let unpinnedCap = 20
    private let fileURL: URL

    init(fileURL: URL = ProjectStore.defaultFileURL) {
        self.fileURL = fileURL
        recents = Self.load(from: fileURL)
    }

    static var defaultFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".grump")
            .appendingPathComponent("recent-projects.json")
    }

    // MARK: - Detection

    /// Detects what kind of project lives at `rootPath`.
    /// Precedence: .xcworkspace > .xcodeproj > Package.swift > plain folder.
    nonisolated static func detect(at rootPath: String) -> Project {
        let standardized = URL(fileURLWithPath: (rootPath as NSString).expandingTildeInPath)
            .standardizedFileURL.path
        let name = (standardized as NSString).lastPathComponent
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: standardized))?.sorted() ?? []

        if let workspace = contents.first(where: { $0.hasSuffix(".xcworkspace") }) {
            return Project(
                name: name,
                rootPath: standardized,
                kind: .xcworkspace,
                containerPath: (standardized as NSString).appendingPathComponent(workspace),
                lastOpenedAt: Date()
            )
        }
        if let xcodeproj = contents.first(where: { $0.hasSuffix(".xcodeproj") }) {
            return Project(
                name: name,
                rootPath: standardized,
                kind: .xcodeproj,
                containerPath: (standardized as NSString).appendingPathComponent(xcodeproj),
                lastOpenedAt: Date()
            )
        }
        if contents.contains("Package.swift") {
            return Project(name: name, rootPath: standardized, kind: .spmPackage, containerPath: nil, lastOpenedAt: Date())
        }
        return Project(name: name, rootPath: standardized, kind: .plainFolder, containerPath: nil, lastOpenedAt: Date())
    }

    // MARK: - Mutations

    /// Records a project open. An empty path means the project was closed.
    /// Kind is re-detected on every open (a folder can gain an .xcodeproj between opens).
    func noteProjectOpened(_ path: String) {
        guard !path.isEmpty else {
            close()
            return
        }
        var project = Self.detect(at: path)
        if let existing = recents.first(where: { $0.rootPath == project.rootPath }) {
            project.isPinned = existing.isPinned
        }
        recents.removeAll { $0.rootPath == project.rootPath }
        recents.append(project)
        current = project
        normalizeAndSave()
    }

    func removeRecent(rootPath: String) {
        recents.removeAll { $0.rootPath == rootPath }
        normalizeAndSave()
    }

    func togglePin(rootPath: String) {
        guard let index = recents.firstIndex(where: { $0.rootPath == rootPath }) else { return }
        recents[index].isPinned.toggle()
        normalizeAndSave()
    }

    func removeAll() {
        recents.removeAll()
        normalizeAndSave()
    }

    func close() {
        current = nil
    }

    // MARK: - Ordering + persistence

    /// Pinned first, then most recently opened; unpinned entries beyond the cap age out.
    private func normalizeAndSave() {
        recents.sort {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            return $0.lastOpenedAt > $1.lastOpenedAt
        }
        var unpinnedSeen = 0
        recents = recents.filter { project in
            if project.isPinned { return true }
            unpinnedSeen += 1
            return unpinnedSeen <= unpinnedCap
        }
        save()
    }

    private func save() {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(recents)
            try data.write(to: fileURL)
        } catch {
            GRumpLogger.persistence.error("ProjectStore save failed: \(error.localizedDescription)")
        }
    }

    private static func load(from fileURL: URL) -> [Project] {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Project].self, from: data) else {
            return []
        }
        return decoded
    }
}
