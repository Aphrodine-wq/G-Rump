import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - File Node Model

struct FileNode: Identifiable, Hashable {
    let id: String
    let name: String
    let path: String
    let isDirectory: Bool
    var children: [FileNode]
    var isExpanded: Bool = false

    var icon: String {
        if isDirectory {
            return isExpanded ? "folder.fill" : "folder"
        }
        return FileNode.iconForExtension((name as NSString).pathExtension)
    }

    var iconColor: Color {
        if isDirectory { return .accentOrange }
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return Color(red: 1.0, green: 0.45, blue: 0.25)
        case "py": return Color(red: 0.2, green: 0.6, blue: 1.0)
        case "js", "ts", "jsx", "tsx": return Color(red: 0.95, green: 0.85, blue: 0.3)
        case "json", "yaml", "yml", "toml": return Color(red: 0.6, green: 0.6, blue: 0.7)
        case "md", "txt": return Color(red: 0.5, green: 0.7, blue: 0.9)
        case "html", "css", "scss": return Color(red: 0.9, green: 0.4, blue: 0.5)
        case "xcodeproj", "xcworkspace", "pbxproj": return Color(red: 0.3, green: 0.6, blue: 1.0)
        case "plist", "entitlements": return Color(red: 0.7, green: 0.7, blue: 0.8)
        case "png", "jpg", "jpeg", "gif", "svg", "webp": return Color(red: 0.85, green: 0.3, blue: 0.9)
        case "xcassets": return Color(red: 0.3, green: 0.8, blue: 0.5)
        default: return Color(red: 0.5, green: 0.5, blue: 0.6)
        }
    }

    static func iconForExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        case "swift": return "swift"
        case "py": return "chevron.left.forwardslash.chevron.right"
        case "js", "ts", "jsx", "tsx": return "curlybraces"
        case "json": return "doc.text"
        case "yaml", "yml", "toml": return "doc.text"
        case "md", "txt": return "text.alignleft"
        case "html", "xml", "svg": return "chevron.left.forwardslash.chevron.right"
        case "css", "scss", "sass": return "paintbrush"
        case "png", "jpg", "jpeg", "gif", "webp", "heic": return "photo"
        case "pdf": return "doc.richtext"
        case "xcodeproj", "xcworkspace": return "hammer"
        case "plist": return "list.bullet.rectangle"
        case "entitlements": return "lock.shield"
        case "xcassets": return "photo.stack"
        case "xcdatamodeld": return "cylinder.split.1x2"
        case "xcstrings": return "globe"
        case "sh", "bash", "zsh": return "terminal"
        case "zip", "tar", "gz": return "doc.zipper"
        case "gitignore": return "eye.slash"
        default: return "doc"
        }
    }
}

// MARK: - File Tree Service

@MainActor
final class FileTreeService: ObservableObject {
    @Published var rootNodes: [FileNode] = []
    @Published var isLoading = false
    private var workingDirectory: String = ""
    #if os(macOS)
    private var fsEventStream: FSEventStreamRef?
    #endif

    private static let ignoredNames: Set<String> = [
        ".git", ".build", ".swiftpm", "node_modules", ".DS_Store",
        "DerivedData", "Pods", ".Trash", "__pycache__", ".venv",
        "venv", ".env", "xcuserdata", ".gradle"
    ]

    func setDirectory(_ path: String) {
        guard !path.isEmpty, path != workingDirectory else { return }
        workingDirectory = path
        refresh()
        #if os(macOS)
        startWatching()
        #endif
    }

    func refresh() {
        guard !workingDirectory.isEmpty else { return }
        isLoading = true
        let dir = workingDirectory
        Task.detached(priority: .userInitiated) {
            let nodes = await Self.buildTree(at: dir, depth: 0, maxDepth: 8)
            await MainActor.run {
                self.rootNodes = nodes
                self.isLoading = false
            }
        }
    }

    func toggleExpansion(_ node: FileNode) {
        toggleInNodes(&rootNodes, id: node.id)
    }

    /// Expands every ancestor directory of `path` so its node is visible
    /// (Reveal in Navigator). No-op for paths outside the working directory.
    func expandTo(path: String) {
        guard !workingDirectory.isEmpty else { return }
        let standardized = (path as NSString).standardizingPath
        guard standardized.hasPrefix(workingDirectory + "/") || standardized == workingDirectory else { return }
        expandAncestors(&rootNodes, target: standardized)
    }

