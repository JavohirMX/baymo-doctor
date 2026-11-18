import SwiftUI

struct ChildRangeSummaryView: View {
    var summary: ChildRangeSummary

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.title)
                        .font(.headline)
                        .foregroundStyle(ClinicPalette.primaryText)
                    Text(summary.detail)
                        .font(.caption)
                        .foregroundStyle(ClinicPalette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Recording results")
                        .font(.caption)
                        .foregroundStyle(ClinicPalette.secondaryText)
                    ForEach(summary.results) { row in
                        HStack(spacing: 8) {
                            if let tone = row.tone {
                                ClinicStatusBadge(title: row.title, tone: tone)
                            } else {
                                Text(row.title)
                                    .font(.callout)
                            }
                            Spacer(minLength: 8)
                            Text("\(row.count)")
                                .font(.body.monospacedDigit())
                                .foregroundStyle(ClinicPalette.secondaryText)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Symptoms reported")
                        .font(.caption)
                        .foregroundStyle(ClinicPalette.secondaryText)
                    if summary.symptoms.isEmpty {
                        Text("No symptoms in this range.")
                            .font(.callout)
                            .foregroundStyle(ClinicPalette.secondaryText)
                    } else {
                        ForEach(summary.symptoms) { row in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(row.title)
                                    .font(.callout)
                                Spacer(minLength: 8)
                                Text("\(row.count)")
                                    .font(.callout.monospacedDigit())
                                    .foregroundStyle(ClinicPalette.secondaryText)
                            }
                        }
                    }
                }

                Text(summary.vestNote)
                    .font(.caption)
                    .foregroundStyle(ClinicPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(ClinicPalette.field, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
    }
}
