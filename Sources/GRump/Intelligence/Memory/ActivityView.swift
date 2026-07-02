import SwiftUI

struct ActivityView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject var activityStore: ActivityStore
    @Environment(\.dismiss) var dismiss
    @State private var filterSuccess: Bool?
    @State private var searchText: String = ""

    private var filteredEntries: [ActivityEntry] {
        var list = activityStore.entries
        if let success = filterSuccess {
            list = list.filter { $0.success == success }
        }
        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            let q = searchText.lowercased()
            list = list.filter {
                $0.toolName.lowercased().contains(q) ||
                $0.summary.lowercased().contains(q) ||
                $0.metadata?.filePath?.lowercased().contains(q) == true ||
                $0.metadata?.command?.lowercased().contains(q) == true
            }
        }
        return list
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.xl) {
                Text("Activity")
                    .font(Typography.heading2)
                    .foregroundColor(.textPrimary)
                Spacer()
                HStack(spacing: Spacing.md) {
                    Picker("Filter", selection: $filterSuccess) {
                        Text("All").tag(nil as Bool?)
                        Text("Success").tag(true as Bool?)
                        Text("Failed").tag(false as Bool?)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                    TextField("Search…", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                    Button("Clear") {
                        activityStore.clear()
                    }
                    .foregroundColor(themeManager.palette.effectiveAccent)
                }
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(Typography.body)
                        .foregroundColor(.textMuted)
                }
                .buttonStyle(.plain)
            }
            .padding(Spacing.huge)

            Rectangle()
                .fill(themeManager.palette.borderCrisp)
                .frame(height: Border.thin)

            if filteredEntries.isEmpty {
                VStack(spacing: Spacing.xl) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 48))
                        .foregroundColor(.textMuted)
                    Text("No activity yet")
                        .font(Typography.body)
                        .foregroundColor(.textMuted)
                    Text("Tool invocations will appear here as the agent runs.")
                        .font(Typography.captionSmall)
                        .foregroundColor(.textMuted)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: Spacing.sm) {
                        ForEach(filteredEntries) { entry in
                            ActivityEntryRow(entry: entry)
                        }
                    }
                    .padding(Spacing.huge)
                }
            }
        }
        .background(themeManager.palette.bgDark)
        .frame(minWidth: 400, minHeight: 400)
    }
}

private struct ActivityEntryRow: View {
    @EnvironmentObject var themeManager: ThemeManager
    let entry: ActivityEntry

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.lg) {
            Image(systemName: entry.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(Typography.bodySmall)
                .foregroundColor(entry.success ? .accentGreen : .accentOrange)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.sm) {
                    Text(entry.toolName.replacingOccurrences(of: "_", with: " "))
                        .font(Typography.captionSmallSemibold)
                        .foregroundColor(.textPrimary)
                    Text(entry.timestamp, style: .relative)
                        .font(Typography.micro)
                        .foregroundColor(.textMuted)
                }
                if let path = entry.metadata?.filePath, !path.isEmpty {
                    Text((path as NSString).lastPathComponent)
                        .font(Typography.codeSmall)
                        .foregroundColor(.textMuted)
                        .lineLimit(1)
                }
                if let cmd = entry.metadata?.command, !cmd.isEmpty {
                    Text(String(cmd.prefix(60)) + (cmd.count > 60 ? "…" : ""))
                        .font(Typography.codeSmall)
                        .foregroundColor(.textMuted)
                        .lineLimit(1)
                }
                if !entry.summary.isEmpty {
                    Text(entry.summary)
                        .font(Typography.captionSmall)
                        .foregroundColor(.textSecondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(Spacing.lg)
        .background(themeManager.palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.standard, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.standard, style: .continuous)
                .stroke(themeManager.palette.borderCrisp, lineWidth: Border.thin)
        )
    }
}
