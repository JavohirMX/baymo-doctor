import Charts
import SwiftUI

struct ChildECGTrendsView: View {
    var rows: [ChildECGRow]
    var series: ChildTrendSeries
    var showsBaselineGap: Bool
    var onOpen: (UUID) -> Void

    var body: some View {
        if rows.isEmpty {
            ContentUnavailableView {
                Label("No recordings in this range", systemImage: "waveform.path.ecg")
            } description: {
                Text("Heart rate and QRS appear here for recordings in the selected range.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 12) {
                            heartChart
                                .frame(minWidth: 0, maxWidth: .infinity)
                            qrsChart
                                .frame(minWidth: 0, maxWidth: .infinity)
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            heartChart
                            qrsChart
                        }
                    }

                    if showsBaselineGap {
                        Text("No heart rate or QRS could be measured from the current baseline, so these charts have no reference line.")
                            .font(.caption)
                            .foregroundStyle(ClinicPalette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    chartLegend

                    ScrollView(.horizontal) {
                        table
                            .frame(minHeight: 340)
                    }
                    .frame(maxWidth: .infinity, minHeight: 340, maxHeight: 420)
                }
                .padding(20)
            }
            .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var table: some View {
        Table(rows) {
            TableColumn("Recording") { row in
                recordingCell(row)
            }
            .width(min: 180, ideal: 230)

            TableColumn("Result") { row in
                ClinicStatusBadge(title: row.resultTitle, tone: row.resultTone)
            }
            .width(min: 110, ideal: 130)

            TableColumn("Heart rate") { row in
                Text(row.heartRate)
            }
            .width(min: 88, ideal: 104)

            TableColumn("PR") { row in
                Text(row.pr)
            }
            .width(min: 64, ideal: 80)

            TableColumn("QRS") { row in
                Text(row.qrs)
            }
            .width(min: 64, ideal: 80)

            TableColumn("Axis") { row in
                Text(row.axis)
            }
            .width(min: 64, ideal: 80)

            TableColumn("Signal") { row in
                Text(row.signal)
                    .lineLimit(1)
            }
            .width(min: 80, ideal: 120)

            TableColumn("Length") { row in
                Text(row.length)
            }
            .width(min: 72, ideal: 96)
        }
        .frame(minWidth: 880, minHeight: 340)
    }

    private var heartChart: some View {
        trendChart(
            title: "Heart rate",
            unit: "bpm",
            empty: "No heart rate in this range.",
            values: heartPoints,
            baseline: series.baselineHeartRate,
            fallback: 40...160
        )
    }

    private var qrsChart: some View {
        trendChart(
            title: "QRS duration",
            unit: "ms",
            empty: "No QRS duration in this range.",
            values: qrsPoints,
            baseline: series.baselineQRS,
            fallback: 40...200
        )
    }

    private var heartPoints: [PlotPoint] {
        series.points.compactMap { point in
            guard let value = point.heartRate else { return nil }
            return PlotPoint(id: point.id, date: point.date, value: value, tone: point.tone)
        }
    }

    private var qrsPoints: [PlotPoint] {
        series.points.compactMap { point in
            guard let value = point.qrsMS else { return nil }
            return PlotPoint(id: point.id, date: point.date, value: value, tone: point.tone)
        }
    }

    private func trendChart(
        title: String,
        unit: String,
        empty: String,
        values: [PlotPoint],
        baseline: Int?,
        fallback: ClosedRange<Int>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(unit)
                .font(.caption)
                .foregroundStyle(ClinicPalette.secondaryText)
            if values.isEmpty, baseline == nil, series.missedDays.isEmpty {
                Text(empty)
                    .font(.callout)
                    .foregroundStyle(ClinicPalette.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 180, alignment: .leading)
            } else {
                Chart {
                    ForEach(values) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value(title, point.value)
                        )
                        .foregroundStyle(ClinicPalette.accentInk)
                        .interpolationMethod(.linear)
                        PointMark(
                            x: .value("Date", point.date),
                            y: .value(title, point.value)
                        )
                        .foregroundStyle(ClinicPalette.foreground(point.tone))
                        .symbolSize(60)
                    }
                    if let baseline {
                        RuleMark(y: .value("Baseline", baseline))
                            .foregroundStyle(ClinicPalette.secondaryText)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .annotation(position: .top, alignment: .leading) {
                                Text("Baseline \(baseline) \(unit)")
                                    .font(.caption2)
                                    .foregroundStyle(ClinicPalette.secondaryText)
                            }
                    }
                    ForEach(series.missedDays, id: \.self) { day in
                        RuleMark(x: .value("Missed", day))
                            .foregroundStyle(ClinicPalette.foreground(.amber).opacity(0.75))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    }
                }
                .chartYScale(domain: domain(values: values.map(\.value), baseline: baseline, fallback: fallback))
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4))
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: 180)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(title), \(values.count) recordings")
            }
        }
        .padding(12)
        .background(ClinicPalette.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private var chartLegend: some View {
        if series.baselineHeartRate != nil || series.baselineQRS != nil || !series.missedDays.isEmpty {
            legendRow
        }
    }

    private var legendRow: some View {
        HStack(spacing: 16) {
            if series.baselineHeartRate != nil || series.baselineQRS != nil {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(ClinicPalette.secondaryText)
                        .frame(width: 16, height: 1)
                    Text("Baseline")
                }
            }
            if !series.missedDays.isEmpty {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(ClinicPalette.foreground(.amber))
                        .frame(width: 2, height: 12)
                    Text("Missed day")
                }
            }
        }
        .font(.caption)
        .foregroundStyle(ClinicPalette.secondaryText)
    }

    private func domain(values: [Int], baseline: Int?, fallback: ClosedRange<Int>) -> ClosedRange<Int> {
        var numbers = values
        if let baseline {
            numbers.append(baseline)
        }
        guard let low = numbers.min(), let high = numbers.max() else { return fallback }
        if low == high {
            let pad = max(8, abs(low) / 10)
            return (low - pad)...(high + pad)
        }
        let pad = max(4, (high - low) / 6)
        return (low - pad)...(high + pad)
    }

    @ViewBuilder
    private func recordingCell(_ row: ChildECGRow) -> some View {
        if row.canOpen, let recordingID = row.recordingID {
            Button {
                onOpen(recordingID)
            } label: {
                cellLabel(row)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(row.resultTitle == "Change" ? "ecg.row.change" : "ecg.row")
        } else {
            cellLabel(row)
        }
    }

    private func cellLabel(_ row: ChildECGRow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.title)
            Text(row.subtitle)
                .font(.caption)
                .foregroundStyle(ClinicPalette.secondaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PlotPoint: Identifiable {
    var id: UUID
    var date: Date
    var value: Int
    var tone: ClinicTone
}
