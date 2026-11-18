import Foundation
import SwiftData
import SwiftUI

struct ECGViewerView: View {
    var child: Child
    var recording: ClinicRecording

    @State private var selectedRecordingID: UUID?
    @State private var selectedLead: ECGLead = .ii
    @State private var compareBaselineID: UUID?
    @State private var layout: ECGCompareLayout = .stacked
    @State private var reading = ECGReading.placeholder
    @State private var payloadCache = ECGPayloadCache()

    private enum ECGCompareLayout: String, CaseIterable, Identifiable {
        case stacked
        case overlay

        var id: String { rawValue }

        var title: String {
            switch self {
            case .stacked: "Stacked"
            case .overlay: "Overlay"
            }
        }
    }

    private enum Copy {
        static let dash = "—"
        static let leads: [ECGLead] = [.i, .ii, .iii, .aVR, .aVL, .aVF, .v1]
    }

    var body: some View {
        VStack(spacing: 0) {
            viewerBar
            Rectangle().fill(ClinicPalette.separator).frame(height: 1)
            controls
            Rectangle().fill(ClinicPalette.separator).frame(height: 1)
            HStack(spacing: 0) {
                paperColumn
                Divider()
                inspector
            }
            Divider()
            Label(ChildDetailLogic.vestNote, systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(ClinicPalette.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .accessibilityIdentifier("ecg.disclaimer")
        }
        .background(ClinicPalette.canvas)
        .accessibilityIdentifier("ecg.viewer")
        .toolbar {
            ToolbarSpacer(.flexible)
            ToolbarItem {
                Button(activeRecording.reviewed ? "Reviewed" : "Mark as reviewed") {
                    ClinicReview.markReviewed(activeRecording)
                }
                .buttonStyle(.glassProminent)
                .disabled(activeRecording.reviewed)
                .accessibilityIdentifier("ecg.markReviewed")
            }
        }
        .task(id: measurementToken) { await measure() }
        .onChange(of: child.id) { _, _ in
            selectedRecordingID = nil
            compareBaselineID = nil
            selectedLead = .ii
        }
        .onChange(of: recording.id) { _, _ in
            selectedRecordingID = nil
        }
    }

    // MARK: - Recording

    private var activeRecording: ClinicRecording {
        guard let selectedRecordingID else { return recording }
        return child.recordings.first { $0.id == selectedRecordingID } ?? recording
    }

    private var availableLeads: Set<ECGLead> {
        payloadCache.availableLeads(for: activeRecording)
    }

    private var resolvedLead: ECGLead {
        if availableLeads.contains(selectedLead) { return selectedLead }
        if availableLeads.contains(.ii) { return .ii }
        if availableLeads.contains(.i) { return .i }
        return Copy.leads.first { availableLeads.contains($0) } ?? selectedLead
    }

    private var numbersAreCurrent: Bool {
        reading.isReady && reading.recordingID == activeRecording.id
    }

    private var stripIsCurrent: Bool {
        numbersAreCurrent && reading.lead == resolvedLead
    }

    private var compareIsCurrent: Bool {
        stripIsCurrent && reading.compareID == compareBaselineID
    }

    private var recordingSubtitle: String {
        "\(dateTime(activeRecording.startDate)) · \(durationText)"
    }

    private var childNickname: String {
        let nickname = child.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        return nickname.isEmpty ? child.fullName : nickname
    }

    private var durationText: String {
        let seconds = max(0, Int(activeRecording.duration.rounded()))
        let minutes = seconds / 60
        let remainder = seconds % 60
        if minutes > 0, remainder == 0 { return "\(minutes) min" }
        if minutes > 0 { return "\(minutes) min \(remainder) s" }
        return "\(seconds) s"
    }

    private var measurementToken: String {
        let baseline = child.currentBaseline
        return [
            activeRecording.id.uuidString,
            String(ECGPayloadCache.stamp(activeRecording.samplesData)),
            baseline?.id.uuidString ?? "-",
            String(baseline.map { ECGPayloadCache.stamp($0.recordingData) } ?? 0),
            compareBaselineID?.uuidString ?? "-",
            resolvedLead.rawValue,
            String(activeRecording.heartRate ?? Int.min),
            String(activeRecording.prMS ?? Int.min),
            String(activeRecording.qrsMS ?? Int.min)
        ].joined(separator: "|")
    }

    private func measure() async {
        let token = measurementToken
        let recordingID = activeRecording.id
        let payload = payloadCache.payload(for: activeRecording)
        let stored = ECGStoredIntervals(
            heartRate: activeRecording.heartRate,
            prMS: activeRecording.prMS,
            qrsMS: activeRecording.qrsMS
        )
        let baselineData = child.currentBaseline?.recordingData ?? Data()
        let compareID = compareBaselineID
        let compareData = baselineVersions.first { $0.id == compareID }?.recordingData
        let lead = resolvedLead
        let measured = await Task.detached(priority: .userInitiated) {
            let baseline = (try? StoredECGPayload.decode(baselineData)) ?? .empty
            let compare = compareData.flatMap { try? StoredECGPayload.decode($0) }
            return ECGViewerMeasurement.reading(
                recordingID: recordingID,
                payload: payload,
                stored: stored,
                baseline: baseline,
                compare: compare,
                compareID: compareID,
                lead: lead
            )
        }.value
        guard !Task.isCancelled, token == measurementToken else { return }
        reading = measured
    }

    // MARK: - Controls

    private var viewerBar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("ECG, \(dateTime(activeRecording.startDate))")
                    .font(.headline)
                    .foregroundStyle(ClinicPalette.primaryText)
                Text(child.nickname.isEmpty ? child.fullName : child.nickname)
                    .font(.caption)
                    .foregroundStyle(ClinicPalette.secondaryText)
            }
            Spacer(minLength: 12)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                ClinicStatusBadge(
                    title: activeRecording.parentStatus.listTitle,
                    tone: activeRecording.parentStatus.tone
                )
                if numbersAreCurrent {
                    Text(reading.changed
                         ? "Heart rate and QRS duration are outside \(childNickname)'s usual range compared with the baseline."
                         : reading.sentence)
                        .font(.callout)
                        .foregroundStyle(ClinicPalette.primaryText)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }

            HStack(alignment: .center, spacing: 12) {
                Text("Lead")
                    .font(.callout)
                    .foregroundStyle(ClinicPalette.secondaryText)
                Picker("Lead", selection: $selectedLead) {
                    ForEach(Copy.leads) { lead in
                        Text(lead.rawValue)
                            .tag(lead)
                            .disabled(!availableLeads.contains(lead))
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("Lead")
                Picker("Compare", selection: $compareBaselineID) {
                    Text("None").tag(UUID?.none)
                    ForEach(baselineVersions, id: \.id) { version in
                        Text(compareTitle(version)).tag(UUID?.some(version.id))
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 280)
                .accessibilityIdentifier("ecg.compare")

                Picker("View", selection: $layout) {
                    ForEach(ECGCompareLayout.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(compareBaselineID == nil)
                .accessibilityLabel("View")
                .accessibilityIdentifier("ecg.layout")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var baselineVersions: [BaselineVersion] {
        child.baselines.sorted { lhs, rhs in
            if lhs.version != rhs.version { return lhs.version > rhs.version }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            return lhs.id.uuidString > rhs.id.uuidString
        }
    }

    private func compareTitle(_ version: BaselineVersion) -> String {
        let name = version.fileName.isEmpty ? "Baseline \(version.version)" : version.fileName
        if version.id == child.currentBaseline?.id {
            return "Current baseline · \(name)"
        }
        let date = version.recordedAt.formatted(date: .abbreviated, time: .omitted)
        return "\(name) · \(date)"
    }

    private var comparePaperTitle: String {
        guard let compareBaselineID,
              let version = baselineVersions.first(where: { $0.id == compareBaselineID })
        else { return "Baseline" }
        if version.id == child.currentBaseline?.id { return "Current baseline" }
        return version.fileName.isEmpty ? "Baseline \(version.version)" : version.fileName
    }

    // MARK: - Paper

    private var paperColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ECGPaperView(
                    title: "This ECG",
                    leadName: resolvedLead.rawValue,
                    primary: stripIsCurrent ? reading.strip : .empty,
                    overlay: overlayStrip,
                    emptyMessage: stripIsCurrent ? "No \(resolvedLead.rawValue) trace in this recording." : nil,
                    showsProgress: !stripIsCurrent
                )
                if layout == .overlay, compareBaselineID != nil {
                    overlayStatus
                }
                if layout == .stacked, compareBaselineID != nil {
                    stackedCompare
                }
                sinceLastSync
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var overlayStrip: ECGStripDrawing? {
        guard layout == .overlay, compareIsCurrent else { return nil }
        return reading.compareStrip
    }

    @ViewBuilder
    private var overlayStatus: some View {
        if !compareIsCurrent {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Measuring the baseline strip.")
                    .font(.callout)
                    .foregroundStyle(ClinicPalette.secondaryText)
            }
        } else if reading.compareMissingLead {
            Text("The baseline has no lead \(resolvedLead.rawValue).")
                .font(.callout)
                .foregroundStyle(ClinicPalette.secondaryText)
        }
    }

    @ViewBuilder
    private var stackedCompare: some View {
        if compareIsCurrent, let compare = reading.compareStrip {
            ECGPaperView(
                title: comparePaperTitle,
                leadName: resolvedLead.rawValue,
                primary: compare,
                overlay: nil,
                emptyMessage: nil,
                showsProgress: false
            )
        } else if compareIsCurrent, reading.compareMissingLead {
            Text("The baseline has no lead \(resolvedLead.rawValue).")
                .font(.callout)
                .foregroundStyle(ClinicPalette.secondaryText)
        } else {
            ECGPaperView(
                title: comparePaperTitle,
                leadName: resolvedLead.rawValue,
                primary: .empty,
                overlay: nil,
                emptyMessage: nil,
                showsProgress: true
            )
        }
    }

    private var sinceLastSync: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Since last sync")
                .font(.headline)
            if child.lastSyncDate == nil {
                Text("This child has not synced yet.")
                    .foregroundStyle(ClinicPalette.secondaryText)
            } else if otherRecordings.isEmpty {
                Text("No other recordings since the last sync.")
                    .foregroundStyle(ClinicPalette.secondaryText)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(otherRecordings, id: \.id) { item in
                        Button {
                            selectedRecordingID = item.id
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(dateTime(item.startDate))
                                    Text(item.parentStatus.listTitle)
                                        .font(.caption)
                                        .foregroundStyle(ClinicPalette.secondaryText)
                                }
                                Spacer(minLength: 8)
                                if let heartRate = item.heartRate {
                                    Text("\(heartRate) bpm")
                                        .font(.caption)
                                        .foregroundStyle(ClinicPalette.secondaryText)
                                }
                                if item.reviewed {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(ClinicPalette.foreground(.green))
                                        .accessibilityLabel("Reviewed")
                                }
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("ecg.other.\(item.id.uuidString)")
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    private var otherRecordings: [ClinicRecording] {
        let filter = ChildDetailLogic.dateFilter(
            range: .sinceLastSync,
            day: nil,
            lastSyncDate: child.lastSyncDate
        )
        return child.recordings
            .filter { $0.id != activeRecording.id && filter.contains($0.startDate) }
            .sorted { lhs, rhs in
                if lhs.startDate != rhs.startDate { return lhs.startDate > rhs.startDate }
                return lhs.id.uuidString > rhs.id.uuidString
            }
    }

    // MARK: - Inspector

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                measurementsSection
                signalSection
                diarySection
                noteSection
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 360)
    }

    private var measurementsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Measurements")
                .font(.headline)
            if numbersAreCurrent {
                Text(reading.sentence)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("ecg.result")
                measurementTable
                if let lead = reading.measurementLead, !reading.storedWithRecording {
                    Text("Heart rate, PR, and QRS are measured on lead \(lead.rawValue).")
                        .font(.caption)
                        .foregroundStyle(ClinicPalette.secondaryText)
                }
                if child.currentBaseline == nil {
                    Text("No current baseline.")
                        .font(.caption)
                        .foregroundStyle(ClinicPalette.secondaryText)
                } else {
                    Text("The baseline column is this child's current baseline.")
                        .font(.caption)
                        .foregroundStyle(ClinicPalette.secondaryText)
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Measuring heart rate, PR, and QRS.")
                        .font(.callout)
                        .foregroundStyle(ClinicPalette.secondaryText)
                }
            }
        }
    }

    private var measurementTable: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
            GridRow {
                Text("")
                columnTitle("This ECG")
                columnTitle("Baseline")
                columnTitle("Change")
            }
            measurementRow(
                "Heart rate",
                unit: "bpm",
                current: reading.heartRate,
                baseline: reading.baselineHeartRate,
                changed: reading.heartRateChanged
            )
            measurementRow(
                "PR",
                unit: "ms",
                current: reading.prMS,
                baseline: reading.baselinePRMS,
                changed: false
            )
            measurementRow(
                "QRS",
                unit: "ms",
                current: reading.qrsMS,
                baseline: reading.baselineQRSMS,
                changed: reading.qrsChanged
            )
            measurementRow(
                "Axis",
                unit: "°",
                current: reading.axisDegrees,
                baseline: reading.baselineAxisDegrees,
                changed: false
            )
        }
        .accessibilityIdentifier("ecg.measurements")
    }

    private func columnTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(ClinicPalette.secondaryText)
    }

    private func measurementRow(
        _ title: String,
        unit: String,
        current: Int?,
        baseline: Int?,
        changed: Bool
    ) -> some View {
        GridRow {
            Text("\(title) (\(unit))")
            Text(number(current))
                .monospacedDigit()
            Text(number(baseline))
                .monospacedDigit()
                .foregroundStyle(ClinicPalette.secondaryText)
            HStack(spacing: 6) {
                if changed {
                    Circle()
                        .fill(ClinicPalette.foreground(.amber))
                        .frame(width: 8, height: 8)
                        .accessibilityLabel("Changed")
                }
                Text(delta(current, baseline))
                    .monospacedDigit()
                    .foregroundStyle(changed ? ClinicPalette.foreground(.amber) : ClinicPalette.primaryText)
            }
        }
        .font(.callout)
    }

    private var signalSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Signal quality")
                .font(.headline)
            Text(signalQualityText)
                .foregroundStyle(signalQualityText == Copy.dash ? ClinicPalette.secondaryText : ClinicPalette.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("ecg.quality")
        }
    }

