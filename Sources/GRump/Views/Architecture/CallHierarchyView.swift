import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - Call Hierarchy Models

struct CallNode: Identifiable, Hashable {
    let id: String
    var name: String
    var filePath: String
    var lineNumber: Int
    var callCount: Int
    var symbolType: SymbolType
    var children: [CallNode]
    var isRecursive: Bool = false
    var isExpanded: Bool = false
    var depth: Int = 0

    enum SymbolType: String, CaseIterable, Hashable {
        case function, method, initializer, closure, property, subscriptOp

        var icon: String {
            switch self {
            case .function: return "f.square"
            case .method: return "m.square"
            case .initializer: return "arrow.up.square"
            case .closure: return "curlybraces.square"
            case .property: return "p.square"
            case .subscriptOp: return "number.square"
            }
        }

        var color: Color {
            switch self {
            case .function: return Color(red: 0.30, green: 0.55, blue: 0.95)
            case .method: return Color.brandPurple
            case .initializer: return Color.accentGreen
            case .closure: return Color.accentOrange
            case .property: return Color(red: 0.60, green: 0.60, blue: 0.65)
            case .subscriptOp: return Color(red: 0.85, green: 0.35, blue: 0.50)
            }
        }

        var label: String {
            switch self {
            case .function: return "Function"
            case .method: return "Method"
            case .initializer: return "Initializer"
            case .closure: return "Closure"
            case .property: return "Property"
            case .subscriptOp: return "Subscript"
            }
        }
    }

    var totalDescendants: Int {
        children.reduce(0) { $0 + 1 + $1.totalDescendants }
    }

    static func == (lhs: CallNode, rhs: CallNode) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum HierarchyDirection: String, CaseIterable {
    case callees = "Callees"
    case callers = "Callers"

    var icon: String {
        switch self {
        case .callees: return "arrow.down.right"
        case .callers: return "arrow.up.left"
        }
    }
}

// MARK: - Call Hierarchy ViewModel

@MainActor
final class CallHierarchyViewModel: ObservableObject {
    @Published var rootFunction: CallNode?
    @Published var direction: HierarchyDirection = .callees
    @Published var searchQuery: String = ""
    @Published var depthLimit: Int = 5
    @Published var selectedNode: CallNode?
    @Published var isLoading: Bool = false
    @Published var allFunctions: [CallNode] = []
    @Published var expandedIDs: Set<String> = []

    var filteredFunctions: [CallNode] {
        guard !searchQuery.isEmpty else { return allFunctions }
        return allFunctions.filter { $0.name.localizedCaseInsensitiveContains(searchQuery) }
    }

    func selectRootFunction(_ node: CallNode) {
        rootFunction = node
        selectedNode = node
        expandedIDs = [node.id]
        buildHierarchy()
    }

    func toggleExpansion(_ nodeID: String) {
        if expandedIDs.contains(nodeID) {
            expandedIDs.remove(nodeID)
        } else {
            expandedIDs.insert(nodeID)
        }
    }

    func buildHierarchy() {
        guard rootFunction != nil else { return }
        // In a real implementation this would query LSP or index
        // For now, we generate a sample hierarchy
    }

