import SwiftUI

struct ChildTimelineView: View {
    var days: [ChildTimelineDay]
    var emptyMessage: String

    var body: some View {
        if days.isEmpty {
            ContentUnavailableView {
                Label("Nothing to show", systemImage: "calendar")
            } description: {
                Text(emptyMessage)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(days) { day in
                        daySection(day)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func daySection(_ day: ChildTimelineDay) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(dayTitle(day.day))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ClinicPalette.primaryText)
                .padding(.top, 18)
                .padding(.bottom, 4)
            ForEach(day.entries) { entry in
                entryRow(entry)
                Divider()
            }
        }
    }

    @ViewBuilder
    private func entryRow(_ entry: ChildTimelineEntry) -> some View {
        if entry.opensRecording {
            NavigationLink(value: entry.id) {
                entryLabel(entry)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(isChange(entry) ? "timeline.change" : "timeline.recording")
        } else {
            entryLabel(entry)
        }
    }

    private func entryLabel(_ entry: ChildTimelineEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(entry.date.formatted(date: .omitted, time: .shortened))
                .font(.callout)
                .foregroundStyle(ClinicPalette.secondaryText)
                .frame(width: 48, alignment: .leading)
                .padding(.top, 6)
            ZStack {
                Circle()
                    .fill(iconColor(entry).opacity(0.14))
                    .frame(width: 28, height: 28)
                Image(systemName: entry.kind.systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(iconColor(entry))
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(ClinicPalette.primaryText)
                    .multilineTextAlignment(.leading)
                if !entry.detail.isEmpty {
                    Text(entry.detail)
                        .font(.callout)
                        .foregroundStyle(ClinicPalette.secondaryText)
                        .multilineTextAlignment(.leading)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let statusTitle = entry.statusTitle, let tone = entry.statusTone {
                ClinicStatusBadge(title: statusTitle, tone: tone)
                    .padding(.top, 4)
            }
            if entry.opensRecording {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ClinicPalette.secondaryText)
                    .padding(.top, 8)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func isChange(_ entry: ChildTimelineEntry) -> Bool {
        entry.statusTitle == "Change" || entry.statusTitle == "Change detected"
    }

    private func iconColor(_ entry: ChildTimelineEntry) -> Color {
        if entry.kind == .recording, let tone = entry.statusTone {
            return ClinicPalette.foreground(tone)
        }
        return ClinicPalette.secondaryText
    }

    private func dayTitle(_ day: Date) -> String {
        day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
    }
}
