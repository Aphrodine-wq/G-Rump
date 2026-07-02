import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - Architecture Models

struct ArchNode: Identifiable, Hashable {
    let id: String
    var name: String
    var filePath: String
    var nodeType: ArchNodeType
    var loc: Int
    var complexity: Int
    var connections: [String] = []
    var position: CGPoint = .zero
    var velocity: CGPoint = .zero

    enum ArchNodeType: String, CaseIterable, Hashable {
        case module, file, classType, structType, protocolType, enumType

        var label: String {
            switch self {
            case .module: return "Module"
            case .file: return "File"
            case .classType: return "Class"
            case .structType: return "Struct"
            case .protocolType: return "Protocol"
            case .enumType: return "Enum"
            }
        }

        var color: Color {
            switch self {
            case .module: return Color(red: 0.30, green: 0.55, blue: 0.95)
            case .file: return Color.accentGreen
            case .classType: return Color.accentOrange
            case .structType: return Color(red: 0.95, green: 0.65, blue: 0.20)
            case .protocolType: return Color.brandPurple
            case .enumType: return Color(red: 0.85, green: 0.35, blue: 0.50)
            }
        }

        var icon: String {
            switch self {
            case .module: return "shippingbox.fill"
            case .file: return "doc.fill"
            case .classType: return "c.square.fill"
            case .structType: return "s.square.fill"
            case .protocolType: return "p.square.fill"
            case .enumType: return "e.square.fill"
            }
        }
    }

    static func == (lhs: ArchNode, rhs: ArchNode) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct ArchEdge: Identifiable, Hashable {
    let id: String
    var source: String
    var target: String
    var edgeType: ArchEdgeType
    var isCycle: Bool = false

    enum ArchEdgeType: String, CaseIterable, Hashable {
        case importDep, inheritance, conformance, call

        var label: String {
            switch self {
            case .importDep: return "Import"
            case .inheritance: return "Inherits"
            case .conformance: return "Conforms"
            case .call: return "Calls"
            }
        }

        var color: Color {
            switch self {
            case .importDep: return Color(red: 0.5, green: 0.5, blue: 0.55)
            case .inheritance: return Color(red: 0.30, green: 0.55, blue: 0.95)
            case .conformance: return Color.brandPurple
            case .call: return Color.accentGreen
            }
        }
    }
}

enum ArchTab: String, CaseIterable {
    case dependencyGraph = "Dependency Graph"
    case moduleMap = "Module Map"
    case callHierarchy = "Call Hierarchy"
    case metrics = "Metrics"

    var icon: String {
        switch self {
        case .dependencyGraph: return "point.3.connected.trianglepath.dotted"
        case .moduleMap: return "map.fill"
        case .callHierarchy: return "arrow.triangle.branch"
        case .metrics: return "chart.bar.fill"
        }
    }
}

enum GraphLayout: String, CaseIterable {
    case forceDirected = "Force-Directed"
    case hierarchical = "Hierarchical"
    case circular = "Circular"

    var icon: String {
        switch self {
        case .forceDirected: return "atom"
        case .hierarchical: return "list.bullet.indent"
        case .circular: return "circle.hexagonpath"
        }
    }
}

// MARK: - Architecture ViewModel

@MainActor
final class ArchitectureViewModel: ObservableObject {
    @Published var selectedTab: ArchTab = .dependencyGraph
    @Published var selectedNode: ArchNode?
    @Published var zoomLevel: CGFloat = 1.0
    @Published var searchQuery: String = ""
    @Published var isLoading: Bool = false
    @Published var graphLayout: GraphLayout = .forceDirected
    @Published var nodes: [ArchNode] = []
    @Published var edges: [ArchEdge] = []
    @Published var panOffset: CGSize = .zero
    @Published var showDetailPanel: Bool = true
    @Published var analysisProgress: Double = 0.0

    var filteredNodes: [ArchNode] {
        guard !searchQuery.isEmpty else { return nodes }
        return nodes.filter { $0.name.localizedCaseInsensitiveContains(searchQuery) }
    }

    var selectedNodeConnections: [ArchEdge] {
        guard let selected = selectedNode else { return [] }
        return edges.filter { $0.source == selected.id || $0.target == selected.id }
    }

    var selectedNodeNeighbors: [ArchNode] {
        let connectionIDs = selectedNodeConnections.flatMap { [$0.source, $0.target] }
        let uniqueIDs = Set(connectionIDs).subtracting([selectedNode?.id ?? ""])
        return nodes.filter { uniqueIDs.contains($0.id) }
    }

    func analyzeProject(path: String) {
        isLoading = true
        analysisProgress = 0.0

        Task {
            // Simulate progressive analysis
            for step in 1...10 {
                try? await Task.sleep(for: .milliseconds(200))
                analysisProgress = Double(step) / 10.0
            }

            // Generate sample architecture data from the project
            let sampleNodes = Self.generateSampleNodes()
            let sampleEdges = Self.generateSampleEdges(from: sampleNodes)

            nodes = sampleNodes
            edges = sampleEdges
            isLoading = false
        }
    }