    func buildSampleData() {
        let symbols: [(String, CallNode.SymbolType)] = [
            ("sendMessage(_:)", .method),
            ("processToolCall(_:)", .method),
            ("streamResponse(for:)", .function),
            ("executeCommand(_:)", .function),
            ("parseMarkdown(_:)", .function),
            ("saveConversation()", .method),
            ("loadModel(named:)", .function),
            ("handleKeyEvent(_:)", .method),
            ("refreshUI()", .method),
            ("validateInput(_:)", .function),
            ("compressImage(_:quality:)", .function),
            ("fetchRemoteConfig()", .function),
            ("initializeDatabase()", .initializer),
            ("onAppear { }", .closure),
            ("tokenCount.get", .property),
        ]

        allFunctions = symbols.enumerated().map { i, sym in
            var children: [CallNode] = []
            let childCount = Int.random(in: 1...4)
            for c in 0..<childCount {
                let childSym = symbols[(i + c + 1) % symbols.count]
                var grandChildren: [CallNode] = []
                if Int.random(in: 0...2) == 0 {
                    let gc = symbols[(i + c + 3) % symbols.count]
                    grandChildren.append(CallNode(
                        id: "gc-\(i)-\(c)",
                        name: gc.0,
                        filePath: "Sources/GRump/Services/\(gc.0.prefix(8)).swift",
                        lineNumber: Int.random(in: 10...500),
                        callCount: Int.random(in: 1...20),
                        symbolType: gc.1,
                        children: [],
                        depth: 2
                    ))
                }
                children.append(CallNode(
                    id: "child-\(i)-\(c)",
                    name: childSym.0,
                    filePath: "Sources/GRump/Services/\(childSym.0.prefix(8)).swift",
                    lineNumber: Int.random(in: 10...500),
                    callCount: Int.random(in: 1...50),
                    symbolType: childSym.1,
                    children: grandChildren,
                    isRecursive: i == (i + c + 1) % symbols.count,
                    depth: 1
                ))
            }

            return CallNode(
                id: "fn-\(i)",
                name: sym.0,
                filePath: "Sources/GRump/ViewModels/\(sym.0.prefix(8)).swift",
                lineNumber: Int.random(in: 1...300),
                callCount: Int.random(in: 1...100),
                symbolType: sym.1,
                children: children,
                depth: 0
            )
        }

        if let first = allFunctions.first {
            selectRootFunction(first)
        }
    }
}

// MARK: - Call Hierarchy View

struct CallHierarchyView: View {
    @ObservedObject var viewModel: ArchitectureViewModel
    @StateObject private var hierarchyVM = CallHierarchyViewModel()

    var body: some View {
        HSplitView {
            // Left: Function picker
            functionPicker
                .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)

            // Right: Hierarchy tree
            VStack(spacing: 0) {
                hierarchyToolbar
                Divider()

                if let root = hierarchyVM.rootFunction {
                    hierarchyTree(root: root)
                } else {
                    emptyState
                }
            }
        }
        .onAppear {
            hierarchyVM.buildSampleData()
        }
    }

    // MARK: - Function Picker

