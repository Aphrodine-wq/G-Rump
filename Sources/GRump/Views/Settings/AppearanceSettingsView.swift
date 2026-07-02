import SwiftUI

// MARK: - Appearance Settings View
struct AppearanceSettingsView: View {
    @ObservedObject var themeManager: ThemeManager
    @Binding var lineSpacingSetting: String
    @Binding var codeFontSetting: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.huge) {
            settingsCard {
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    sectionTitle("Theme", icon: "paintbrush.fill", accent: themeManager.accentColor.color)
                    VStack(spacing: Spacing.md) {
                        themeRow(.system)
                        Text("Light")
                            .font(Typography.captionSmallSemibold)
                            .foregroundColor(.textMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, Spacing.sm)
                        ForEach(AppTheme.lightThemes, id: \.self) { appTheme in
                            themeRow(appTheme)
                        }
                        Text("Dark")
                            .font(Typography.captionSmallSemibold)
                            .foregroundColor(.textMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, Spacing.lg)
                        ForEach(AppTheme.darkThemes, id: \.self) { appTheme in
                            themeRow(appTheme)
                        }
                        Text("Fun")
                            .font(Typography.captionSmallSemibold)
                            .foregroundColor(.textMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, Spacing.lg)
                        ForEach(AppTheme.funThemes, id: \.self) { appTheme in
                            themeRow(appTheme)
                        }
                    }
                }
            }
            settingsCard {
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    sectionTitle("Accent color", icon: "paintpalette.fill", accent: themeManager.accentColor.color)
                    let columns = [GridItem(.adaptive(minimum: 100))]
                    LazyVGrid(columns: columns, spacing: Spacing.md) {
                        ForEach(AccentColorOption.allCases) { option in
                            accentChip(option)
                        }
                    }
                }
            }
            settingsCard {
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    sectionTitle("Display", icon: "rectangle.compress.vertical", accent: themeManager.accentColor.color)
                    Text("Compact uses slightly tighter spacing.")
                        .font(Typography.bodySmall)
                        .foregroundColor(.textMuted)
                    Picker("Density", selection: $themeManager.density) {
                        ForEach(AppDensity.allCases) { density in
                            Text(density.displayName).tag(density)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            settingsCard {
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    sectionTitle("Text size", icon: "textformat.size", accent: themeManager.accentColor.color)
                    Text("Scale for message and code text. Medium is the default.")
                        .font(Typography.bodySmall)
                        .foregroundColor(.textMuted)
                    Picker("Content size", selection: $themeManager.contentSize) {
                        ForEach(AppContentSize.allCases) { size in
                            Text(size.displayName).tag(size)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            settingsCard {
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    sectionTitle("Line spacing", icon: "arrow.up.and.down.text.horizontal", accent: themeManager.accentColor.color)
                    Text("Adjust vertical spacing between lines in messages.")
                        .font(Typography.bodySmall)
                        .foregroundColor(.textMuted)
                    Picker("Line spacing", selection: $lineSpacingSetting) {
                        Text("Tight").tag("tight")
                        Text("Normal").tag("normal")
                        Text("Relaxed").tag("relaxed")
                    }
                    .pickerStyle(.segmented)
                }
            }
            settingsCard {
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    sectionTitle("Code font", icon: "chevron.left.forwardslash.chevron.right", accent: themeManager.accentColor.color)
                    Text("Font used for code blocks and inline code.")
                        .font(Typography.bodySmall)
                        .foregroundColor(.textMuted)
                    Picker("Code font", selection: $codeFontSetting) {
                        Text("SF Mono").tag("sf-mono")
                        Text("Menlo").tag("menlo")
                        Text("Fira Code").tag("fira-code")
                        Text("JetBrains Mono").tag("jetbrains-mono")
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
    }

    // MARK: - Helper Views (these would need to be shared or duplicated)

    @ViewBuilder
    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(Spacing.huge)
        .background(themeManager.palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xxl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.xxl, style: .continuous)
            .stroke(themeManager.palette.borderSubtle, lineWidth: 1))
    }

    @ViewBuilder
    private func sectionTitle(_ title: String, icon: String, accent: Color) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(accent)
            Text(title)
                .font(Typography.heading3)
                .foregroundColor(.textPrimary)
        }
    }

    @ViewBuilder
    private func themeRow(_ theme: AppTheme) -> some View {
        Button(action: { themeManager.theme = theme }) {
            HStack(spacing: Spacing.md) {
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(ThemePalette(theme: theme, accent: themeManager.accentColor).bgDark)
                    .frame(width: 32, height: 20)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .stroke(themeManager.palette.borderSubtle, lineWidth: 1)
                    )
                Text(theme.displayName)
                    .font(Typography.body)
                    .foregroundColor(.textPrimary)
                Spacer()
                if themeManager.theme == theme {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(themeManager.accentColor.color)
                        .font(.system(size: 16, weight: .medium))
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(themeManager.theme == theme ? themeManager.accentColor.color.opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func accentChip(_ option: AccentColorOption) -> some View {
        Button(action: { themeManager.accentColor = option }) {
            HStack(spacing: Spacing.xs) {
                Circle()
                    .fill(option.color)
                    .frame(width: 16, height: 16)
                    .overlay(
                        Circle()
                            .stroke(themeManager.palette.borderSubtle, lineWidth: 1)
                    )
                Text(option.displayName)
                    .font(Typography.caption)
                    .foregroundColor(.textPrimary)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(themeManager.accentColor == option ? option.color.opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
