import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - Treemap Models

struct TreemapNode: Identifiable, Hashable {
    let id: String
    var name: String
    var loc: Int
    var complexity: Double
    var children: [TreemapNode]
    var filePath: String

    var isLeaf: Bool { children.isEmpty }
    var totalLOC: Int {
        if isLeaf { return loc }
        return children.reduce(0) { $0 + $1.totalLOC }
    }

    var complexityGrade: String {
        if complexity < 5 { return "A" }
        if complexity < 10 { return "B" }
        if complexity < 15 { return "C" }
        if complexity < 25 { return "D" }
        return "F"
    }

    var complexityColor: Color {
        if complexity < 5 { return Color.accentGreen }
        if complexity < 10 { return Color(red: 0.55, green: 0.78, blue: 0.25) }
        if complexity < 15 { return Color(red: 0.90, green: 0.75, blue: 0.20) }
        if complexity < 25 { return Color.accentOrange }
        return Color(red: 0.90, green: 0.30, blue: 0.25) }

    static func == (lhs: TreemapNode, rhs: TreemapNode) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct TreemapRect: Identifiable {
    let id: String
    var node: TreemapNode
    var rect: CGRect
}

// MARK: - Treemap Layout Algorithm

struct TreemapLayoutEngine {
    /// Squarified treemap layout
    static func layout(nodes: [TreemapNode], in rect: CGRect) -> [TreemapRect] {
        guard !nodes.isEmpty else { return [] }
        let totalArea = rect.width * rect.height
        let totalLOC = CGFloat(nodes.reduce(0) { $0 + $1.totalLOC })
        guard totalLOC > 0 else { return [] }

        let sorted = nodes.sorted { $0.totalLOC > $1.totalLOC }
        var results: [TreemapRect] = []
        var remaining = sorted
        var currentRect = rect

        while !remaining.isEmpty {
            let isWide = currentRect.width >= currentRect.height

            // Find best row
            var row: [TreemapNode] = []
            var bestAspect: CGFloat = .infinity

            for i in 0..<remaining.count {
                let candidate = Array(remaining[0...i])
                let rowLOC = CGFloat(candidate.reduce(0) { $0 + $1.totalLOC })
                let rowFraction = rowLOC / totalLOC
                let rowSize = isWide ? currentRect.height : currentRect.width

                let worstAspect = candidate.map { node -> CGFloat in
                    let nodeFraction = CGFloat(node.totalLOC) / rowLOC
                    let nodeWidth = isWide ? (totalArea * rowFraction / currentRect.height) : (rowSize * nodeFraction)
                    let nodeHeight = isWide ? (rowSize * nodeFraction) : (totalArea * rowFraction / currentRect.width)
                    guard nodeWidth > 0 && nodeHeight > 0 else { return CGFloat.infinity }
                    return max(nodeWidth / nodeHeight, nodeHeight / nodeWidth)
                }.max() ?? .infinity

                if worstAspect <= bestAspect {
                    bestAspect = worstAspect
                    row = candidate
                } else {
                    break
                }
            }

            if row.isEmpty { row = [remaining[0]] }

            // Layout row
            let rowLOC = CGFloat(row.reduce(0) { $0 + $1.totalLOC })
            let rowFraction = rowLOC / max(totalLOC, 1)

            if isWide {
                let rowWidth = currentRect.width * rowFraction
                var y = currentRect.minY
                for node in row {
                    let nodeFraction = CGFloat(node.totalLOC) / max(rowLOC, 1)
                    let nodeHeight = currentRect.height * nodeFraction
                    let nodeRect = CGRect(x: currentRect.minX, y: y, width: rowWidth, height: nodeHeight)
                    results.append(TreemapRect(id: node.id, node: node, rect: nodeRect))
                    y += nodeHeight
                }
                currentRect = CGRect(
                    x: currentRect.minX + rowWidth,
                    y: currentRect.minY,
                    width: currentRect.width - rowWidth,
                    height: currentRect.height
                )
            } else {
                let rowHeight = currentRect.height * rowFraction
                var x = currentRect.minX
                for node in row {
                    let nodeFraction = CGFloat(node.totalLOC) / max(rowLOC, 1)
                    let nodeWidth = currentRect.width * nodeFraction
                    let nodeRect = CGRect(x: x, y: currentRect.minY, width: nodeWidth, height: rowHeight)
                    results.append(TreemapRect(id: node.id, node: node, rect: nodeRect))
                    x += nodeWidth
                }
                currentRect = CGRect(
                    x: currentRect.minX,
                    y: currentRect.minY + rowHeight,
                    width: currentRect.width,
                    height: currentRect.height - rowHeight
                )
            }

            remaining.removeFirst(row.count)
        }

        return results
    }
}

// MARK: - Module Map ViewModel

@MainActor
final class ModuleMapViewModel: ObservableObject {
    @Published var rootNode: TreemapNode?
    @Published var breadcrumb: [TreemapNode] = []
    @Published var hoveredNode: TreemapNode?
    @Published var currentLevel: TreemapNode?

