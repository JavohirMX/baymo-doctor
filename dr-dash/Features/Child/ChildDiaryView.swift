import SwiftUI

struct ChildDiaryView: View {
    var lists: ChildDiaryLists
    var scrolls: Bool = true

    var body: some View {
        if scrolls {
            ScrollView { stack }
        } else {
            stack
        }
    }

    private var stack: some View {
        VStack(alignment: .leading, spacing: 28) {
            section(title: "Symptoms", rows: lists.symptoms, empty: "No symptoms in this range.")
            section(title: "Activities", rows: lists.activities, empty: "No activities in this range.")
            section(title: "Journal", rows: lists.journal, empty: "No journal entries in this range.")
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func section(title: String, rows: [ChildDiaryRow], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(ClinicPalette.primaryText)
            if rows.isEmpty {
                Text(empty)
                    .foregroundStyle(ClinicPalette.secondaryText)
            } else {
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(ClinicPalette.secondaryText)
                        Text(row.title)
                            .font(.body.weight(.medium))
                            .foregroundStyle(ClinicPalette.primaryText)
                            .textSelection(.enabled)
                        if !row.detail.isEmpty {
                            Text(row.detail)
                                .font(.callout)
                                .foregroundStyle(ClinicPalette.secondaryText)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Divider()
                }
            }
        }
    }
}
