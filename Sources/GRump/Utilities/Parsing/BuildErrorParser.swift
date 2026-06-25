import SwiftUI
import Foundation

// MARK: - Build Error Model

struct BuildError: Identifiable, Hashable {
    let id = UUID()
    let file: String
    let line: Int
    let column: Int
    let message: String
    let severity: Severity
    let fixitSuggestion: String?

    enum Severity: String, Hashable, CaseIterable {
        case error
        case warning
        case note

        var icon: String {
            switch self {
            case .error: return "xmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .note: return "info.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .error: return .red
            case .warning: return .orange
            case .note: return Color(red: 0.3, green: 0.6, blue: 1.0)
            }
        }
    }

    var fileName: String { (file as NSString).lastPathComponent }
    var shortPath: String {
        let components = file.components(separatedBy: "/")
        if components.count > 3 {
            return components.suffix(3).joined(separator: "/")
        }
        return file
    }
}

// MARK: - Build Error Parser

struct BuildErrorParserEngine {
    /// Parse xcodebuild or swift build output into structured errors.
    static func parse(_ output: String) -> [BuildError] {
        var errors: [BuildError] = []
        let lines = output.components(separatedBy: "\n")

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Swift/Clang format: /path/file.swift:10:5: error: message
            if let match = parseSwiftError(trimmed) {
                // Look ahead for fixit
                var fixit: String?
                if index + 1 < lines.count {
                    let nextLine = lines[index + 1].trimmingCharacters(in: .whitespaces)
                    if nextLine.contains("fix-it:") || nextLine.contains("note:") {
                        fixit = nextLine
                    }
                }
                errors.append(BuildError(
                    file: match.file, line: match.line, column: match.column,
                    message: match.message, severity: match.severity,
                    fixitSuggestion: fixit
                ))
            }
        }

        return errors
    }

    private struct ParsedError {
        let file: String
        let line: Int
        let column: Int
        let message: String
        let severity: BuildError.Severity
    }

    private static func parseSwiftError(_ line: String) -> ParsedError? {
        // Pattern: /path/to/file.swift:LINE:COL: error|warning|note: message
        let patterns: [(String, BuildError.Severity)] = [
            (": error: ", .error),
            (": warning: ", .warning),
            (": note: ", .note)
        ]

        for (separator, severity) in patterns {
            guard let sepRange = line.range(of: separator) else { continue }
            let pathAndLocation = String(line[line.startIndex..<sepRange.lowerBound])
            let message = String(line[sepRange.upperBound...])

            // Split path:line:col
            let components = pathAndLocation.components(separatedBy: ":")
            guard components.count >= 3 else { continue }

            // Reconstruct file path (may contain : on macOS in volume names)
            let lineStr = components[components.count - 2]
            let colStr = components[components.count - 1]

            guard let lineNum = Int(lineStr), let colNum = Int(colStr) else { continue }

            let filePath = components.dropLast(2).joined(separator: ":")

            return ParsedError(
                file: filePath, line: lineNum, column: colNum,
                message: message, severity: severity
            )
        }

        return nil
    }
}

// MARK: - Build Errors View

