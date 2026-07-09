import SwiftUI

struct WhatsNewView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) var dismiss

    private let features: [(icon: String, title: String, description: String)] = [
        ("rectangle.split.3x3", "IDE Intelligence Panels", "17 built-in panels: File Navigator, Git, Tests, Assets, Localization, Profiling, Logs, App Store Tools, and more."),
        ("cpu", "Multi-Provider AI", "First-class support for Anthropic, OpenAI, Google, and OpenRouter."),
        ("server.rack", "MCP Server Integration", "58 pre-configured MCP servers with Keychain-backed credential vault for secure API key storage."),
        ("book.closed.fill", "Skills System", "40+ bundled skills for SwiftUI, async/await, Kubernetes, code review, and more. Add your own with SKILL.md files."),
        ("heart.text.square", "SOUL.md Personality", "Define global and per-project AI personality with SOUL.md files and built-in templates."),
        ("hammer.fill", "Apple-Native Tools", "24 new tools: Spotlight search, Keychain, Calendar, OCR, image classification, xcodebuild, and more."),
        ("paintbrush.fill", "Themes & Layout", "Fun themes (Snow, Linen, Graphite, Amethyst, Ink), Zen Mode, customizable layout, and Activity Bar."),
        ("doc.text.magnifyingglass", "LSP Integration", "Live SourceKit-LSP diagnostics with error/warning badges in the top bar."),
        ("terminal.fill", "Inline Terminal", "Multi-session terminal with ANSI color parsing built right into the app."),
        ("arrow.triangle.branch", "Git Panel", "Full git integration: status, branches, commit, push, and pull without leaving G-Rump.")
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: Spacing.xl) {
                FrownyFaceLogo(size: 64)

                Text("What's New in G-Rump")
                    .font(Typography.heading1)
                    .foregroundColor(themeManager.palette.textPrimary)

                Text("Version 2.0 — The Full IDE Experience")
                    .font(Typography.bodySmall)
                    .foregroundColor(themeManager.palette.textMuted)
            }
            .padding(.top, Spacing.colossal)
            .padding(.bottom, Spacing.huge)

            // Features list
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    ForEach(Array(features.enumerated()), id: \.offset) { _, feature in
                        HStack(alignment: .top, spacing: Spacing.xl) {
                            Image(systemName: feature.icon)
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(themeManager.palette.effectiveAccent)
                                .frame(width: 36, height: 36)
                                .background(themeManager.palette.effectiveAccent.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))

                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text(feature.title)
                                    .font(Typography.bodySmallSemibold)
                                    .foregroundColor(themeManager.palette.textPrimary)
                                Text(feature.description)
                                    .font(Typography.bodySmall)
                                    .foregroundColor(themeManager.palette.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(.horizontal, Spacing.colossal)
            }

            // Done button
            Button(action: { dismiss() }) {
                Text("Continue")
                    .font(Typography.bodySemibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.xl)
                    .background(themeManager.palette.effectiveAccent)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
            }
            .buttonStyle(ScaleButtonStyle())
            .padding(.horizontal, Spacing.colossal)
            .padding(.vertical, Spacing.huge)
        }
        .background(themeManager.palette.bgDark)
        #if os(macOS)
        .frame(width: 480, height: 640)
        #endif
    }
}
