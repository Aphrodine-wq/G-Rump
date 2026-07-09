// MARK: - Learning Panel
//
// The learning loop's transparency surface: pending skill proposals (the
// approval gate, rendered as diffs), the lesson list with confidence bars and
// pin/retire/edit, and recent run outcomes.

import SwiftUI

struct LearningPanel: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var viewModel: ChatViewModel
    @ObservedObject private var lessonStore = LessonStore.shared
    @ObservedObject private var proposalStore = SkillProposalStore.shared
    @ObservedObject private var reflectionEngine = ReflectionEngine.shared

    private enum LearningTab: String, CaseIterable {
        case proposals
        case lessons
        case outcomes

        var label: String {
            switch self {
            case .proposals: return "Proposals"
            case .lessons: return "Lessons"
            case .outcomes: return "Outcomes"
            }
        }
    }

    @State private var selectedTab: LearningTab = .lessons
    @State private var recentOutcomes: [RunOutcome] = []
    @State private var editingLesson: Lesson?
    @State private var editedText = ""

    var body: some View {
        VStack(spacing: 0) {
            header

            Rectangle()
                .fill(themeManager.palette.borderSubtle)
                .frame(height: Border.thin)

            switch selectedTab {
            case .proposals: proposalsTab
            case .lessons: lessonsTab
            case .outcomes: outcomesTab
            }
        }
        .background(themeManager.palette.bgDark)
        .onAppear {
            if proposalStore.pendingCount > 0 {
                selectedTab = .proposals
            }
            refreshOutcomes()
        }
        .alert("Edit Lesson", isPresented: Binding(
            get: { editingLesson != nil },
            set: { if !$0 { editingLesson = nil } }
        )) {
            TextField("Lesson text", text: $editedText)
            Button("Save") {
                if let lesson = editingLesson {
                    lessonStore.revise(id: lesson.id, newText: editedText)
                }
                editingLesson = nil
            }
            Button("Cancel", role: .cancel) { editingLesson = nil }
        }
    }

    private func refreshOutcomes() {
        Task { @MainActor in
            recentOutcomes = await viewModel.outcomeLedger.recent(30).reversed()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Spacing.lg) {
            Picker("", selection: $selectedTab) {
                ForEach(LearningTab.allCases, id: \.self) { tab in
                    if tab == .proposals && proposalStore.pendingCount > 0 {
                        Text("\(tab.label) (\(proposalStore.pendingCount))").tag(tab)
                    } else {
                        Text(tab.label).tag(tab)
                    }
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if reflectionEngine.isReflecting {
                ProgressView()
                    .controlSize(.small)
                    .help("Reflection in progress")
            }
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.lg)
    }

    // MARK: - Proposals

    private var proposalsTab: some View {
        Group {
            if proposalStore.pending.isEmpty {
                emptyState(
                    icon: "checkmark.seal",
                    text: "No pending skill proposals.\nReflection proposes skills when lessons cluster."
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Spacing.lg) {
                        ForEach(proposalStore.pending) { proposal in
                            proposalCard(proposal)
                        }
                    }
                    .padding(Spacing.lg)
                }
            }
        }
    }

    private func proposalCard(_ proposal: SkillProposal) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.md) {
                Image(systemName: proposal.isUpdate ? "pencil.circle.fill" : "plus.circle.fill")
                    .foregroundColor(themeManager.palette.effectiveAccent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(proposal.draft.name)
                        .font(Typography.bodySmallSemibold)
                        .foregroundColor(themeManager.palette.textPrimary)
                    Text("\(proposal.isUpdate ? "Update" : "New skill") · \(proposal.draft.skillId) · \(proposal.source)")
                        .font(Typography.captionSmall)
                        .foregroundColor(themeManager.palette.textMuted)
                }
                Spacer()
            }

            if !proposal.draft.rationale.isEmpty {
                Text(proposal.draft.rationale)
                    .font(Typography.captionSmall)
                    .foregroundColor(themeManager.palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !proposal.draft.lessonIds.isEmpty {
                Text("From lessons: \(proposal.draft.lessonIds.joined(separator: ", "))")
                    .font(Typography.codeMicro)
                    .foregroundColor(themeManager.palette.textMuted)
            }

            InlineDiffCard(
                filePath: "skills/\(proposal.draft.skillId)/SKILL.md",
                originalContent: proposal.existingBody ?? "",
                newContent: proposal.draft.body
            )

            HStack(spacing: Spacing.md) {
                Button {
                    _ = proposalStore.approve(id: proposal.id, workingDirectory: viewModel.workingDirectory)
                } label: {
                    Text("Approve & Enable")
                        .font(Typography.captionSmallSemibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, Spacing.lg)
                        .padding(.vertical, Spacing.sm)
                        .background(Color.accentGreen)
                        .clipShape(Capsule())
                }
                .buttonStyle(ScaleButtonStyle())

                Button {
                    proposalStore.reject(id: proposal.id)
                } label: {
                    Text("Reject")
                        .font(Typography.captionSmallSemibold)
                        .foregroundColor(themeManager.palette.textSecondary)
                        .padding(.horizontal, Spacing.lg)
                        .padding(.vertical, Spacing.sm)
                        .background(themeManager.palette.bgElevated)
                        .clipShape(Capsule())
                }
                .buttonStyle(ScaleButtonStyle())

                Spacer()
            }
        }
        .padding(Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(themeManager.palette.bgElevated.opacity(0.35))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .stroke(themeManager.palette.borderSubtle, lineWidth: Border.hairline)
        )
    }

    // MARK: - Lessons

    private var activeLessons: [Lesson] {
        lessonStore.lessons
            .filter { $0.status != .retired }
            .sorted { lhs, rhs in
                if (lhs.status == .pinned) != (rhs.status == .pinned) { return lhs.status == .pinned }
                return lhs.effectiveConfidence() > rhs.effectiveConfidence()
            }
    }

    private var retiredLessons: [Lesson] {
        lessonStore.lessons.filter { $0.status == .retired }
    }

    private var lessonsTab: some View {
        Group {
            if lessonStore.lessons.isEmpty {
                emptyState(
                    icon: "graduationcap",
                    text: "No lessons yet.\nThe agent distills them after runs — or ask it to record_lesson."
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Spacing.sm) {
                        ForEach(activeLessons) { lesson in
                            lessonRow(lesson)
                        }
                        if !retiredLessons.isEmpty {
                            Text("Retired")
                                .font(Typography.captionSmallSemibold)
                                .foregroundColor(themeManager.palette.textMuted)
                                .textCase(.uppercase)
                                .tracking(0.4)
                                .padding(.top, Spacing.xl)
                            ForEach(retiredLessons) { lesson in
                                lessonRow(lesson)
                                    .opacity(0.5)
                            }
                        }
                    }
                    .padding(Spacing.lg)
                }
            }
        }
    }

    private func lessonRow(_ lesson: Lesson) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .top, spacing: Spacing.md) {
                if lesson.status == .pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9))
                        .foregroundColor(themeManager.palette.effectiveAccent)
                        .padding(.top, 2)
                }
                Text(lesson.text)
                    .font(Typography.captionSmallMedium)
                    .foregroundColor(themeManager.palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }

            HStack(spacing: Spacing.md) {
                ProgressView(value: lesson.effectiveConfidence())
                    .progressViewStyle(.linear)
                    .frame(width: 80)
                Text(String(format: "%.0f%%", lesson.effectiveConfidence() * 100))
                    .font(Typography.codeMicro)
                    .foregroundColor(themeManager.palette.textMuted)
                Text("\(lesson.hitCount) hits · \(lesson.category.label) · \(lesson.scope.rawValue)")
                    .font(Typography.codeMicro)
                    .foregroundColor(themeManager.palette.textMuted)
                Spacer()
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(themeManager.palette.bgElevated.opacity(0.3))
        )
        .contextMenu {
            if lesson.status == .retired {
                Button("Reactivate") { lessonStore.reactivate(id: lesson.id) }
            } else {
                Button(lesson.status == .pinned ? "Unpin" : "Pin") {
                    lesson.status == .pinned ? lessonStore.unpin(id: lesson.id) : lessonStore.pin(id: lesson.id)
                }
                Button("Edit…") {
                    editedText = lesson.text
                    editingLesson = lesson
                }
                Button("Retire", role: .destructive) { lessonStore.retire(id: lesson.id) }
            }
        }
    }

    // MARK: - Outcomes

    private var outcomesTab: some View {
        Group {
            if recentOutcomes.isEmpty {
                emptyState(icon: "clock.arrow.circlepath", text: "No recorded runs yet for this project.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Spacing.sm) {
                        ForEach(recentOutcomes) { outcome in
                            outcomeRow(outcome)
                        }
                    }
                    .padding(Spacing.lg)
                }
                .refreshable { refreshOutcomes() }
            }
        }
    }

    private func outcomeRow(_ outcome: RunOutcome) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: outcome.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 11))
                .foregroundColor(outcome.success ? .accentGreen : .red)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(outcome.taskType) · \(outcome.iterations) iterations\(outcome.amended ? " · corrected by user" : "")")
                    .font(Typography.captionSmallMedium)
                    .foregroundColor(themeManager.palette.textPrimary)
                Text(outcome.timestamp.formatted(date: .abbreviated, time: .shortened)
                     + (outcome.buildFailures > 0 ? " · \(outcome.buildFailures) build failures" : "")
                     + (outcome.loopPivots > 0 ? " · \(outcome.loopPivots) pivots" : "")
                     + (outcome.injectedLessonIds.isEmpty ? "" : " · \(outcome.injectedLessonIds.count) lessons applied"))
                    .font(Typography.codeMicro)
                    .foregroundColor(themeManager.palette.textMuted)
            }
            Spacer()
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(themeManager.palette.bgElevated.opacity(0.3))
        )
    }

    // MARK: - Empty state

    private func emptyState(icon: String, text: String) -> some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .light))
                .foregroundColor(themeManager.palette.textMuted.opacity(0.6))
            Text(text)
                .font(Typography.captionSmall)
                .foregroundColor(themeManager.palette.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