    private var functionPicker: some View {
        VStack(spacing: 0) {
            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.textMuted)
                    .font(.system(size: 11))
                TextField("Find function...", text: $hierarchyVM.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !hierarchyVM.searchQuery.isEmpty {
                    Button { hierarchyVM.searchQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.textMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.bgInput.opacity(0.5))

            Divider()

            // Function list
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(hierarchyVM.filteredFunctions) { func_ in
                        functionRow(func_)
                    }
                }
                .padding(.vertical, 4)
            }

            Divider()

            // Summary
            HStack {
                Text("\(hierarchyVM.allFunctions.count) symbols")
                    .font(.system(size: 10))
                    .foregroundColor(.textMuted)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.bgCard.opacity(0.3))
        }
        .background(Color.bgCard.opacity(0.2))
    }

    private func functionRow(_ node: CallNode) -> some View {
        let isSelected = hierarchyVM.rootFunction?.id == node.id

        return HStack(spacing: 8) {
            Image(systemName: node.symbolType.icon)
                .font(.system(size: 12))
                .foregroundColor(node.symbolType.color)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(node.name)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular, design: .monospaced))
                    .foregroundColor(isSelected ? .brandPurple : .textPrimary)
                    .lineLimit(1)
                Text(node.filePath)
                    .font(.system(size: 9))
                    .foregroundColor(.textMuted)
                    .lineLimit(1)
            }

            Spacer()

            // Fan-out badge
            if !node.children.isEmpty {
                Text("\(node.children.count)")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.textSecondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.secondary.opacity(0.12))
                    )
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isSelected ? Color.brandPurpleSubtle : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            hierarchyVM.selectRootFunction(node)
        }
    }

    // MARK: - Hierarchy Toolbar

    private var hierarchyToolbar: some View {
        HStack(spacing: 12) {
            // Direction picker
            Picker("", selection: $hierarchyVM.direction) {
                ForEach(HierarchyDirection.allCases, id: \.self) { dir in
                    Label(dir.rawValue, systemImage: dir.icon)
                        .tag(dir)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 180)

            Divider().frame(height: 14)

            // Depth limit
            HStack(spacing: 6) {
                Text("Depth:")
                    .font(.system(size: 11))
                    .foregroundColor(.textSecondary)
                Slider(
                    value: Binding(
                        get: { Double(hierarchyVM.depthLimit) },
                        set: { hierarchyVM.depthLimit = Int($0) }
                    ),
                    in: 1...10,
                    step: 1
                )
                .frame(width: 100)
                Text("\(hierarchyVM.depthLimit)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.textPrimary)
                    .frame(width: 20)
            }

            Spacer()

            // Stats
            if let root = hierarchyVM.rootFunction {
                HStack(spacing: 8) {
                    Label(
                        hierarchyVM.direction == .callees ? "Fan-out: \(root.children.count)" : "Fan-in: \(root.children.count)",
                        systemImage: hierarchyVM.direction == .callees ? "arrow.down.right" : "arrow.up.left"
                    )
                    .font(.system(size: 10))
                    .foregroundColor(.textMuted)

                    Label(
                        "Total: \(root.totalDescendants)",
                        systemImage: "sum"
                    )
                    .font(.system(size: 10))
                    .foregroundColor(.textMuted)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.bgCard.opacity(0.3))
    }

    // MARK: - Hierarchy Tree

    private func hierarchyTree(root: CallNode) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                hierarchyRow(node: root, depth: 0)
            }
            .padding(.vertical, 4)
        }
    }

    private func hierarchyRow(node: CallNode, depth: Int) -> some View {
        let isExpanded = hierarchyVM.expandedIDs.contains(node.id)
        let isSelected = hierarchyVM.selectedNode?.id == node.id
        let withinDepthLimit = depth < hierarchyVM.depthLimit

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                // Indentation with tree lines
                ForEach(0..<depth, id: \.self) { level in
                    Rectangle()
                        .fill(Color.borderSubtle.opacity(0.3))
                        .frame(width: 1)
                        .padding(.leading, 20)
                }

                // Expand/collapse toggle
                if !node.children.isEmpty && withinDepthLimit {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            hierarchyVM.toggleExpansion(node.id)
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.textMuted)
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                } else {
                    Spacer().frame(width: 16)
                }

                // Symbol icon
                Image(systemName: node.symbolType.icon)
                    .font(.system(size: 13))
                    .foregroundColor(node.symbolType.color)
                    .frame(width: 18)
                    .padding(.leading, 4)

                // Function name
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(node.name)
                            .font(.system(size: 12, weight: isSelected ? .semibold : .regular, design: .monospaced))
                            .foregroundColor(node.isRecursive ? .accentOrange : (isSelected ? .brandPurple : .textPrimary))
                            .lineLimit(1)

                        // Recursive badge
                        if node.isRecursive {
                            Text("RECURSIVE")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.accentOrange)
                                )
                        }
                    }

                    HStack(spacing: 8) {
                        Text(node.filePath)
                            .font(.system(size: 9))
                            .foregroundColor(.textMuted)
                            .lineLimit(1)
                        Text(":\(node.lineNumber)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.textMuted)
                    }
                }
                .padding(.leading, 4)

                Spacer()

                // Call count
                HStack(spacing: 4) {
                    Image(systemName: "arrow.right.arrow.left")
                        .font(.system(size: 8))
                        .foregroundColor(.textMuted)
                    Text("\(node.callCount)x")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.textSecondary)
                }
                .padding(.trailing, 4)

                // Children count badge
                if !node.children.isEmpty {
                    Text("\(node.children.count)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 20, height: 16)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(node.symbolType.color.opacity(0.6))
                        )
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isSelected ? Color.brandPurpleSubtle : Color.clear)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                hierarchyVM.selectedNode = node
            }

            // Children
            if isExpanded && withinDepthLimit {
                ForEach(node.children) { child in
                    hierarchyRow(node: child, depth: depth + 1)
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 32))
                .foregroundColor(.textMuted)
            Text("Select a function to explore")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.textPrimary)
            Text("Choose a function from the list on the left to see\nits call hierarchy — callers or callees.")
                .font(.system(size: 12))
                .foregroundColor(.textMuted)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
