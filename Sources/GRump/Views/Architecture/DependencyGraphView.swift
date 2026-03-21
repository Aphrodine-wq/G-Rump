import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - Force Simulation

@MainActor
final class ForceSimulation: ObservableObject {
    struct SimNode: Identifiable {
        let id: String
        var x: CGFloat
        var y: CGFloat
        var vx: CGFloat = 0
        var vy: CGFloat = 0
        var fx: CGFloat = 0
        var fy: CGFloat = 0
        var radius: CGFloat = 20
        var pinned: Bool = false
    }

    struct SimEdge: Identifiable {
        let id: String
        var source: String
        var target: String
        var strength: CGFloat = 0.3
    }

    @Published var nodes: [SimNode] = []
    @Published var edges: [SimEdge] = []
    @Published var isRunning: Bool = false

    private let repulsionStrength: CGFloat = -800
    private let attractionStrength: CGFloat = 0.015
    private let centerStrength: CGFloat = 0.02
    private let damping: CGFloat = 0.92
    private let collisionRadius: CGFloat = 30

    func initialize(archNodes: [ArchNode], archEdges: [ArchEdge], bounds: CGSize) {
        let center = CGPoint(x: bounds.width / 2, y: bounds.height / 2)
        let spreadRadius = min(bounds.width, bounds.height) * 0.35

        nodes = archNodes.enumerated().map { index, node in
            let angle = CGFloat(index) / CGFloat(archNodes.count) * 2 * .pi
            let jitter = CGFloat.random(in: -50...50)
            let r = spreadRadius + jitter
            return SimNode(
                id: node.id,
                x: center.x + cos(angle) * r,
                y: center.y + sin(angle) * r,
                radius: max(12, min(30, CGFloat(node.loc) / 50.0))
            )
        }

        edges = archEdges.map { edge in
            SimEdge(id: edge.id, source: edge.source, target: edge.target, strength: 0.3)
        }
    }

    func step() {
        let nodeMap = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })

        for i in 0..<nodes.count {
            guard !nodes[i].pinned else { continue }
            nodes[i].fx = 0
            nodes[i].fy = 0

            // Repulsion: all nodes push each other apart
            for j in 0..<nodes.count where i != j {
                let dx = nodes[i].x - nodes[j].x
                let dy = nodes[i].y - nodes[j].y
                let distSq = max(dx * dx + dy * dy, 1)
                let dist = sqrt(distSq)
                let force = repulsionStrength / distSq
                nodes[i].fx += (dx / dist) * force
                nodes[i].fy += (dy / dist) * force
            }

            // Centering force
            let centerX = nodes.reduce(0) { $0 + $1.x } / CGFloat(nodes.count)
            let centerY = nodes.reduce(0) { $0 + $1.y } / CGFloat(nodes.count)
            nodes[i].fx -= (nodes[i].x - centerX) * centerStrength
            nodes[i].fy -= (nodes[i].y - centerY) * centerStrength
        }

        // Attraction: connected nodes pull together
        for edge in edges {
            guard let si = nodes.firstIndex(where: { $0.id == edge.source }),
                  let ti = nodes.firstIndex(where: { $0.id == edge.target }) else { continue }
            let dx = nodes[ti].x - nodes[si].x
            let dy = nodes[ti].y - nodes[si].y
            let dist = max(sqrt(dx * dx + dy * dy), 1)
            let force = (dist - 120) * attractionStrength * edge.strength
            let fx = (dx / dist) * force
            let fy = (dy / dist) * force
            if !nodes[si].pinned {
                nodes[si].fx += fx
                nodes[si].fy += fy
            }
            if !nodes[ti].pinned {
                nodes[ti].fx -= fx
                nodes[ti].fy -= fy
            }
        }

        // Collision detection
        for i in 0..<nodes.count {
            for j in (i + 1)..<nodes.count {
                let dx = nodes[j].x - nodes[i].x
                let dy = nodes[j].y - nodes[i].y
                let dist = max(sqrt(dx * dx + dy * dy), 1)
                let minDist = nodes[i].radius + nodes[j].radius + 8
                if dist < minDist {
                    let overlap = (minDist - dist) * 0.5
                    let pushX = (dx / dist) * overlap
                    let pushY = (dy / dist) * overlap
                    if !nodes[i].pinned {
                        nodes[i].fx -= pushX
                        nodes[i].fy -= pushY
                    }
                    if !nodes[j].pinned {
                        nodes[j].fx += pushX
                        nodes[j].fy += pushY
                    }
                }
            }
        }

        // Verlet integration
        for i in 0..<nodes.count {
            guard !nodes[i].pinned else { continue }
            nodes[i].vx = (nodes[i].vx + nodes[i].fx) * damping
            nodes[i].vy = (nodes[i].vy + nodes[i].fy) * damping
            // Clamp velocity
            let maxV: CGFloat = 20
            nodes[i].vx = max(-maxV, min(maxV, nodes[i].vx))
            nodes[i].vy = max(-maxV, min(maxV, nodes[i].vy))
            nodes[i].x += nodes[i].vx
            nodes[i].y += nodes[i].vy
        }
    }

    func runSimulation(iterations: Int) async {
        isRunning = true
        for _ in 0..<iterations {
            step()
            if iterations > 100 {
                // Let the UI breathe
                try? await Task.sleep(for: .milliseconds(1))
            }
        }
        isRunning = false
    }
}