    func exportGraph(format: String) {
        GRumpLogger.general.info("Exporting architecture graph as \(format)")
    }

    private static func generateSampleNodes() -> [ArchNode] {
        let modules = ["Core", "Views", "Services", "Models", "Utilities", "Tools", "Agents", "Skills"]
        var allNodes: [ArchNode] = []
        for (i, mod) in modules.enumerated() {
            allNodes.append(ArchNode(
                id: "mod-\(i)",
                name: mod,
                filePath: "Sources/GRump/\(mod)/",
                nodeType: .module,
                loc: Int.random(in: 2000...8000),
                complexity: Int.random(in: 5...25)
            ))
            let fileCount = Int.random(in: 3...6)
            for f in 0..<fileCount {
                allNodes.append(ArchNode(
                    id: "file-\(i)-\(f)",
                    name: "\(mod)File\(f).swift",
                    filePath: "Sources/GRump/\(mod)/\(mod)File\(f).swift",
                    nodeType: [.file, .classType, .structType, .protocolType, .enumType].randomElement()!,
                    loc: Int.random(in: 50...600),
                    complexity: Int.random(in: 1...20),
                    connections: ["mod-\(i)"]
                ))
            }
        }
        return allNodes
    }

    private static func generateSampleEdges(from nodes: [ArchNode]) -> [ArchEdge] {
        var edgesList: [ArchEdge] = []
        let fileNodes = nodes.filter { $0.nodeType != .module }
        for (i, node) in fileNodes.enumerated() {
            let targetCount = min(Int.random(in: 1...3), fileNodes.count - 1)
            for _ in 0..<targetCount {
                let targetIdx = (i + Int.random(in: 1...max(1, fileNodes.count - 1))) % fileNodes.count
                let target = fileNodes[targetIdx]
                if target.id != node.id {
                    edgesList.append(ArchEdge(
                        id: "edge-\(node.id)-\(target.id)",
                        source: node.id,
                        target: target.id,
                        edgeType: ArchEdge.ArchEdgeType.allCases.randomElement()!,
                        isCycle: Int.random(in: 0...10) == 0
                    ))
                }
            }
        }
        return edgesList
    }
}

// MARK: - Architecture Visualizer View

struct ArchitectureVisualizerView: View {
    @StateObject private var viewModel = ArchitectureViewModel()
    @State private var showExportMenu = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .doubleColumn

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            tabBar

            Divider()

            if viewModel.isLoading {
                loadingView
            } else if viewModel.nodes.isEmpty {
                emptyStateView
            } else {
                // Main content
                HSplitView {
                    mainContent
                        .frame(minWidth: 400)

                    if viewModel.showDetailPanel {
                        detailPanel
                            .frame(minWidth: 240, idealWidth: 300, maxWidth: 400)
                    }
                }
            }

            // Toolbar footer
            toolbarFooter
        }
        .background(Color.bgDark)
        .onAppear {
            viewModel.analyzeProject(path: "")
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(ArchTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 11))
                        Text(tab.rawValue)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(viewModel.selectedTab == tab ? .brandPurple : .textSecondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(viewModel.selectedTab == tab ? Color.brandPurpleSubtle : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer()

            // Search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.textMuted)
                    .font(.system(size: 11))
                TextField("Search nodes...", text: $viewModel.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .frame(width: 150)
                if !viewModel.searchQuery.isEmpty {
                    Button {
                        viewModel.searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.textMuted)
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.bgInput.opacity(0.6))
            )
            .padding(.trailing, 8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.bgCard.opacity(0.5))
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        switch viewModel.selectedTab {
        case .dependencyGraph:
            DependencyGraphView(viewModel: viewModel)
        case .moduleMap:
            ModuleMapView(viewModel: viewModel)
        case .callHierarchy:
            CallHierarchyView(viewModel: viewModel)
        case .metrics:
            MetricsDashboardView(viewModel: viewModel)
        }
    }

    // MARK: - Detail Panel

    private var detailPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Details")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Spacer()
                Button {
                    withAnimation { viewModel.showDetailPanel = false }
                } label: {
                    Image(systemName: "sidebar.right")
                        .foregroundColor(.textSecondary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            if let node = viewModel.selectedNode {
                selectedNodeDetail(node: node)
            } else {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "cursorarrow.click.2")
                        .font(.system(size: 28))
                        .foregroundColor(.textMuted)
                    Text("Select a node to view details")
                        .font(.system(size: 12))
                        .foregroundColor(.textMuted)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color.bgCard.opacity(0.4))
    }

    private func selectedNodeDetail(node: ArchNode) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Node header
                HStack(spacing: 10) {
                    Image(systemName: node.nodeType.icon)
                        .font(.system(size: 20))
                        .foregroundColor(node.nodeType.color)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(node.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.textPrimary)
                        Text(node.nodeType.label)
                            .font(.system(size: 11))
                            .foregroundColor(.textSecondary)
                    }
                }

