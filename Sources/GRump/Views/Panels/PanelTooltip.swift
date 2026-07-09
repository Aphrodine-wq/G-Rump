import SwiftUI

/// Rich hover tooltip for right panel sidebar icons.
/// Shows icon, name, description, keyboard shortcut, and a mini preview graphic.
struct PanelTooltip: View {
    @EnvironmentObject var themeManager: ThemeManager
    let tab: PanelTab

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            // Header: icon + name + shortcut
            HStack(spacing: Spacing.lg) {
                Image(systemName: tab.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(themeManager.palette.effectiveAccent)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(tab.label)
                        .font(Typography.bodySmallSemibold)
                        .foregroundColor(themeManager.palette.textPrimary)

                    if let shortcut = tab.shortcut {
                        Text("⌃\(shortcut)")
                            .font(Typography.micro)
                            .foregroundColor(themeManager.palette.textMuted)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, 1)
                            .background(themeManager.palette.bgInput)
                            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    }
                }

                Spacer()
            }

            // Description
            Text(tab.tooltipDescription)
                .font(Typography.captionSmall)
                .foregroundColor(themeManager.palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            // Mini preview graphic
            miniPreview
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(themeManager.palette.bgInput.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .padding(Spacing.xl)
        .frame(width: 220)
        .background(themeManager.palette.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .stroke(themeManager.palette.borderCrisp.opacity(0.5), lineWidth: Border.thin)
        )
        .shadow(color: Color.black.opacity(0.25), radius: 12, y: 4)
    }

    @ViewBuilder
    private var miniPreview: some View {
        switch tab {
        case .chat:
            miniChatPreview
        case .files:
            miniFileTreePreview
        case .git:
            miniGitPreview
        case .terminal:
            miniTerminalPreview
        case .tests:
            miniTestsPreview
        case .preview:
            miniDevicePreview
        case .simulator:
            miniSimPreview
        case .docs:
            miniDocsPreview
        case .spm:
            miniPackagePreview
        case .logs:
            miniLogsPreview
        default:
            miniGenericPreview
        }
    }

    // MARK: - Mini Previews

    private var miniChatPreview: some View {
        VStack(alignment: .leading, spacing: 3) {
            miniBar(width: 100, color: themeManager.palette.effectiveAccent.opacity(0.4))
            miniBar(width: 140, color: themeManager.palette.textMuted.opacity(0.2))
            miniBar(width: 80, color: themeManager.palette.effectiveAccent.opacity(0.4))
        }
        .padding(.horizontal, Spacing.lg)
    }

    private var miniFileTreePreview: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: "folder.fill").font(.system(size: 8)).foregroundColor(.accentOrange)
                miniBar(width: 50, color: themeManager.palette.textMuted.opacity(0.3))
            }
            HStack(spacing: 4) {
                Spacer().frame(width: 12)
                Image(systemName: "swift").font(.system(size: 8)).foregroundColor(Color(red: 1.0, green: 0.45, blue: 0.25))
                miniBar(width: 60, color: themeManager.palette.textMuted.opacity(0.3))
            }
            HStack(spacing: 4) {
                Spacer().frame(width: 12)
                Image(systemName: "swift").font(.system(size: 8)).foregroundColor(Color(red: 1.0, green: 0.45, blue: 0.25))
                miniBar(width: 45, color: themeManager.palette.textMuted.opacity(0.3))
            }
        }
        .padding(.horizontal, Spacing.lg)
    }

    private var miniGitPreview: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Circle().fill(Color.accentGreen).frame(width: 5, height: 5)
                miniBar(width: 60, color: Color.accentGreen.opacity(0.3))
            }
            HStack(spacing: 4) {
                Circle().fill(Color.orange).frame(width: 5, height: 5)
                miniBar(width: 80, color: Color.orange.opacity(0.3))
            }
            HStack(spacing: 4) {
                Circle().fill(Color.red).frame(width: 5, height: 5)
                miniBar(width: 45, color: Color.red.opacity(0.3))
            }
        }
        .padding(.horizontal, Spacing.lg)
    }

    private var miniTerminalPreview: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text("$").font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundColor(Color.accentGreen)
                miniBar(width: 80, color: themeManager.palette.textMuted.opacity(0.3))
            }
            miniBar(width: 120, color: themeManager.palette.textMuted.opacity(0.15))
            miniBar(width: 90, color: themeManager.palette.textMuted.opacity(0.15))
        }
        .padding(.horizontal, Spacing.lg)
    }

    private var miniTestsPreview: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 7)).foregroundColor(.accentGreen)
                miniBar(width: 70, color: Color.accentGreen.opacity(0.3))
            }
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 7)).foregroundColor(.accentGreen)
                miniBar(width: 55, color: Color.accentGreen.opacity(0.3))
            }
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill").font(.system(size: 7)).foregroundColor(.red)
                miniBar(width: 65, color: Color.red.opacity(0.3))
            }
        }
        .padding(.horizontal, Spacing.lg)
    }

    private var miniDevicePreview: some View {
        HStack {
            Spacer()
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(themeManager.palette.textMuted.opacity(0.3), lineWidth: 1)
                .frame(width: 22, height: 38)
                .overlay(
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(themeManager.palette.effectiveAccent.opacity(0.15))
                        .padding(3)
                )
            Spacer()
        }
    }

    private var miniSimPreview: some View {
        HStack(spacing: Spacing.lg) {
            Spacer()
            VStack(spacing: 2) {
                Image(systemName: "iphone").font(.system(size: 14)).foregroundColor(themeManager.palette.textMuted.opacity(0.5))
                Circle().fill(Color.accentGreen).frame(width: 4, height: 4)
            }
            VStack(spacing: 2) {
                Image(systemName: "ipad").font(.system(size: 14)).foregroundColor(themeManager.palette.textMuted.opacity(0.5))
                Circle().fill(Color(red: 0.5, green: 0.5, blue: 0.6)).frame(width: 4, height: 4)
            }
            Spacer()
        }
    }

    private var miniDocsPreview: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass").font(.system(size: 7)).foregroundColor(themeManager.palette.textMuted)
                miniBar(width: 90, color: themeManager.palette.textMuted.opacity(0.2))
            }
            miniBar(width: 140, color: themeManager.palette.effectiveAccent.opacity(0.2))
            miniBar(width: 100, color: themeManager.palette.textMuted.opacity(0.15))
        }
        .padding(.horizontal, Spacing.lg)
    }

    private var miniPackagePreview: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: "shippingbox").font(.system(size: 7)).foregroundColor(.orange)
                miniBar(width: 70, color: Color.orange.opacity(0.3))
            }
            HStack(spacing: 4) {
                Image(systemName: "shippingbox").font(.system(size: 7)).foregroundColor(.orange)
                miniBar(width: 55, color: Color.orange.opacity(0.3))
            }
        }
        .padding(.horizontal, Spacing.lg)
    }

    private var miniLogsPreview: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Circle().fill(Color(red: 0.3, green: 0.6, blue: 1.0)).frame(width: 4, height: 4)
                miniBar(width: 110, color: themeManager.palette.textMuted.opacity(0.2))
            }
            HStack(spacing: 4) {
                Circle().fill(Color.orange).frame(width: 4, height: 4)
                miniBar(width: 90, color: themeManager.palette.textMuted.opacity(0.2))
            }
            HStack(spacing: 4) {
                Circle().fill(Color.red).frame(width: 4, height: 4)
                miniBar(width: 70, color: themeManager.palette.textMuted.opacity(0.2))
            }
        }
        .padding(.horizontal, Spacing.lg)
    }

    private var miniGenericPreview: some View {
        VStack(spacing: 4) {
            Image(systemName: tab.icon)
                .font(.system(size: 16, weight: .light))
                .foregroundColor(themeManager.palette.textMuted.opacity(0.4))
        }
    }

    private func miniBar(width: CGFloat, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(color)
            .frame(width: width, height: 4)
    }
}

// MARK: - Tooltip Description Extension

extension PanelTab {
    var tooltipDescription: String {
        switch self {
        case .chat: return "Main conversation view with AI assistant"
        case .files: return "Browse and navigate project files"
        case .preview: return "Live SwiftUI preview canvas"
        case .simulator: return "Manage iOS/watchOS simulators"
        case .git: return "Git status, branches, commit & push"
        case .tests: return "Discover and run XCTests"
        case .build: return "Build output, errors & live diagnostics"
        case .assets: return "Browse asset catalogs & SF Symbols"
        case .localization: return "Manage translations & find hardcoded strings"
        case .schema: return "View SwiftData & Core Data models"
        case .profiling: return "Performance measurements & Instruments"
        case .logs: return "System log streaming & crash reports"
        case .spm: return "Swift Package Manager dependencies"
        case .xcode: return "Xcode project targets & schemes"
        case .docs: return "Search Apple developer documentation"
        case .terminal: return "Integrated terminal sessions"
        case .appstore: return "App Store submission checklist"
        case .accessibility: return "Accessibility audit & suggestions"
        case .memory: return "Browse & search persistent memory store"
        case .learning: return "Lessons, skill proposals & run outcomes"
        }
    }
}
