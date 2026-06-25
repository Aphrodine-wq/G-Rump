import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - Metrics Models

struct CodeMetrics {
    var totalLOC: Int = 0
    var avgComplexity: Double = 0
    var duplicationPercent: Double = 0
    var overallGrade: MetricGrade = .b

    enum MetricGrade: String, CaseIterable {
        case a = "A"
        case b = "B"
        case c = "C"
        case d = "D"
        case f = "F"

        var color: Color {
            switch self {
            case .a: return Color.accentGreen
            case .b: return Color(red: 0.55, green: 0.78, blue: 0.25)
            case .c: return Color(red: 0.90, green: 0.75, blue: 0.20)
            case .d: return Color.accentOrange
            case .f: return Color(red: 0.90, green: 0.30, blue: 0.25)
            }
        }
    }
}

struct ComplexityBucket: Identifiable {
    let id: String
    var label: String
    var count: Int
    var color: Color
}

struct HotspotFile: Identifiable {
    let id: String
    var name: String
    var loc: Int
    var complexity: Int
    var grade: CodeMetrics.MetricGrade
    var issues: Int
}

struct LanguageBreakdown: Identifiable {
    let id: String
    var name: String
    var loc: Int
    var color: Color
    var percentage: Double
}

struct TrendPoint: Identifiable {
    let id: String
    var date: Date
    var score: Double
}

enum MetricsSortField: String, CaseIterable {
    case name = "File"
    case loc = "LOC"
    case complexity = "Complexity"
    case grade = "Grade"
    case issues = "Issues"
}

// MARK: - Metrics Dashboard View

struct MetricsDashboardView: View {
    @ObservedObject var viewModel: ArchitectureViewModel
    @State private var metrics = CodeMetrics()
    @State private var complexityBuckets: [ComplexityBucket] = []
    @State private var hotspotFiles: [HotspotFile] = []
    @State private var languageBreakdown: [LanguageBreakdown] = []
    @State private var trendData: [TrendPoint] = []
    @State private var sortField: MetricsSortField = .complexity
    @State private var sortAscending: Bool = false
    @State private var selectedHotspot: HotspotFile?