    var displayNode: TreemapNode? {
        currentLevel ?? rootNode
    }

    func drillInto(_ node: TreemapNode) {
        guard !node.isLeaf else { return }
        if let current = displayNode {
            breadcrumb.append(current)
        }
        currentLevel = node
    }

    func navigateUp() {
        guard !breadcrumb.isEmpty else {
            currentLevel = nil
            return
        }
        currentLevel = breadcrumb.removeLast()
    }

    func navigateToBreadcrumb(at index: Int) {
        guard index < breadcrumb.count else { return }
        currentLevel = breadcrumb[index]
        breadcrumb = Array(breadcrumb.prefix(index))
    }

    func buildFromArchNodes(_ nodes: [ArchNode]) {
        // Group files by module
        let modules = nodes.filter { $0.nodeType == .module }
        let files = nodes.filter { $0.nodeType != .module }

        var moduleChildren: [String: [TreemapNode]] = [:]
        for file in files {
            let moduleID = file.connections.first ?? "unknown"
            let child = TreemapNode(
                id: file.id,
                name: file.name,
                loc: file.loc,
                complexity: Double(file.complexity),
                children: [],
                filePath: file.filePath
            )
            moduleChildren[moduleID, default: []].append(child)
        }

        let moduleNodes = modules.map { mod in
            TreemapNode(
                id: mod.id,
                name: mod.name,
                loc: mod.loc,
                complexity: Double(mod.complexity),
                children: moduleChildren[mod.id] ?? [],
                filePath: mod.filePath
            )
        }

        rootNode = TreemapNode(
            id: "root",
            name: "Project",
            loc: moduleNodes.reduce(0) { $0 + $1.totalLOC },
            complexity: Double(moduleNodes.reduce(0) { $0 + Int($1.complexity) }) / max(Double(moduleNodes.count), 1),
            children: moduleNodes,
            filePath: "Sources/"
        )
    }
}

// MARK: - Module Map View

struct ModuleMapView: View {
    @ObservedObject var viewModel: ArchitectureViewModel
    @StateObject private var mapVM = ModuleMapViewModel()
    @State private var tooltipNode: TreemapNode?
    @State private var tooltipPosition: CGPoint = .zero

    var body: some View {
        VStack(spacing: 0) {
            breadcrumbBar

            Divider()

            GeometryReader { geometry in
                ZStack {
                    if let displayNode = mapVM.displayNode {
                        let rects = TreemapLayoutEngine.layout(
                            nodes: displayNode.children.isEmpty ? [displayNode] : displayNode.children,
                            in: CGRect(
                                x: 4,
                                y: 4,
                                width: geometry.size.width - 8,
                                height: geometry.size.height - 8
                            )
                        )

                        ForEach(rects) { item in
                            treemapCell(item: item)
                        }

                        // Tooltip
                        if let tooltip = tooltipNode {
                            tooltipView(for: tooltip)
                                .position(tooltipPosition)
                        }
                    } else {
                        emptyState
                    }
                }
            }

            // Stats bar
            statsBar
        }
        .background(Color.bgDark)
        .onAppear {
            mapVM.buildFromArchNodes(viewModel.nodes)
        }
        .onChange(of: viewModel.nodes) { _, newNodes in
            mapVM.buildFromArchNodes(newNodes)
        }
    }

    // MARK: - Breadcrumb Bar

    private var breadcrumbBar: some View {
        HStack(spacing: 4) {
            // Root button
            Button {
                mapVM.breadcrumb.removeAll()
                mapVM.currentLevel = nil
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "house.fill")
                        .font(.system(size: 9))
                    Text("Project")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(mapVM.breadcrumb.isEmpty && mapVM.currentLevel == nil ? .brandPurple : .textSecondary)
            }
            .buttonStyle(.plain)

            ForEach(Array(mapVM.breadcrumb.enumerated()), id: \.element.id) { index, node in
                Image(systemName: "chevron.right")
                    .font(.system(size: 8))
                    .foregroundColor(.textMuted)
                Button {
                    mapVM.navigateToBreadcrumb(at: index)
                } label: {
                    Text(node.name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.textSecondary)
                }
                .buttonStyle(.plain)
            }

            if let current = mapVM.currentLevel {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8))
                    .foregroundColor(.textMuted)
                Text(current.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.brandPurple)
            }