struct BuildErrorsView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var viewModel: ChatViewModel
    let errors: [BuildError]
    @State private var filterSeverity: BuildError.Severity?
    @State private var autoFixEnabled = false
    @State private var isAutoFixing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: Spacing.lg) {
                Image(systemName: "hammer.fill")
                    .font(Typography.captionSmall)
                    .foregroundColor(errors.contains(where: { $0.severity == .error }) ? .red : .accentGreen)

                Text("Build Results")
                    .font(Typography.captionSmallSemibold)
                    .foregroundColor(themeManager.palette.textSecondary)

                // Summary
                let errorCount = errors.filter { $0.severity == .error }.count
                let warningCount = errors.filter { $0.severity == .warning }.count

                if errorCount > 0 {
                    Label("\(errorCount)", systemImage: "xmark.circle.fill")
                        .font(Typography.micro)
                        .foregroundColor(.red)
                }
                if warningCount > 0 {
                    Label("\(warningCount)", systemImage: "exclamationmark.triangle.fill")
                        .font(Typography.micro)
                        .foregroundColor(.orange)
                }

                Spacer()

                // Auto-fix toggle
                Toggle(isOn: $autoFixEnabled) {
                    Text("Auto-fix")
                        .font(Typography.micro)
                        .foregroundColor(themeManager.palette.textMuted)
                }
                .toggleStyle(.switch)
                .controlSize(.mini)

                if isAutoFixing {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.lg)

            // Filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    severityChip(nil, label: "All (\(errors.count))")
                    ForEach(BuildError.Severity.allCases, id: \.self) { sev in
                        let count = errors.filter { $0.severity == sev }.count
                        if count > 0 {
                            severityChip(sev, label: "\(sev.rawValue.capitalized) (\(count))")
                        }
                    }
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.bottom, Spacing.md)
            }

            Rectangle()
                .fill(themeManager.palette.borderSubtle)
                .frame(height: Border.thin)

            // Error list
            ScrollView {
                LazyVStack(spacing: Spacing.sm) {
                    ForEach(filteredErrors) { error in
                        BuildErrorRow(error: error, onFix: {
                            fixError(error)
                        })
                    }
                }
                .padding(Spacing.lg)
            }
        }
        .background(themeManager.palette.bgElevated.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .stroke(themeManager.palette.borderSubtle, lineWidth: Border.hairline)
        )
    }

    private var filteredErrors: [BuildError] {
        guard let severity = filterSeverity else { return errors }
        return errors.filter { $0.severity == severity }
    }

    private func severityChip(_ severity: BuildError.Severity?, label: String) -> some View {
        let isSelected = filterSeverity == severity
        return Button(action: { filterSeverity = severity }) {
            Text(label)
                .font(Typography.micro)
                .foregroundColor(isSelected ? (severity?.color ?? themeManager.palette.effectiveAccent) : themeManager.palette.textMuted)
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.sm)
                .background(isSelected ? (severity?.color ?? themeManager.palette.effectiveAccent).opacity(0.12) : themeManager.palette.bgElevated)
                .clipShape(Capsule())
        }
        .buttonStyle(ScaleButtonStyle())
    }

    private func fixError(_ error: BuildError) {
        let prompt = """
        Fix this build error in \(error.file) at line \(error.line):

        Error: \(error.message)
        \(error.fixitSuggestion.map { "Suggested fix: \($0)" } ?? "")

        Read the file, apply the minimal fix, and verify it compiles.
        """
        viewModel.userInput = prompt
        viewModel.sendMessage()
    }
}

// MARK: - Build Error Row

struct BuildErrorRow: View {
    @EnvironmentObject var themeManager: ThemeManager
    let error: BuildError
    var onFix: () -> Void
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .top, spacing: Spacing.md) {
                Image(systemName: error.severity.icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(error.severity.color)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(error.message)
                        .font(Typography.captionSmallMedium)
                        .foregroundColor(themeManager.palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: Spacing.md) {
                        Text(error.shortPath)
                            .font(Typography.codeMicro)
                            .foregroundColor(themeManager.palette.effectiveAccent)
                        Text(":\(error.line):\(error.column)")
                            .font(Typography.codeMicro)
                            .foregroundColor(themeManager.palette.textMuted)
                    }
                }

                Spacer()

                if isHovered && error.severity == .error {
                    Button(action: onFix) {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 10))
                            Text("Fix")
                                .font(Typography.captionSmallSemibold)
                        }
                        .foregroundColor(themeManager.palette.effectiveAccent)
                        .padding(.horizontal, Spacing.lg)
                        .padding(.vertical, Spacing.sm)
                        .background(themeManager.palette.effectiveAccent.opacity(0.12))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .transition(.opacity)
                }
            }

            if let fixit = error.fixitSuggestion {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 8))
                        .foregroundColor(.orange)
                    Text(fixit)
                        .font(Typography.micro)
                        .foregroundColor(themeManager.palette.textMuted)
                        .lineLimit(2)
                }
                .padding(.leading, Spacing.xxxl)
            }
        }
        .padding(Spacing.xl)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(isHovered ? themeManager.palette.bgElevated.opacity(0.5) : themeManager.palette.bgElevated.opacity(0.3))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .stroke(error.severity == .error ? error.severity.color.opacity(0.2) : themeManager.palette.borderSubtle, lineWidth: Border.hairline)
        )
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: Anim.instant), value: isHovered)
    }
}