    private func expandAncestors(_ nodes: inout [FileNode], target: String) {
        for index in nodes.indices where nodes[index].isDirectory {
            if target == nodes[index].path || target.hasPrefix(nodes[index].path + "/") {
                nodes[index].isExpanded = true
                expandAncestors(&nodes[index].children, target: target)
            }
        }
    }

    private func toggleInNodes(_ nodes: inout [FileNode], id: String) {
        for i in nodes.indices {
            if nodes[i].id == id {
                nodes[i].isExpanded.toggle()
                return
            }
            if !nodes[i].children.isEmpty {
                toggleInNodes(&nodes[i].children, id: id)
            }
        }
    }

    nonisolated private static func buildTree(at path: String, depth: Int, maxDepth: Int) -> [FileNode] {
        guard depth < maxDepth else { return [] }
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: path) else { return [] }

        var dirs: [FileNode] = []
        var files: [FileNode] = []

        for name in contents.sorted(by: { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }) {
            guard !ignoredNames.contains(name) && !name.hasPrefix(".") else { continue }
            let fullPath = (path as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: fullPath, isDirectory: &isDir) else { continue }

            if isDir.boolValue {
                let children = buildTree(at: fullPath, depth: depth + 1, maxDepth: maxDepth)
                dirs.append(FileNode(id: fullPath, name: name, path: fullPath, isDirectory: true, children: children))
            } else {
                files.append(FileNode(id: fullPath, name: name, path: fullPath, isDirectory: false, children: []))
            }
        }

        return dirs + files
    }

    #if os(macOS)
    private func startWatching() {
        stopWatching()
        guard !workingDirectory.isEmpty else { return }
        let paths = [workingDirectory] as CFArray
        let callback: FSEventStreamCallback = { _, clientCallbackInfo, _, _, _, _ in
            guard let info = clientCallbackInfo else { return }
            let service = Unmanaged<FileTreeService>.fromOpaque(info).takeUnretainedValue()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                service.refresh()
            }
        }
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        fsEventStream = FSEventStreamCreate(
            nil,
            callback,
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            2.0,
            UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        )
        if let stream = fsEventStream {
            FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            FSEventStreamStart(stream)
        }
    }

    private func stopWatching() {
        if let stream = fsEventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            fsEventStream = nil
        }
    }

    #endif

    func createFile(at directory: String, name: String) {
        let path = (directory as NSString).appendingPathComponent(name)
        FileManager.default.createFile(atPath: path, contents: nil)
        refresh()
    }

    func createFolder(at directory: String, name: String) {
        let path = (directory as NSString).appendingPathComponent(name)
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        refresh()
    }

    func deleteItem(at path: String) {
        try? FileManager.default.removeItem(atPath: path)
        refresh()
    }

    func renameItem(at path: String, to newName: String) {
        let parent = (path as NSString).deletingLastPathComponent
        let newPath = (parent as NSString).appendingPathComponent(newName)
        try? FileManager.default.moveItem(atPath: path, toPath: newPath)
        refresh()
    }
}

// MARK: - Project Navigator View