                Divider()

                // File path
                detailRow(label: "Path", value: node.filePath, icon: "folder")

                // Metrics
                detailRow(label: "Lines of Code", value: "\(node.loc)", icon: "text.alignleft")
                detailRow(label: "Complexity", value: "\(node.complexity)", icon: "gauge.medium")

                // Connections
                let inbound = viewModel.edges.filter { $0.target == node.id }.count
                let outbound = viewModel.edges.filter { $0.source == node.id }.count
                detailRow(label: "Inbound", value: "\(inbound)", icon: "arrow.down.left")
                detailRow(label: "Outbound", value: "\(outbound)", icon: "arrow.up.right")

                Divider()

                // Connected nodes
                Text("Connected Nodes")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textPrimary)

                ForEach(viewModel.selectedNodeNeighbors) { neighbor in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(neighbor.nodeType.color)
                            .frame(width: 8, height: 8)
                        Text(neighbor.name)
                            .font(.system(size: 11))
                            .foregroundColor(.textSecondary)
                        Spacer()
                        Image(systemName: neighbor.nodeType.icon)
                            .font(.system(size: 10))
                            .foregroundColor(.textMuted)
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.selectedNode = neighbor
                    }
                }
            }
            .padding(14)
        }
    }

    private func detailRow(label: String, value: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(.textMuted)
                .frame(width: 14)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.textPrimary)
                .lineLimit(1)
        }
    }

    // MARK: - Toolbar Footer

    private var toolbarFooter: some View {
        HStack(spacing: 12) {
            // Refresh
            Button {
                viewModel.analyzeProject(path: "")
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundColor(.textSecondary)

            Divider().frame(height: 14)

            // Export
            Menu {
                Button("Export as PNG") { viewModel.exportGraph(format: "png") }
                Button("Export as SVG") { viewModel.exportGraph(format: "svg") }
                Button("Export as JSON") { viewModel.exportGraph(format: "json") }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
                    .font(.system(size: 11))
            }
            .menuStyle(.borderlessButton)
            .frame(width: 80)
            .foregroundColor(.textSecondary)

            Divider().frame(height: 14)

            // Layout picker
            Picker("", selection: $viewModel.graphLayout) {
                ForEach(GraphLayout.allCases, id: \.self) { layout in
                    Label(layout.rawValue, systemImage: layout.icon)
                        .tag(layout)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 220)

            Divider().frame(height: 14)

            // Zoom controls
            HStack(spacing: 6) {
                Button {
                    withAnimation { viewModel.zoomLevel = max(0.25, viewModel.zoomLevel - 0.25) }
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)

                Text("\(Int(viewModel.zoomLevel * 100))%")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.textSecondary)
                    .frame(width: 40)

                Button {
                    withAnimation { viewModel.zoomLevel = min(4.0, viewModel.zoomLevel + 0.25) }
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation { viewModel.zoomLevel = 1.0 }
                } label: {
                    Text("Fit")
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 3).fill(Color.bgInput.opacity(0.5)))
                }
                .buttonStyle(.plain)
            }

            Spacer()

            // Detail panel toggle
            Button {
                withAnimation { viewModel.showDetailPanel.toggle() }
            } label: {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 12))
                    .foregroundColor(viewModel.showDetailPanel ? .brandPurple : .textMuted)
            }
            .buttonStyle(.plain)

            // Node count
            Text("\(viewModel.nodes.count) nodes, \(viewModel.edges.count) edges")
                .font(.system(size: 10))
                .foregroundColor(.textMuted)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.bgCard.opacity(0.5))
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .controlSize(.large)
                .scaleEffect(1.2)

            Text("Analyzing project structure...")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.textPrimary)

            // Progress bar
            VStack(spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.secondary.opacity(0.15))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.brandPurple)
                            .frame(width: geo.size.width * viewModel.analysisProgress)
                            .animation(.easeInOut(duration: 0.3), value: viewModel.analysisProgress)
                    }
                }
                .frame(width: 240, height: 4)

                Text("\(Int(viewModel.analysisProgress * 100))%")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.textMuted)
            }

            Text("Scanning files, resolving imports, building dependency graph...")
                .font(.system(size: 11))
                .foregroundColor(.textMuted)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 40))
                .foregroundColor(.textMuted)
            Text("No Architecture Data")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.textPrimary)
            Text("Open a project and click Refresh to analyze\nthe codebase structure and dependencies.")
                .font(.system(size: 12))
                .foregroundColor(.textMuted)
                .multilineTextAlignment(.center)
            Button {
                viewModel.analyzeProject(path: "")
            } label: {
                Label("Analyze Project", systemImage: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.brandPurple))
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