// MARK: - Dependency Graph View

struct DependencyGraphView: View {
    @ObservedObject var viewModel: ArchitectureViewModel
    @StateObject private var simulation = ForceSimulation()
    @State private var hoveredNode: String?
    @State private var draggedNode: String?
    @State private var canvasSize: CGSize = .zero
    @State private var showLegend: Bool = true
    @State private var showMinimap: Bool = true
    @State private var hasInitialized: Bool = false

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                // Subtle grid background
                gridBackground(size: geometry.size)

                // Main canvas
                graphCanvas(size: geometry.size)
                    .scaleEffect(viewModel.zoomLevel)
                    .offset(viewModel.panOffset)
                    .gesture(panGesture)
                    .gesture(zoomGesture)

                // Legend overlay
                if showLegend {
                    legendOverlay
                        .padding(12)
                }

                // Minimap
                if showMinimap {
                    minimapView(size: geometry.size)
                        .frame(width: 160, height: 120)
                        .position(x: geometry.size.width - 92, y: geometry.size.height - 72)
                }

                // Simulation indicator
                if simulation.isRunning {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Laying out...")
                            .font(.system(size: 10))
                            .foregroundColor(.textMuted)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.bgCard.opacity(0.9))
                    )
                    .position(x: geometry.size.width / 2, y: 20)
                }
            }
            .onAppear {
                canvasSize = geometry.size
                if !hasInitialized {
                    initializeSimulation(size: geometry.size)
                    hasInitialized = true
                }
            }
            .onChange(of: geometry.size) { _, newSize in
                canvasSize = newSize
            }
        }
        .clipped()
    }

    // MARK: - Grid Background

    private func gridBackground(size: CGSize) -> some View {
        Canvas { context, canvasSize in
            let gridSpacing: CGFloat = 40
            let gridColor = Color.secondary.opacity(0.06)

            // Vertical lines
            var x: CGFloat = 0
            while x < canvasSize.width {
                let path = Path { p in
                    p.move(to: CGPoint(x: x, y: 0))
                    p.addLine(to: CGPoint(x: x, y: canvasSize.height))
                }
                context.stroke(path, with: .color(gridColor), lineWidth: 0.5)
                x += gridSpacing
            }

            // Horizontal lines
            var y: CGFloat = 0
            while y < canvasSize.height {
                let path = Path { p in
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: canvasSize.width, y: y))
                }
                context.stroke(path, with: .color(gridColor), lineWidth: 0.5)
                y += gridSpacing
            }
        }
    }

    // MARK: - Graph Canvas

    private func graphCanvas(size: CGSize) -> some View {
        Canvas { context, canvasSize in
            let nodeMap = Dictionary(uniqueKeysWithValues: simulation.nodes.map { ($0.id, $0) })
            let archNodeMap = Dictionary(uniqueKeysWithValues: viewModel.nodes.map { ($0.id, $0) })
            let searchActive = !viewModel.searchQuery.isEmpty
            let matchingIDs = Set(viewModel.filteredNodes.map(\.id))

            // Draw edges
            for edge in simulation.edges {
                guard let sourceNode = nodeMap[edge.source],
                      let targetNode = nodeMap[edge.target],
                      let archEdge = viewModel.edges.first(where: { $0.id == edge.id }) else { continue }

                let from = CGPoint(x: sourceNode.x, y: sourceNode.y)
                let to = CGPoint(x: targetNode.x, y: targetNode.y)

                let dx = to.x - from.x
                let dy = to.y - from.y
                let dist = sqrt(dx * dx + dy * dy)
                guard dist > 1 else { continue }

                // Bezier control point for curved edges
                let midX = (from.x + to.x) / 2
                let midY = (from.y + to.y) / 2
                let perpX = -(dy / dist) * 20
                let perpY = (dx / dist) * 20
                let control = CGPoint(x: midX + perpX, y: midY + perpY)

                var edgePath = Path()
                edgePath.move(to: from)
                edgePath.addQuadCurve(to: to, control: control)

                let edgeOpacity: CGFloat = searchActive ? (matchingIDs.contains(edge.source) || matchingIDs.contains(edge.target) ? 0.8 : 0.1) : 0.5

                if archEdge.isCycle {
                    // Cycle: red dashed
                    context.stroke(
                        edgePath,
                        with: .color(Color.red.opacity(edgeOpacity)),
                        style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                    )
                } else {
                    context.stroke(
                        edgePath,
                        with: .color(archEdge.edgeType.color.opacity(edgeOpacity)),
                        lineWidth: 1.5
                    )
                }

                // Arrowhead
                let arrowLen: CGFloat = 8
                let angle = atan2(to.y - control.y, to.x - control.x)
                let arrowP1 = CGPoint(
                    x: to.x - arrowLen * cos(angle - .pi / 6),
                    y: to.y - arrowLen * sin(angle - .pi / 6)
                )
                let arrowP2 = CGPoint(
                    x: to.x - arrowLen * cos(angle + .pi / 6),
                    y: to.y - arrowLen * sin(angle + .pi / 6)
                )
                var arrowPath = Path()
                arrowPath.move(to: to)
                arrowPath.addLine(to: arrowP1)
                arrowPath.addLine(to: arrowP2)
                arrowPath.closeSubpath()
                context.fill(
                    arrowPath,
                    with: .color(archEdge.isCycle ? Color.red.opacity(edgeOpacity) : archEdge.edgeType.color.opacity(edgeOpacity))
                )
            }

            // Draw nodes
            for simNode in simulation.nodes {
                guard let archNode = archNodeMap[simNode.id] else { continue }

                let isSelected = viewModel.selectedNode?.id == simNode.id
                let isHovered = hoveredNode == simNode.id
                let isSearchMatch = searchActive && matchingIDs.contains(simNode.id)
                let nodeOpacity: CGFloat = searchActive ? (isSearchMatch ? 1.0 : 0.3) : 1.0
                let radius = simNode.radius

                let rect = CGRect(
                    x: simNode.x - radius,
                    y: simNode.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )

                // Search glow
                if isSearchMatch {
                    let glowRect = rect.insetBy(dx: -6, dy: -6)
                    let glowPath = RoundedRectangle(cornerRadius: 8).path(in: glowRect)
                    context.fill(glowPath, with: .color(Color.yellow.opacity(0.3)))
                }

                // Selection ring
                if isSelected {
                    let selRect = rect.insetBy(dx: -4, dy: -4)
                    let selPath = RoundedRectangle(cornerRadius: 7).path(in: selRect)
                    context.stroke(selPath, with: .color(Color.brandPurple), lineWidth: 2.5)
                }

                // Hover glow
                if isHovered {
                    let hoverRect = rect.insetBy(dx: -3, dy: -3)
                    let hoverPath = RoundedRectangle(cornerRadius: 7).path(in: hoverRect)
                    context.fill(hoverPath, with: .color(archNode.nodeType.color.opacity(0.2)))
                }

                // Node body
                let nodePath = RoundedRectangle(cornerRadius: 6).path(in: rect)
                context.fill(nodePath, with: .color(archNode.nodeType.color.opacity(nodeOpacity * 0.85)))

                // Node border
                context.stroke(nodePath, with: .color(archNode.nodeType.color.opacity(nodeOpacity)), lineWidth: 1.5)

                // Node label
                let label = Text(archNode.name)
                    .font(.system(size: max(8, min(11, radius * 0.5))))
                    .foregroundColor(.white.opacity(nodeOpacity))
                let resolvedLabel = context.resolve(label)
                let labelSize = resolvedLabel.measure(in: CGSize(width: radius * 2.5, height: 20))
                context.draw(resolvedLabel, at: CGPoint(x: simNode.x, y: simNode.y + radius + 10))

                // Connection count badge
                let connCount = viewModel.edges.filter { $0.source == simNode.id || $0.target == simNode.id }.count
                if connCount > 0 && radius > 14 {
                    let badge = Text("\(connCount)")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                    let resolvedBadge = context.resolve(badge)
                    let badgePos = CGPoint(x: simNode.x + radius - 4, y: simNode.y - radius + 4)
                    let badgeRect = CGRect(x: badgePos.x - 7, y: badgePos.y - 7, width: 14, height: 14)
                    let badgePath = Circle().path(in: badgeRect)
                    context.fill(badgePath, with: .color(Color(red: 0.3, green: 0.3, blue: 0.35)))
                    context.draw(resolvedBadge, at: badgePos)
                }
            }
        }
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                let adjustedLoc = adjustForTransform(location)
                hoveredNode = hitTest(at: adjustedLoc)
            case .ended:
                hoveredNode = nil
            }
        }
        .onTapGesture { location in
            let adjustedLoc = adjustForTransform(location)
            if let nodeID = hitTest(at: adjustedLoc) {
                viewModel.selectedNode = viewModel.nodes.first { $0.id == nodeID }
            } else {
                viewModel.selectedNode = nil
            }
        }
        .gesture(
            DragGesture(minimumDistance: 5)
                .onChanged { value in
                    let adjustedStart = adjustForTransform(value.startLocation)
                    if draggedNode == nil {
                        draggedNode = hitTest(at: adjustedStart)
                        if let id = draggedNode, let idx = simulation.nodes.firstIndex(where: { $0.id == id }) {
                            simulation.nodes[idx].pinned = true
                        }
                    }
                    if let id = draggedNode, let idx = simulation.nodes.firstIndex(where: { $0.id == id }) {
                        let adjustedCurrent = adjustForTransform(value.location)
                        simulation.nodes[idx].x = adjustedCurrent.x
                        simulation.nodes[idx].y = adjustedCurrent.y
                    }
                }
                .onEnded { _ in
                    if let id = draggedNode, let idx = simulation.nodes.firstIndex(where: { $0.id == id }) {
                        simulation.nodes[idx].pinned = false
                    }
                    draggedNode = nil
                }
        )
    }

    // MARK: - Legend Overlay

    private var legendOverlay: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Legend")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.textSecondary)
                Spacer()
                Button {
                    withAnimation { showLegend.toggle() }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8))
                        .foregroundColor(.textMuted)
                }
                .buttonStyle(.plain)
            }

            // Node types
            Text("Nodes")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.textMuted)
            ForEach(ArchNode.ArchNodeType.allCases, id: \.self) { type in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(type.color)
                        .frame(width: 12, height: 12)
                    Text(type.label)
                        .font(.system(size: 9))
                        .foregroundColor(.textSecondary)
                }
            }

            Divider().opacity(0.3)

            // Edge types
            Text("Edges")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.textMuted)
            ForEach(ArchEdge.ArchEdgeType.allCases, id: \.self) { type in
                HStack(spacing: 6) {
                    Rectangle()
                        .fill(type.color)
                        .frame(width: 16, height: 2)
                    Text(type.label)
                        .font(.system(size: 9))
                        .foregroundColor(.textSecondary)
                }
            }
            HStack(spacing: 6) {
                Path { p in
                    p.move(to: CGPoint(x: 0, y: 1))
                    p.addLine(to: CGPoint(x: 16, y: 1))
                }
                .stroke(Color.red, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                .frame(width: 16, height: 2)
                Text("Cycle")
                    .font(.system(size: 9))
                    .foregroundColor(.textSecondary)
            }
        }
        .padding(10)
        .frame(width: 130)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.bgCard.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.borderSubtle.opacity(0.5), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Minimap

    private func minimapView(size: CGSize) -> some View {
        let archNodeMap = Dictionary(uniqueKeysWithValues: viewModel.nodes.map { ($0.id, $0) })

        return Canvas { context, canvasSize in
            // Background
            let bgPath = RoundedRectangle(cornerRadius: 6).path(in: CGRect(origin: .zero, size: canvasSize))
            context.fill(bgPath, with: .color(Color.bgDark.opacity(0.85)))
            context.stroke(bgPath, with: .color(Color.borderSubtle.opacity(0.4)), lineWidth: 0.5)

            guard !simulation.nodes.isEmpty else { return }

            // Calculate bounds
            let minX = simulation.nodes.map(\.x).min() ?? 0
            let maxX = simulation.nodes.map(\.x).max() ?? 1
            let minY = simulation.nodes.map(\.y).min() ?? 0
            let maxY = simulation.nodes.map(\.y).max() ?? 1
            let rangeX = max(maxX - minX, 1)
            let rangeY = max(maxY - minY, 1)
            let padding: CGFloat = 10

            func miniPos(_ node: ForceSimulation.SimNode) -> CGPoint {
                CGPoint(
                    x: padding + (node.x - minX) / rangeX * (canvasSize.width - padding * 2),
                    y: padding + (node.y - minY) / rangeY * (canvasSize.height - padding * 2)
                )
            }

            // Draw edges as thin lines
            for edge in simulation.edges {
                guard let s = simulation.nodes.first(where: { $0.id == edge.source }),
                      let t = simulation.nodes.first(where: { $0.id == edge.target }) else { continue }
                var path = Path()
                path.move(to: miniPos(s))
                path.addLine(to: miniPos(t))
                context.stroke(path, with: .color(Color.secondary.opacity(0.2)), lineWidth: 0.5)
            }

            // Draw nodes as dots
            for simNode in simulation.nodes {
                let pos = miniPos(simNode)
                let nodeColor = archNodeMap[simNode.id]?.nodeType.color ?? Color.secondary
                let dotSize: CGFloat = 3
                let dotRect = CGRect(x: pos.x - dotSize / 2, y: pos.y - dotSize / 2, width: dotSize, height: dotSize)
                context.fill(Circle().path(in: dotRect), with: .color(nodeColor))
            }

            // Viewport rectangle
            let vpW = canvasSize.width / viewModel.zoomLevel * 0.5
            let vpH = canvasSize.height / viewModel.zoomLevel * 0.5
            let vpX = canvasSize.width / 2 - vpW / 2 - viewModel.panOffset.width * 0.1
            let vpY = canvasSize.height / 2 - vpH / 2 - viewModel.panOffset.height * 0.1
            let vpRect = CGRect(x: vpX, y: vpY, width: vpW, height: vpH)
            let vpPath = RoundedRectangle(cornerRadius: 2).path(in: vpRect)
            context.stroke(vpPath, with: .color(Color.brandPurple.opacity(0.5)), lineWidth: 1)
        }
    }

    // MARK: - Helpers

    private func initializeSimulation(size: CGSize) {
        simulation.initialize(archNodes: viewModel.nodes, archEdges: viewModel.edges, bounds: size)
        Task {
            await simulation.runSimulation(iterations: 200)
        }
    }

    private func adjustForTransform(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: (point.x - viewModel.panOffset.width) / viewModel.zoomLevel,
            y: (point.y - viewModel.panOffset.height) / viewModel.zoomLevel
        )
    }

    private func hitTest(at point: CGPoint) -> String? {
        for node in simulation.nodes {
            let dx = point.x - node.x
            let dy = point.y - node.y
            if dx * dx + dy * dy <= node.radius * node.radius {
                return node.id
            }
        }
        return nil
    }

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard draggedNode == nil, hitTest(at: adjustForTransform(value.startLocation)) == nil else { return }
                viewModel.panOffset = CGSize(
                    width: value.translation.width,
                    height: value.translation.height
                )
            }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let newZoom = max(0.25, min(4.0, value.magnification))
                viewModel.zoomLevel = newZoom
            }
    }
}