struct ProjectNavigatorView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var viewModel: ChatViewModel
    @StateObject private var fileTree = FileTreeService()
    @State private var searchText = ""
    @State private var selectedFilePath: String?
    @State private var showNewFileDialog = false
    @State private var showNewFolderDialog = false
    @State private var newItemName = ""
    @State private var newItemParentPath = ""
    @State private var inlineChatFilePath: String?

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: Spacing.md) {
                Image(systemName: "magnifyingglass")
                    .font(Typography.captionSmall)
                    .foregroundColor(themeManager.palette.textMuted)
                TextField("Filter files…", text: $searchText)
                    .font(Typography.bodySmall)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(Typography.captionSmall)
                            .foregroundColor(themeManager.palette.textMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.lg)
            .background(themeManager.palette.bgInput)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.lg)
            .padding(.bottom, Spacing.md)

            // Toolbar
            HStack(spacing: Spacing.md) {
                Text(viewModel.workingDirectory.isEmpty ? "No project" : (viewModel.workingDirectory as NSString).lastPathComponent)
                    .font(Typography.captionSmallSemibold)
                    .foregroundColor(themeManager.palette.textSecondary)
                    .lineLimit(1)

                Spacer()

                Button(action: { fileTree.refresh() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(Typography.captionSmall)
                        .foregroundColor(themeManager.palette.textMuted)
                }
                .buttonStyle(ScaleButtonStyle())
                .help("Refresh")

                #if os(macOS)
                Button(action: {
                    if !viewModel.workingDirectory.isEmpty {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: viewModel.workingDirectory)
                    }
                }) {
                    Image(systemName: "arrow.up.forward.square")
                        .font(Typography.captionSmall)
                        .foregroundColor(themeManager.palette.textMuted)
                }
                .buttonStyle(ScaleButtonStyle())
                .help("Reveal in Finder")
                #endif
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.sm)

            Rectangle()
                .fill(themeManager.palette.borderSubtle)
                .frame(height: Border.thin)

            // File tree
            if viewModel.workingDirectory.isEmpty {
                emptyState
            } else if fileTree.isLoading && fileTree.rootNodes.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filteredNodes(fileTree.rootNodes)) { node in
                            FileNodeRow(
                                node: node,
                                depth: 0,
                                selectedPath: $selectedFilePath,
                                fileTree: fileTree,
                                onOpenFile: { path in
                                    viewModel.userInput = "Read and analyze the file: \(path)"
                                },
                                onNewFile: { parentPath in
                                    newItemParentPath = parentPath
                                    showNewFileDialog = true
                                },
                                onNewFolder: { parentPath in
                                    newItemParentPath = parentPath
                                    showNewFolderDialog = true
                                },
                                onAskAbout: { path in
                                    withAnimation(Anim.spring) {
                                        inlineChatFilePath = path
                                    }
                                }
                            )
                        }
                    }
                    .padding(.vertical, Spacing.sm)
                }
            }

            // Inline file chat
            if let chatPath = inlineChatFilePath {
                InlineFileChatView(
                    filePath: chatPath,
                    onDismiss: {
                        withAnimation(Anim.spring) {
                            inlineChatFilePath = nil
                        }
                    }
                )
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .bottom)),
                    removal: .opacity
                ))
                .padding(.bottom, Spacing.md)
            }
        }
        .background(themeManager.palette.bgDark)
        .onAppear {
            fileTree.setDirectory(viewModel.workingDirectory)
        }
        .onChange(of: viewModel.workingDirectory) { _, newDir in
            fileTree.setDirectory(newDir)
        }
        // Reveal in Navigator (build console issues, future callers).
        .onReceive(NotificationCenter.default.publisher(for: .init("GRumpRevealFile"))) { note in
            guard let path = note.userInfo?["path"] as? String else { return }
            fileTree.expandTo(path: path)
            selectedFilePath = (path as NSString).standardizingPath
        }
        .alert("New File", isPresented: $showNewFileDialog) {
            TextField("filename.swift", text: $newItemName)
            Button("Create") {
                if !newItemName.isEmpty {
                    fileTree.createFile(at: newItemParentPath, name: newItemName)
                    newItemName = ""
                }
            }
            Button("Cancel", role: .cancel) { newItemName = "" }
        }
        .alert("New Folder", isPresented: $showNewFolderDialog) {
            TextField("FolderName", text: $newItemName)
            Button("Create") {
                if !newItemName.isEmpty {
                    fileTree.createFolder(at: newItemParentPath, name: newItemName)
                    newItemName = ""
                }
            }
            Button("Cancel", role: .cancel) { newItemName = "" }
        }
    }

    private func filteredNodes(_ nodes: [FileNode]) -> [FileNode] {
        guard !searchText.isEmpty else { return nodes }
        return nodes.compactMap { node in
            if node.name.localizedCaseInsensitiveContains(searchText) {
                return node
            }
            if node.isDirectory {
                let filtered = filteredNodes(node.children)
                if !filtered.isEmpty {
                    var copy = node
                    copy.children = filtered
                    copy.isExpanded = true
                    return copy
                }
            }
            return nil
        }
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.xxl) {
            Spacer()
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(themeManager.palette.textMuted)
            Text("No project open")
                .font(Typography.bodySmallMedium)
                .foregroundColor(themeManager.palette.textSecondary)
            Text("Open a folder to browse files")
                .font(Typography.captionSmall)
                .foregroundColor(themeManager.palette.textMuted)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - File Node Row

struct FileNodeRow: View {
    @EnvironmentObject var themeManager: ThemeManager
    let node: FileNode
    let depth: Int
    @Binding var selectedPath: String?
    @ObservedObject var fileTree: FileTreeService
    var onOpenFile: (String) -> Void
    var onNewFile: (String) -> Void
    var onNewFolder: (String) -> Void
    var onAskAbout: ((String) -> Void)?
    @State private var isHovered = false
    @State private var isRenaming = false
    @State private var renameName = ""

    private var isSelected: Bool { selectedPath == node.path }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Row content
            HStack(spacing: Spacing.sm) {
                // Expand arrow (directories only)
                if node.isDirectory {
                    Image(systemName: node.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(themeManager.palette.textMuted)
                        .frame(width: 10)
                } else {
                    Spacer().frame(width: 10)
                }

                // File icon
                Image(systemName: node.icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(node.iconColor)
                    .frame(width: 16)

                // Name
                if isRenaming {
                    TextField("Name", text: $renameName, onCommit: {
                        if !renameName.isEmpty {
                            fileTree.renameItem(at: node.path, to: renameName)
                        }
                        isRenaming = false
                    })
                    .font(Typography.bodySmall)
                    .textFieldStyle(.plain)
                    #if os(macOS)
                    .onExitCommand { isRenaming = false }
                    #endif
                } else {
                    Text(node.name)
                        .font(Typography.bodySmall)
                        .foregroundColor(isSelected ? themeManager.palette.effectiveAccent : themeManager.palette.textPrimary)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.leading, CGFloat(depth) * 16 + Spacing.lg)
            .padding(.trailing, Spacing.lg)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                    .fill(isSelected ? themeManager.palette.effectiveAccent.opacity(0.1)
                          : isHovered ? themeManager.palette.bgElevated.opacity(0.5)
                          : Color.clear)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                if node.isDirectory {
                    fileTree.toggleExpansion(node)
                } else {
                    selectedPath = node.path
                }
            }
            .onTapGesture(count: 2) {
                if !node.isDirectory {
                    onOpenFile(node.path)
                }
            }
            .onHover { isHovered = $0 }
            #if os(macOS)
            .contextMenu {
                if node.isDirectory {
                    Button(action: { onNewFile(node.path) }) {
                        Label("New File", systemImage: "doc.badge.plus")
                    }
                    Button(action: { onNewFolder(node.path) }) {
                        Label("New Folder", systemImage: "folder.badge.plus")
                    }
                    Divider()
                }
                Button(action: {
                    renameName = node.name
                    isRenaming = true
                }) {
                    Label("Rename", systemImage: "pencil")
                }
                Button(action: {
                    NSWorkspace.shared.selectFile(node.path, inFileViewerRootedAtPath: (node.path as NSString).deletingLastPathComponent)
                }) {
                    Label("Reveal in Finder", systemImage: "arrow.up.forward.square")
                }
                if !node.isDirectory {
                    Button(action: {
                        if let xcodeURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.dt.Xcode") {
                            NSWorkspace.shared.open([URL(fileURLWithPath: node.path)], withApplicationAt: xcodeURL, configuration: NSWorkspace.OpenConfiguration())
                        }
                    }) {
                        Label("Open in Xcode", systemImage: "hammer")
                    }
                    Button(action: { onAskAbout?(node.path) }) {
                        Label("Ask G-Rump…", systemImage: "bubble.left")
                    }
                }
                Divider()
                Button(role: .destructive, action: { fileTree.deleteItem(at: node.path) }) {
                    Label("Delete", systemImage: "trash")
                }
            }
            #endif

            // Children (if expanded)
            if node.isDirectory && node.isExpanded {
                ForEach(node.children) { child in
                    FileNodeRow(
                        node: child,
                        depth: depth + 1,
                        selectedPath: $selectedPath,
                        fileTree: fileTree,
                        onOpenFile: onOpenFile,
                        onNewFile: onNewFile,
                        onNewFolder: onNewFolder,
                        onAskAbout: onAskAbout
                    )
                }
            }
        }
    }
}
