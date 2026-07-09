// MARK: - Onboarding Step 4: Skills Quick Start
//
// Skill-pack toggle grid driven by the real SkillPack.builtInPacks.
// Selection is local state only — it's applied exactly once, as a UNION
// merge, when onboarding completes (OnboardingView.completeOnboarding).

import SwiftUI

extension OnboardingView {

    /// Packs surfaced by default, iOS-first. The rest sit behind "Show all".
    static let featuredPackIds: [String] = [
        "ios-dev", "code-quality", "mobile-cross-platform", "full-stack-web",
        "backend-apis", "devops", "ai-ml", "security-compliance"
    ]

    private var featuredPacks: [SkillPack] {
        Self.featuredPackIds.compactMap { id in
            SkillPack.builtInPacks.first { $0.id == id }
        }
    }

    private var remainingPacks: [SkillPack] {
        SkillPack.builtInPacks.filter { !Self.featuredPackIds.contains($0.id) }
    }

    // MARK: - Step 4: Skills Quick Start

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

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: Spacing.md) {
                    ForEach(featuredPacks) { pack in
                        skillPackRow(pack)
                    }

                    if showAllSkillPacks {
                        ForEach(remainingPacks) { pack in
                            skillPackRow(pack)
                        }
                    } else if !remainingPacks.isEmpty {
                        Button {
                            withAnimation(.easeInOut(duration: Anim.quick)) {
                                showAllSkillPacks = true
                            }
                        } label: {
                            Text("Show all \(SkillPack.builtInPacks.count) packs")
                                .font(Typography.bodySmallMedium)
                                .foregroundColor(themeManager.palette.effectiveAccent)
                                .padding(.vertical, Spacing.md)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: 440, maxHeight: 340)

            if !selectedSkillPacks.isEmpty {
                Text("\(selectedSkillCount) skills enabled")
                    .font(Typography.captionSmallMedium)
                    .foregroundColor(themeManager.palette.effectiveAccent)
            }
        }
        .padding(.horizontal, Spacing.huge)
    }

    private var selectedSkillCount: Int {
        Set(SkillPack.builtInPacks
            .filter { selectedSkillPacks.contains($0.id) }
            .flatMap(\.skillBaseIds)).count
    }

    // MARK: - Pack Row

    private func skillPackRow(_ pack: SkillPack) -> some View {
        let isSelected = selectedSkillPacks.contains(pack.id)
        return Button {
            if isSelected {
                selectedSkillPacks.remove(pack.id)
            } else {
                selectedSkillPacks.insert(pack.id)
            }
        } label: {
            HStack(spacing: Spacing.xl) {
                Image(systemName: pack.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(isSelected ? themeManager.palette.effectiveAccent : themeManager.palette.textMuted)
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

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundColor(isSelected ? themeManager.palette.effectiveAccent : themeManager.palette.textMuted.opacity(0.4))
            }
            .padding(Spacing.lg)
            .frame(maxWidth: 440)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(isSelected
                          ? themeManager.palette.effectiveAccent.opacity(0.08)
                          : themeManager.palette.bgCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .stroke(isSelected
                            ? themeManager.palette.effectiveAccent.opacity(0.4)
                            : themeManager.palette.borderCrisp, lineWidth: Border.thin)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(pack.name) skill pack")
        .accessibilityHint(pack.description)
    }
}