    private var signalQualityText: String {
        let trimmed = activeRecording.signalQuality.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Copy.dash : trimmed
    }

    private var diarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("That day")
                .font(.headline)
            Text(activeRecording.startDate.formatted(date: .complete, time: .omitted))
                .font(.caption)
                .foregroundStyle(ClinicPalette.secondaryText)
            if dayEvents.isEmpty {
                Text("Nothing logged that day.")
                    .foregroundStyle(ClinicPalette.secondaryText)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(dayEvents, id: \.id) { event in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(event.kind.title)
                                    .font(.caption.weight(.semibold))
                                Spacer(minLength: 8)
                                Text(event.startedAt.formatted(date: .omitted, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(ClinicPalette.secondaryText)
                            }
                            if let symptom = event.symptomName, !symptom.isEmpty {
                                Text(symptom)
                                    .font(.subheadline.weight(.medium))
                            }
                            if !event.text.isEmpty {
                                Text(event.text)
                                    .font(.subheadline)
                                    .foregroundStyle(ClinicPalette.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("ecg.thatDay")
    }

    private var dayEvents: [DiaryEvent] {
        let day = activeRecording.startDate
        return child.diaryEvents
            .filter { Calendar.current.isDate($0.startedAt, inSameDayAs: day) }
            .sorted { lhs, rhs in
                if lhs.startedAt != rhs.startedAt { return lhs.startedAt < rhs.startedAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Doctor note")
                .font(.headline)
            ECGNoteEditor(recording: activeRecording)
                .id(activeRecording.id)
        }
    }

    private func number(_ value: Int?) -> String {
        value.map(String.init) ?? Copy.dash
    }

    private func delta(_ current: Int?, _ baseline: Int?) -> String {
        guard let current, let baseline else { return Copy.dash }
        let difference = current - baseline
        return difference > 0 ? "+\(difference)" : String(difference)
    }

    private func dateTime(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}

private struct ECGNoteEditor: View {
    @Bindable var recording: ClinicRecording

    var body: some View {
        TextField("Doctor note", text: $recording.doctorNote, axis: .vertical)
            .textFieldStyle(.roundedBorder)
            .lineLimit(3...8)
            .accessibilityIdentifier("ecg.doctorNote")
    }
}

/// Keeps one recording's samples decoded so the lead buttons do not parse the payload on every refresh.
@MainActor
private final class ECGPayloadCache {
    private var identity: ObjectIdentifier?
    private var count = -1
    private var stamp = 0
    private var payload = StoredECGPayload.empty
    private var leads: Set<ECGLead> = []

    func availableLeads(for recording: ClinicRecording) -> Set<ECGLead> {
        refresh(recording)
        return leads
    }

    func payload(for recording: ClinicRecording) -> StoredECGPayload {
        refresh(recording)
        return payload
    }

    static func stamp(_ data: Data) -> Int {
        var hasher = Hasher()
        hasher.combine(data.count)
        for byte in data.prefix(24) {
            hasher.combine(byte)
        }
        if data.count > 24 {
            for byte in data.suffix(24) {
                hasher.combine(byte)
            }
        }
        return hasher.finalize()
    }

    private func refresh(_ recording: ClinicRecording) {
        let nextIdentity = ObjectIdentifier(recording)
        let nextCount = recording.samplesData.count
        let nextStamp = Self.stamp(recording.samplesData)
        if identity == nextIdentity, count == nextCount, stamp == nextStamp { return }
        let decoded = recording.samples
        payload = decoded
        leads = Set(ECGRecording(payload: decoded).availableLeads)
        identity = nextIdentity
        count = nextCount
        stamp = nextStamp
    }
}
