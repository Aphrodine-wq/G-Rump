// MARK: - Onboarding Step 6: Skills Quick Start
//
// Skill-pack selection grid with toggle cards for iOS, Full Stack,
// DevOps, Code Quality, and AI & ML packs.

import SwiftUI

extension OnboardingView {

    // MARK: - Skill Packs Data

    struct SkillPack: Identifiable {
        let id: String
        let name: String
        let icon: String
        let description: String
        let skillIds: [String]
    }

    static var skillPacks: [SkillPack] {
        [
            SkillPack(id: "ios", name: "iOS Development", icon: "iphone", description: "Swift, SwiftUI, Xcode, App Store prep",
                      skillIds: ["swift-ios", "swiftui-migration", "swiftdata", "async-await", "app-store-prep", "privacy-manifest", "coreml-conversion"]),
            SkillPack(id: "fullstack", name: "Full Stack", icon: "server.rack", description: "React, Node, APIs, databases",
                      skillIds: ["full-stack", "react-nextjs", "python-fastapi", "api-design", "database-design", "graphql"]),
            SkillPack(id: "devops", name: "DevOps", icon: "gearshape.2.fill", description: "CI/CD, Docker, Kubernetes, Terraform",
                      skillIds: ["ci-cd", "devops", "docker-deploy", "kubernetes", "terraform", "aws-serverless"]),
            SkillPack(id: "quality", name: "Code Quality", icon: "checkmark.seal.fill", description: "Reviews, testing, refactoring, security",
                      skillIds: ["code-review", "testing", "test-generation", "refactoring", "security-audit", "performance", "accessibility"]),
            SkillPack(id: "aiml", name: "AI & ML", icon: "brain.head.profile", description: "Prompt engineering, CoreML, MLX, data science",
                      skillIds: ["prompt-engineering", "coreml-conversion", "mlx-training", "data-science"])
        ]
    }

    // MARK: - Step 6: Skills Quick Start

    var stepSkillsQuickStart: some View {
        VStack(spacing: Spacing.giant) {
            VStack(spacing: Spacing.lg) {
                Image(systemName: "sparkles")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(themeManager.palette.effectiveAccent)

                Text("Enable skill packs")
                    .font(Typography.displayMedium)
                    .foregroundColor(themeManager.palette.textPrimary)

                Text("Skills teach G-Rump domain expertise. Pick packs that match your work — you can customize later in Settings.")
                    .font(Typography.bodySmall)
                    .foregroundColor(themeManager.palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }

            VStack(spacing: Spacing.md) {
                ForEach(Self.skillPacks) { pack in
                    Button {
                        if selectedSkillPacks.contains(pack.id) {
                            selectedSkillPacks.remove(pack.id)
                        } else {
                            selectedSkillPacks.insert(pack.id)
                        }
                        applySelectedSkillPacks()
                    } label: {
                        HStack(spacing: Spacing.xl) {
                            Image(systemName: pack.icon)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(selectedSkillPacks.contains(pack.id) ? themeManager.palette.effectiveAccent : themeManager.palette.textMuted)
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(pack.name)
                                    .font(Typography.bodySmallSemibold)
                                    .foregroundColor(themeManager.palette.textPrimary)
                                Text(pack.description)
                                    .font(Typography.captionSmall)
                                    .foregroundColor(themeManager.palette.textSecondary)
                            }

                            Spacer()

                            Image(systemName: selectedSkillPacks.contains(pack.id) ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 18))
                                .foregroundColor(selectedSkillPacks.contains(pack.id) ? themeManager.palette.effectiveAccent : themeManager.palette.textMuted.opacity(0.4))
                        }
                        .padding(Spacing.lg)
                        .frame(maxWidth: 440)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .fill(selectedSkillPacks.contains(pack.id)
                                      ? themeManager.palette.effectiveAccent.opacity(0.08)
                                      : themeManager.palette.bgCard)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .stroke(selectedSkillPacks.contains(pack.id)
                                        ? themeManager.palette.effectiveAccent.opacity(0.4)
                                        : themeManager.palette.borderCrisp, lineWidth: Border.thin)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(pack.name) skill pack")
                    .accessibilityHint(pack.description)
                }
            }

            if !selectedSkillPacks.isEmpty {
                let count = Set(Self.skillPacks.filter { selectedSkillPacks.contains($0.id) }.flatMap(\.skillIds)).count
                Text("\(count) skills enabled")
                    .font(Typography.captionSmallMedium)
                    .foregroundColor(themeManager.palette.effectiveAccent)
            }
        }
        .padding(.horizontal, Spacing.huge)
    }

    func applySelectedSkillPacks() {
        var allIds: Set<String> = []
        for pack in Self.skillPacks where selectedSkillPacks.contains(pack.id) {
            for skillId in pack.skillIds {
                allIds.insert("global:\(skillId)")
            }
        }
        SkillsSettingsStorage.saveAllowlist(allIds)
    }
}