    var sortedHotspots: [HotspotFile] {
        hotspotFiles.sorted { a, b in
            let result: Bool
            switch sortField {
            case .name: result = a.name < b.name
            case .loc: result = a.loc < b.loc
            case .complexity: result = a.complexity < b.complexity
            case .grade: result = a.grade.rawValue < b.grade.rawValue
            case .issues: result = a.issues < b.issues
            }
            return sortAscending ? result : !result
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Top row: 4 large metric cards
                topMetricCards

                // Complexity distribution chart
                complexityChart

                // Hotspot files table
                hotspotTable

                // Language breakdown + Trend chart side by side
                HStack(alignment: .top, spacing: 16) {
                    languagePieChart
                    trendChart
                }

                // Export button
                HStack {
                    Spacer()
                    Button {
                        exportMarkdownReport()
                    } label: {
                        Label("Export Report", systemImage: "doc.text")
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.brandPurple)
                            )
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .background(Color.bgDark)
        .onAppear {
            generateSampleMetrics()
        }
    }

    // MARK: - Top Metric Cards

    private var topMetricCards: some View {
        HStack(spacing: 12) {
            metricCard(
                title: "Total LOC",
                value: formatNumber(metrics.totalLOC),
                icon: "text.alignleft",
                color: Color(red: 0.30, green: 0.55, blue: 0.95)
            )
            metricCard(
                title: "Avg Complexity",
                value: String(format: "%.1f", metrics.avgComplexity),
                icon: "gauge.medium",
                color: metrics.avgComplexity < 10 ? .accentGreen : (metrics.avgComplexity < 20 ? .accentOrange : Color(red: 0.90, green: 0.30, blue: 0.25))
            )
            metricCard(
                title: "Duplication",
                value: String(format: "%.1f%%", metrics.duplicationPercent),
                icon: "doc.on.doc",
                color: metrics.duplicationPercent < 5 ? .accentGreen : (metrics.duplicationPercent < 15 ? .accentOrange : Color(red: 0.90, green: 0.30, blue: 0.25))
            )
            overallGradeCard
        }
    }

    private func metricCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(color)
                Spacer()
            }
            HStack(alignment: .firstTextBaseline) {
                Text(value)
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundColor(.textPrimary)
                Spacer()
            }
            HStack {
                Text(title)
                    .font(.system(size: 11))
                    .foregroundColor(.textSecondary)
                Spacer()
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.bgCard.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(color.opacity(0.2), lineWidth: 1)
                )
        )
    }

    private var overallGradeCard: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "star.fill")
                    .font(.system(size: 14))
                    .foregroundColor(metrics.overallGrade.color)
                Spacer()
            }
            HStack(alignment: .firstTextBaseline) {
                Text(metrics.overallGrade.rawValue)
                    .font(.system(size: 42, weight: .bold))
                    .foregroundColor(metrics.overallGrade.color)
                Spacer()
            }
            HStack {
                Text("Overall Grade")
                    .font(.system(size: 11))
                    .foregroundColor(.textSecondary)
                Spacer()
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.bgCard.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(metrics.overallGrade.color.opacity(0.3), lineWidth: 1.5)
                )
        )
    }

    // MARK: - Complexity Distribution Chart

    private var complexityChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Complexity Distribution")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.textPrimary)

            GeometryReader { geo in
                let maxCount = complexityBuckets.map(\.count).max() ?? 1
                let barWidth = (geo.size.width - CGFloat(complexityBuckets.count - 1) * 8) / CGFloat(complexityBuckets.count)

                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(complexityBuckets) { bucket in
                        VStack(spacing: 4) {
                            // Count label
                            Text("\(bucket.count)")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(.textSecondary)

                            // Bar
                            RoundedRectangle(cornerRadius: 4)
                                .fill(bucket.color)
                                .frame(
                                    width: barWidth,
                                    height: max(4, (geo.size.height - 40) * CGFloat(bucket.count) / CGFloat(maxCount))
                                )
                                .animation(.easeOut(duration: 0.5), value: bucket.count)

                            // Label
                            Text(bucket.label)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.textMuted)
                        }
                    }
                }
            }
            .frame(height: 160)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.bgCard.opacity(0.4))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.borderSubtle.opacity(0.3), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Hotspot Files Table

    private var hotspotTable: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Top 10 Hotspot Files")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Spacer()
                Text("\(hotspotFiles.count) files")
                    .font(.system(size: 10))
                    .foregroundColor(.textMuted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            // Header
            HStack(spacing: 0) {
                sortableHeader("File", field: .name, width: nil)
                sortableHeader("LOC", field: .loc, width: 70)
                sortableHeader("Complexity", field: .complexity, width: 90)
                sortableHeader("Grade", field: .grade, width: 60)
                sortableHeader("Issues", field: .issues, width: 60)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color.bgCard.opacity(0.3))

            Divider()

            // Rows
            ForEach(sortedHotspots) { file in
                hotspotRow(file)
                Divider().opacity(0.3)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.bgCard.opacity(0.4))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.borderSubtle.opacity(0.3), lineWidth: 0.5)
                )
        )
    }

    private func sortableHeader(_ title: String, field: MetricsSortField, width: CGFloat?) -> some View {
        Button {
            if sortField == field {
                sortAscending.toggle()
            } else {
                sortField = field
                sortAscending = false
            }
        } label: {
            HStack(spacing: 3) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(sortField == field ? .brandPurple : .textSecondary)
                if sortField == field {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(.brandPurple)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(width: width, alignment: width != nil ? .trailing : .leading)
        .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }

    private func hotspotRow(_ file: HotspotFile) -> some View {
        let isSelected = selectedHotspot?.id == file.id

        return HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.textMuted)
                Text(file.name)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(file.loc)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.textSecondary)
                .frame(width: 70, alignment: .trailing)

            // Complexity with mini bar
            HStack(spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.secondary.opacity(0.1))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(complexityBarColor(file.complexity))
                            .frame(width: geo.size.width * min(1, CGFloat(file.complexity) / 50.0))
                    }
                }
                .frame(width: 40, height: 4)

                Text("\(file.complexity)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.textSecondary)
            }
            .frame(width: 90, alignment: .trailing)

            Text(file.grade.rawValue)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(file.grade.color)
                .frame(width: 60, alignment: .trailing)

            HStack(spacing: 3) {
                if file.issues > 0 {
                    Circle()
                        .fill(file.issues > 5 ? Color(red: 0.90, green: 0.30, blue: 0.25) : Color.accentOrange)
                        .frame(width: 6, height: 6)
                }
                Text("\(file.issues)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.textSecondary)
            }
            .frame(width: 60, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(isSelected ? Color.brandPurpleSubtle : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedHotspot = file
        }
    }

    private func complexityBarColor(_ complexity: Int) -> Color {
        if complexity < 10 { return .accentGreen }
        if complexity < 20 { return Color(red: 0.90, green: 0.75, blue: 0.20) }
        if complexity < 35 { return .accentOrange }
        return Color(red: 0.90, green: 0.30, blue: 0.25)
    }

    // MARK: - Language Pie Chart

    private var languagePieChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Language Breakdown")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.textPrimary)

            HStack(spacing: 20) {
                // Pie chart
                Canvas { context, size in
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    let radius = min(size.width, size.height) / 2 - 4
                    var startAngle: Angle = .degrees(-90)

                    for lang in languageBreakdown {
                        let sweepAngle = Angle.degrees(lang.percentage / 100 * 360)
                        let endAngle = startAngle + sweepAngle
                        var path = Path()
                        path.move(to: center)
                        path.addArc(
                            center: center,
                            radius: radius,
                            startAngle: startAngle,
                            endAngle: endAngle,
                            clockwise: false
                        )
                        path.closeSubpath()
                        context.fill(path, with: .color(lang.color))

                        // Separator line
                        var sepPath = Path()
                        sepPath.move(to: center)
                        sepPath.addLine(to: CGPoint(
                            x: center.x + radius * cos(CGFloat(startAngle.radians)),
                            y: center.y + radius * sin(CGFloat(startAngle.radians))
                        ))
                        context.stroke(sepPath, with: .color(Color.bgDark), lineWidth: 1.5)

                        startAngle = endAngle
                    }

                    // Center hole (donut)
                    let innerRadius = radius * 0.55
                    let holePath = Circle().path(in: CGRect(
                        x: center.x - innerRadius,
                        y: center.y - innerRadius,
                        width: innerRadius * 2,
                        height: innerRadius * 2
                    ))
                    context.fill(holePath, with: .color(Color.bgCard.opacity(0.95)))
                }
                .frame(width: 120, height: 120)

                // Legend
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(languageBreakdown) { lang in
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(lang.color)
                                .frame(width: 10, height: 10)
                            Text(lang.name)
                                .font(.system(size: 11))
                                .foregroundColor(.textPrimary)
                            Spacer()
                            Text("\(formatNumber(lang.loc))")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.textSecondary)
                            Text("\(String(format: "%.1f", lang.percentage))%")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(.textMuted)
                                .frame(width: 42, alignment: .trailing)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.bgCard.opacity(0.4))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.borderSubtle.opacity(0.3), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Trend Chart

    private var trendChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Complexity Trend")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Spacer()
                // Trend indicator
                if let first = trendData.first, let last = trendData.last {
                    let delta = last.score - first.score
                    HStack(spacing: 4) {
                        Image(systemName: delta < -1 ? "arrow.down" : (delta > 1 ? "arrow.up" : "arrow.forward"))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(delta < -1 ? .accentGreen : (delta > 1 ? Color(red: 0.90, green: 0.30, blue: 0.25) : Color(red: 0.90, green: 0.75, blue: 0.20)))
                        Text(delta < -1 ? "Improving" : (delta > 1 ? "Declining" : "Stable"))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.textSecondary)
                    }
                }
            }

            GeometryReader { geo in
                Canvas { context, size in
                    guard trendData.count >= 2 else { return }

                    let minScore = (trendData.map(\.score).min() ?? 0) - 2
                    let maxScore = (trendData.map(\.score).max() ?? 100) + 2
                    let scoreRange = max(maxScore - minScore, 1)

                    func point(at index: Int) -> CGPoint {
                        let x = CGFloat(index) / CGFloat(trendData.count - 1) * size.width
                        let y = size.height - (CGFloat(trendData[index].score - minScore) / CGFloat(scoreRange) * size.height)
                        return CGPoint(x: x, y: y)
                    }

                    // Grid lines
                    for i in 0...4 {
                        let y = size.height * CGFloat(i) / 4
                        var gridPath = Path()
                        gridPath.move(to: CGPoint(x: 0, y: y))
                        gridPath.addLine(to: CGPoint(x: size.width, y: y))
                        context.stroke(gridPath, with: .color(Color.secondary.opacity(0.08)), lineWidth: 0.5)
                    }

                    // Area fill
                    var areaPath = Path()
                    areaPath.move(to: CGPoint(x: 0, y: size.height))
                    for i in 0..<trendData.count {
                        areaPath.addLine(to: point(at: i))
                    }
                    areaPath.addLine(to: CGPoint(x: size.width, y: size.height))
                    areaPath.closeSubpath()
                    context.fill(areaPath, with: .color(Color.brandPurple.opacity(0.08)))

                    // Line
                    var linePath = Path()
                    linePath.move(to: point(at: 0))
                    for i in 1..<trendData.count {
                        linePath.addLine(to: point(at: i))
                    }
                    context.stroke(
                        linePath,
                        with: .color(Color.brandPurple),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                    )

                    // Dots
                    for i in 0..<trendData.count {
                        let p = point(at: i)
                        let dotRect = CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)
                        context.fill(Circle().path(in: dotRect), with: .color(Color.brandPurple))
                        let innerRect = CGRect(x: p.x - 1.5, y: p.y - 1.5, width: 3, height: 3)
                        context.fill(Circle().path(in: innerRect), with: .color(Color.bgCard))
                    }
                }
            }
            .frame(height: 100)

            // Date labels
            if trendData.count >= 2 {
                HStack {
                    Text(formatDate(trendData.first!.date))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.textMuted)
                    Spacer()
                    Text(formatDate(trendData.last!.date))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.textMuted)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.bgCard.opacity(0.4))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.borderSubtle.opacity(0.3), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Helpers

    private func formatNumber(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    private func exportMarkdownReport() {
        GRumpLogger.general.info("Exporting metrics report as markdown")
    }

    private func generateSampleMetrics() {
        metrics = CodeMetrics(
            totalLOC: 66_420,
            avgComplexity: 12.4,
            duplicationPercent: 4.7,
            overallGrade: .b
        )

        complexityBuckets = [
            ComplexityBucket(id: "1-5", label: "1-5", count: 342, color: Color.accentGreen),
            ComplexityBucket(id: "6-10", label: "6-10", count: 187, color: Color(red: 0.55, green: 0.78, blue: 0.25)),
            ComplexityBucket(id: "11-20", label: "11-20", count: 89, color: Color(red: 0.90, green: 0.75, blue: 0.20)),
            ComplexityBucket(id: "21-50", label: "21-50", count: 31, color: Color.accentOrange),
            ComplexityBucket(id: "50+", label: "50+", count: 8, color: Color(red: 0.90, green: 0.30, blue: 0.25)),
        ]

        let fileNames = [
            "ChatViewModel+Streaming.swift", "ToolExec+FileOps.swift",
            "ContentView.swift", "OpenRouterService.swift",
            "MCPService.swift", "ToolDefinitions.swift",
            "ChatViewModel+ToolExecution.swift", "LSPService.swift",
            "XMLToolCallParser.swift", "SwiftDataModels.swift",
        ]
        hotspotFiles = fileNames.enumerated().map { i, name in
            let complexity = [42, 38, 35, 31, 28, 25, 22, 19, 17, 14][i]
            let grade: CodeMetrics.MetricGrade = complexity > 35 ? .d : (complexity > 25 ? .c : (complexity > 15 ? .b : .a))
            return HotspotFile(
                id: "hot-\(i)",
                name: name,
                loc: Int.random(in: 200...900),
                complexity: complexity,
                grade: grade,
                issues: max(0, complexity / 8 - 1)
            )
        }

        languageBreakdown = [
            LanguageBreakdown(id: "swift", name: "Swift", loc: 58_200, color: Color.accentOrange, percentage: 87.6),
            LanguageBreakdown(id: "js", name: "JavaScript", loc: 4_800, color: Color(red: 0.95, green: 0.85, blue: 0.20), percentage: 7.2),
            LanguageBreakdown(id: "json", name: "JSON", loc: 2_100, color: Color(red: 0.50, green: 0.50, blue: 0.55), percentage: 3.2),
            LanguageBreakdown(id: "md", name: "Markdown", loc: 980, color: Color(red: 0.30, green: 0.55, blue: 0.95), percentage: 1.5),
            LanguageBreakdown(id: "other", name: "Other", loc: 340, color: Color(red: 0.60, green: 0.60, blue: 0.65), percentage: 0.5),
        ]

        let calendar = Calendar.current
        let now = Date()
        trendData = (0..<8).map { i in
            let date = calendar.date(byAdding: .day, value: -7 * (7 - i), to: now)!
            let baseScore = 72.0 + Double(i) * 1.8 + Double.random(in: -3...3)
            return TrendPoint(id: "trend-\(i)", date: date, score: min(100, max(0, baseScore)))
        }
    }
}