            Spacer()

            if mapVM.currentLevel != nil {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        mapVM.navigateUp()
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.up.left")
                            .font(.system(size: 9))
                        Text("Up")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.bgCard.opacity(0.4))
    }

    // MARK: - Treemap Cell

    private func treemapCell(item: TreemapRect) -> some View {
        let isHovered = mapVM.hoveredNode?.id == item.node.id
        let canDrill = !item.node.isLeaf

        return ZStack(alignment: .topLeading) {
            // Background
            RoundedRectangle(cornerRadius: 4)
                .fill(item.node.complexityColor.opacity(isHovered ? 0.45 : 0.3))
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(item.node.complexityColor.opacity(isHovered ? 0.8 : 0.5), lineWidth: isHovered ? 2 : 1)

            // Content (only show if cell is large enough)
            if item.rect.width > 60 && item.rect.height > 40 {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        if canDrill {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        Text(item.node.name)
                            .font(.system(size: min(12, max(8, item.rect.width / 10)), weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                            .lineLimit(1)
                    }
                    if item.rect.height > 55 {
                        Text("\(item.node.totalLOC) LOC")
                            .font(.system(size: min(10, max(7, item.rect.width / 12)), design: .monospaced))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    if item.rect.height > 70 && item.rect.width > 80 {
                        HStack(spacing: 4) {
                            Text(item.node.complexityGrade)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(item.node.complexityColor.opacity(0.7))
                                )
                        }
                    }
                }
                .padding(6)
            } else if item.rect.width > 30 && item.rect.height > 20 {
                Text(String(item.node.name.prefix(3)))
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(3)
            }
        }
        .frame(width: item.rect.width, height: item.rect.height)
        .position(x: item.rect.midX, y: item.rect.midY)
        .onContinuousHover { phase in
            switch phase {
            case .active(let loc):
                mapVM.hoveredNode = item.node
                tooltipNode = item.node
                tooltipPosition = CGPoint(
                    x: item.rect.midX,
                    y: item.rect.minY - 40
                )
            case .ended:
                if mapVM.hoveredNode?.id == item.node.id {
                    mapVM.hoveredNode = nil
                    tooltipNode = nil
                }
            }
        }
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.3)) {
                mapVM.drillInto(item.node)
            }
        }
        .contextMenu {
            Button("Open in Finder") {
                #if os(macOS)
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: item.node.filePath)
                #endif
            }
            Button("View Dependencies") {
                viewModel.selectedTab = .dependencyGraph
                viewModel.searchQuery = item.node.name
            }
            Divider()
            Button("Copy Path") {
                #if os(macOS)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.node.filePath, forType: .string)
                #endif
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }

    // MARK: - Tooltip

    private func tooltipView(for node: TreemapNode) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(node.name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.textPrimary)
            HStack(spacing: 8) {
                Label("\(node.totalLOC) LOC", systemImage: "text.alignleft")
                Label("Grade: \(node.complexityGrade)", systemImage: "gauge.medium")
            }
            .font(.system(size: 9))
            .foregroundColor(.textSecondary)
            if !node.isLeaf {
                Text("\(node.children.count) children")
                    .font(.system(size: 9))
                    .foregroundColor(.textMuted)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.bgCard.opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.borderSubtle.opacity(0.5), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
        )
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "map.fill")
                .font(.system(size: 32))
                .foregroundColor(.textMuted)
            Text("No module data available")
                .font(.system(size: 13))
                .foregroundColor(.textMuted)
            Text("Analyze a project to view the module map.")
                .font(.system(size: 11))
                .foregroundColor(.textMuted)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Stats Bar

    private var statsBar: some View {
        HStack(spacing: 16) {
            if let display = mapVM.displayNode {
                Label("\(display.children.count) items", systemImage: "square.grid.2x2")
                Label("\(display.totalLOC) total LOC", systemImage: "text.alignleft")
                Label("Avg complexity: \(String(format: "%.1f", display.complexity))", systemImage: "gauge.medium")
            }
            Spacer()
        }
        .font(.system(size: 10))
        .foregroundColor(.textMuted)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.bgCard.opacity(0.3))
    }
}
