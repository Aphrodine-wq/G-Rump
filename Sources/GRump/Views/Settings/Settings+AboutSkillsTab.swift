import SwiftUI

// MARK: - About & Skills Settings Tab Views
// Contains: aboutSection, skillsSettingsSection, settingsSkillRow
// Extracted from Settings+TabViews.swift for maintainability.

extension SettingsView {

    // MARK: - About

    var aboutSection: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                HStack(spacing: Spacing.xxl) {
                    FrownyFaceLogo(size: 36)
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("G-Rump")
                            .font(Typography.sidebarTitle)
                            .foregroundColor(.textPrimary)
                        Text("AI coding agent with file system, shell, and system control")
                            .font(Typography.caption)
                            .foregroundColor(.textMuted)
                    }
                    Spacer()
                }
                HStack(spacing: Spacing.lg) {
                    Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                        .font(Typography.codeSmall)
                        .foregroundColor(.textMuted)
                    if let url = URL(string: "https://www.g-rump.com") {
                        Link(destination: url) {
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: "arrow.up.right.square")
                                Text("GitHub")
                                    .font(Typography.captionSmallMedium)
                            }
                            .foregroundColor(themeManager.palette.effectiveAccent)
                        }
                    }
                }
                if let onRestart = onRestartOnboarding {
                    Button(action: onRestart) {
                        HStack(spacing: Spacing.md) {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Restart onboarding")
                        }
                        .font(Typography.bodySmallSemibold)
                        .foregroundColor(themeManager.palette.effectiveAccent)
                        .padding(.horizontal, Spacing.xl)
                        .padding(.vertical, Spacing.md)
                        .background(themeManager.palette.effectiveAccent.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.standard, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Skills (Settings Tab)

    var skillsSettingsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.huge) {
            skillsMainCard
            clawHubCard
        }
        .onAppear {
            settingsSkills = SkillsStorage.loadSkills(workingDirectory: workingDirectory)
            settingsSkillEnabledIds = SkillsSettingsStorage.loadAllowlist()
            ClawHubService.shared.loadInstalledSkills()
        }
        .sheet(isPresented: $settingsShowAddSkillSheet) {
            AddSkillSheet(
                workingDirectory: workingDirectory,
                onCreated: {
                    settingsSkills = SkillsStorage.loadSkills(workingDirectory: workingDirectory)
                    settingsShowAddSkillSheet = false
                },
                onCancel: { settingsShowAddSkillSheet = false }
            )
        }
        .sheet(item: $settingsSkillToEdit) { skill in
            EditSkillSheet(
                skill: skill,
                onSaved: {
                    settingsSkills = SkillsStorage.loadSkills(workingDirectory: workingDirectory)
                    settingsSkillToEdit = nil
                },
                onCancel: { settingsSkillToEdit = nil }
            )
            .environmentObject(themeManager)
        }
    }

    private var skillsMainCard: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                sectionTitle("Skills", icon: "brain.head.profile", accent: themeManager.accentColor)
                Text("Skills teach the agent specific workflows via SKILL.md files.")
                    .font(Typography.captionSmall)
                    .foregroundColor(.textMuted)

                if settingsSkills.isEmpty {
                    VStack(spacing: Spacing.lg) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 32))
                            .foregroundColor(.textMuted)
                        Text("No skills yet")
                            .font(Typography.bodySmallSemibold)
                            .foregroundColor(.textPrimary)
                        Text("Add SKILL.md files to ~/.grump/skills/ (global) or .grump/skills/ (project).")
                            .font(Typography.captionSmall)
                            .foregroundColor(.textMuted)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.xl)
                } else {
                    skillPacksSection
                    Divider().padding(.vertical, Spacing.sm)
                    individualSkillsSection
                }

                Button(action: { settingsShowAddSkillSheet = true }) {
                    Label("Add Skill", systemImage: "plus.circle.fill")
                        .font(Typography.bodySmallMedium)
                }
                .buttonStyle(.borderedProminent)
                .tint(themeManager.palette.effectiveAccent)
            }
        }
    }

    private var skillPacksSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.md) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(Typography.micro)
                    .foregroundColor(themeManager.palette.effectiveAccent)
                Text("Skill Packs")
                    .font(Typography.captionSmallSemibold)
                    .foregroundColor(.textSecondary)
                Spacer()
                Text("\(SkillPack.builtInPacks.count) packs")
                    .font(Typography.micro)
                    .foregroundColor(.textMuted)
            }
            ForEach(SkillPack.builtInPacks) { pack in
                let packSkillIds = settingsSkills.filter { pack.skillBaseIds.contains($0.baseId) }.map(\.id)
                let enabledCount = packSkillIds.filter { settingsSkillEnabledIds.contains($0) }.count
                let allEnabled = !packSkillIds.isEmpty && enabledCount == packSkillIds.count

                HStack(spacing: Spacing.lg) {
                    Image(systemName: pack.icon)
                        .font(.system(size: 18))
                        .foregroundColor(allEnabled ? themeManager.palette.effectiveAccent : themeManager.palette.textMuted)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(pack.name)
                            .font(Typography.bodySmallSemibold)
                            .foregroundColor(.textPrimary)
                        Text(pack.description)
                            .font(Typography.captionSmall)
                            .foregroundColor(.textMuted)
                            .lineLimit(2)
                    }
                    Spacer()
                    if enabledCount > 0 && !allEnabled {
                        Text("\(enabledCount)/\(packSkillIds.count)")
                            .font(Typography.micro)
                            .foregroundColor(.textMuted)
                    }
                    Toggle("", isOn: Binding(
                        get: { allEnabled },
                        set: { enable in
                            if enable { pack.enable(allSkills: settingsSkills) } else { pack.disable(allSkills: settingsSkills) }
                            settingsSkillEnabledIds = SkillsSettingsStorage.loadAllowlist()
                        }
                    ))
                    .labelsHidden()
                }
                .padding(Spacing.lg)
                .background(themeManager.palette.bgInput)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
        }
    }

    private var individualSkillsSection: some View {
        let builtIn = settingsSkills.filter { $0.isBuiltIn }
        let userAdded = settingsSkills.filter { !$0.isBuiltIn }
        return Group {
            if !builtIn.isEmpty {
                Text("Built-in")
                    .font(Typography.captionSmallSemibold)
                    .foregroundColor(.textSecondary)
                ForEach(builtIn) { skill in settingsSkillRow(skill) }
            }
            if !userAdded.isEmpty {
                Text("User-added")
                    .font(Typography.captionSmallSemibold)
                    .foregroundColor(.textSecondary)
                    .padding(.top, builtIn.isEmpty ? 0 : Spacing.md)
                ForEach(userAdded) { skill in settingsSkillRow(skill) }
            }
        }
    }

    private var clawHubCard: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                sectionTitle("ClawHub", icon: "square.grid.2x2.fill", accent: themeManager.accentColor)
                Text("Browse and install shared skills from the ClawHub registry.")
                    .font(Typography.captionSmall)
                    .foregroundColor(.textMuted)

                let hubSkills = ClawHubService.shared.installedSkills
                if hubSkills.isEmpty {
                    HStack(spacing: Spacing.lg) {
                        Image(systemName: "tray")
                            .font(.system(size: 20))
                            .foregroundColor(.textMuted)
                        Text("No hub skills installed yet.")
                            .font(Typography.bodySmall)
                            .foregroundColor(.textMuted)
                    }
                    .padding(.vertical, Spacing.md)
                } else {
                    ForEach(hubSkills, id: \.name) { skill in
                        HStack(spacing: Spacing.lg) {
                            Image(systemName: "doc.text.fill")
                                .font(Typography.captionSmall)
                                .foregroundColor(themeManager.palette.effectiveAccent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(skill.name)
                                    .font(Typography.bodySmallSemibold)
                                    .foregroundColor(.textPrimary)
                                if !skill.description.isEmpty {
                                    Text(skill.description)
                                        .font(Typography.captionSmall)
                                        .foregroundColor(.textMuted)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            Text("Installed")
                                .font(Typography.micro)
                                .foregroundColor(.accentGreen)
                        }
                        .padding(Spacing.md)
                        .background(themeManager.palette.bgInput.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    }
                }

                Button(action: { ClawHubService.shared.loadInstalledSkills() }) {
                    Label("Refresh Hub Skills", systemImage: "arrow.clockwise")
                        .font(Typography.bodySmallMedium)
                }
                .buttonStyle(.borderedProminent)
                .tint(themeManager.palette.effectiveAccent)
            }
        }
    }

    func settingsSkillRow(_ skill: Skill) -> some View {
        HStack(spacing: Spacing.lg) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.sm) {
                    Text(skill.name)
                        .font(Typography.bodySmallSemibold)
                        .foregroundColor(.textPrimary)
                    if skill.isBuiltIn {
                        Text("Built-in")
                            .font(Typography.micro)
                            .foregroundColor(themeManager.palette.effectiveAccent)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, 2)
                            .background(themeManager.palette.effectiveAccent.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
                if !skill.description.isEmpty {
                    Text(skill.description)
                        .font(Typography.captionSmall)
                        .foregroundColor(.textMuted)
                        .lineLimit(2)
                }
                Text(skill.scope == .global ? "Global" : "Project")
                    .font(Typography.micro)
                    .foregroundColor(.textMuted)
            }
            Spacer()
            if !skill.isBuiltIn {
                Button(action: { settingsSkillToEdit = skill }) {
                    Image(systemName: "pencil")
                        .font(Typography.captionSmall)
                        .foregroundColor(themeManager.palette.effectiveAccent)
                }
                .buttonStyle(.plain)
            }
            Toggle("", isOn: Binding(
                get: { settingsSkillEnabledIds.contains(skill.id) },
                set: { enabled in
                    if enabled { settingsSkillEnabledIds.insert(skill.id) } else { settingsSkillEnabledIds.remove(skill.id) }
                    SkillsSettingsStorage.saveAllowlist(settingsSkillEnabledIds)
                }
            ))
            .labelsHidden()
        }
        .padding(Spacing.lg)
        .background(themeManager.palette.bgInput)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
}
