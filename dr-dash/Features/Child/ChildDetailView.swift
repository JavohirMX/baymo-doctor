import AppKit
import SwiftData
import SwiftUI

/// One child's clinic record: timeline, ECG trends, and the symptom journal.
struct ChildDetailView: View {
    var child: Child
    var backTitle: String
    var onBack: () -> Void

    @State private var path = NavigationPath()
    @State private var tab: ChildDetailTab = .timeline
    @State private var range: ChildTimelineRange = .sinceLastSync
    @State private var showsEdit = false
    @State private var showsSync = false
    @State private var showsLink = false
    @State private var measuredBaseline: ChildBaselineMeasure?
    @State private var baselineMeasureFinished = false

    var body: some View {
        NavigationStack(path: $path) {
            detail
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        Button(action: onBack) {
                            Label(backTitle, systemImage: "chevron.backward")
                        }
                        .accessibilityLabel(backTitle)
                    }
                    ToolbarSpacer(.flexible)
                    if child.linkState != .linked {
                        ToolbarItem {
                            Button("Link phone") { showsLink = true }
                                .buttonStyle(.glass)
                        }
                    }
                    ToolbarItem {
                        Button("Sync phone") { showsSync = true }
                            .buttonStyle(.glass)
                    }
                    if showsReviewButton {
                        ToolbarItem {
                            Button("Mark as reviewed") {
                                ClinicReview.markReviewed(Array(child.recordings), in: activeFilter)
                            }
                            .buttonStyle(.glassProminent)
                            .disabled(!canMarkReviewed)
                        }
                    }
                }
                .navigationDestination(for: UUID.self) { recordingID in
                    if let recording = child.recordings.first(where: { $0.id == recordingID }) {
                        ECGViewerView(child: child, recording: recording)
                    } else {
                        ContentUnavailableView("Recording unavailable", systemImage: "waveform.path.ecg")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(ClinicPalette.canvas)
                    }
                }
                .onChange(of: child.id) { _, _ in
                    resetBrowsing()
                }
                .task(id: child.currentBaseline?.id) {
                    await measureBaseline()
                }
        }
        .sheet(isPresented: $showsEdit) {
            EditChildSheet(child: child)
        }
        .sheet(isPresented: $showsSync) {
            SyncPhoneSheet(child: child)
        }
        .sheet(isPresented: $showsLink) {
            LinkPhoneSheet(child: child)
        }
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 0) {
            childBar
            Rectangle().fill(ClinicPalette.separator).frame(height: 1)
            header
            Rectangle().fill(ClinicPalette.separator).frame(height: 1)
            if showsEmptyState {
                emptyState
            } else {
                if child.recordings.isEmpty {
                    recordingsBanner
                    Divider()
                }
                controls
                HStack(alignment: .top, spacing: 0) {
                    tabContent
                        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    Divider()
                    ChildRangeSummaryView(summary: rangeSummary)
                        .frame(width: 300)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ClinicPalette.canvas)
    }

    private var childBar: some View {
        HStack(spacing: 12) {
            Text(prominentName)
                .font(.headline)
                .foregroundStyle(ClinicPalette.primaryText)
            Spacer(minLength: 12)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            Text(ChildDetailLogic.initials(nickname: child.nickname, fullName: child.fullName))
                .font(.title3.weight(.semibold))
                .foregroundStyle(ClinicPalette.accentInk)
                .frame(width: 52, height: 52)
                .background(ClinicPalette.accentInk.opacity(0.14), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(prominentName)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(ClinicPalette.primaryText)
                    if showsFullNameUnderNickname {
                        Text(child.fullName)
                            .font(.title3)
                            .foregroundStyle(ClinicPalette.secondaryText)
                    }
                    Button("Edit patient") { showsEdit = true }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)
                        .accessibilityIdentifier("Edit")
                }
                Text(identityLine)
                    .font(.callout)
                    .foregroundStyle(ClinicPalette.secondaryText)
                Text(conditionLine)
                    .font(.body)
                    .foregroundStyle(conditionIsEmpty ? ClinicPalette.secondaryText : ClinicPalette.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text("Recording schedule")
                    .font(.caption)
                    .foregroundStyle(ClinicPalette.secondaryText)
                Text(scheduleText)
                    .font(.callout)
                    .foregroundStyle(ClinicPalette.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 280, alignment: .leading)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .accessibilityElement(children: .contain)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            sectionPicker
            Spacer(minLength: 12)
            rangeMenu
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
    }

    private var rangeMenu: some View {
        Menu {
            Picker("Range", selection: $range) {
                ForEach(ChildTimelineRange.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Text("Range: \(range.title)")
        }
        .fixedSize()
    }

    private var sectionPicker: some View {
        ClinicSegmentedPicker(selection: $tab)
            .fixedSize()
            .accessibilityLabel("Section")
    }

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .timeline:
            ChildTimelineView(days: timelineDays, emptyMessage: timelineEmptyMessage)
        case .ecgs:
            ChildECGTrendsView(
                rows: ecgRows,
                series: trendSeries,
                showsBaselineGap: showsBaselineGap,
                onOpen: { path.append($0) }
            )
        case .diary:
            ChildDiaryView(lists: diaryLists)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No recordings yet", systemImage: "waveform.path.ecg")
        } description: {
            Text("Recordings appear here after the parent's phone is synced.")
        } actions: {
            ClinicPrimaryButton(title: "Sync phone", systemImage: "iphone") {
                showsSync = true
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var recordingsBanner: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "waveform.path.ecg")
                .font(.title2)
                .foregroundStyle(ClinicPalette.accentInk)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("No recordings yet")
                    .font(.headline)
                    .foregroundStyle(ClinicPalette.primaryText)
                Text("Recordings appear here after the parent's phone is synced.")
                    .font(.callout)
                    .foregroundStyle(ClinicPalette.secondaryText)
            }
            Spacer(minLength: 12)
            ClinicPrimaryButton(title: "Sync phone", systemImage: "iphone") {
                showsSync = true
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var showsEmptyState: Bool {
        child.recordings.isEmpty && child.diaryEvents.isEmpty
    }

    private var showsReviewButton: Bool {
        !child.recordings.isEmpty
    }

    private var canMarkReviewed: Bool {
        !ClinicListLogic.unreviewedIDs(recordingFacts.map(\.attention), in: activeFilter).isEmpty
    }

    private var prominentName: String {
        let nickname = child.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        return nickname.isEmpty ? child.fullName : nickname
    }

    private var showsFullNameUnderNickname: Bool {
        let nickname = child.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nickname.isEmpty else { return false }
        return nickname.localizedStandardCompare(child.fullName) != .orderedSame
    }

    private var identityLine: String {
        let born = child.birthDate.formatted(.dateTime.day().month(.abbreviated).year())
        return "\(ClinicListLogic.ageCompact(born: child.birthDate)), \(child.sex.title.lowercased()), born \(born)"
    }

    private var conditionIsEmpty: Bool {
        child.conditionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var conditionLine: String {
        conditionIsEmpty ? "No condition recorded" : child.conditionText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var scheduleText: String {
        guard let scheduleFact else { return "No schedule set" }
        return ChildDetailLogic.scheduleSummary(scheduleFact)
    }

    private var lastSyncText: String {
        guard let lastSyncDate = child.lastSyncDate else { return "Not synced yet" }
        return "Last sync \(lastSyncDate.formatted(date: .abbreviated, time: .shortened))"
    }

    private var timelineEmptyMessage: String {
        if ChildDetailLogic.isUnsynced(activeFilter) {
            return "This child has not been synced."
        }
        if range == .sinceLastSync, !recordingFacts.isEmpty || !diaryFacts.isEmpty {
            return "Nothing new since the last sync. Choose All, Last 7 days, or Last 30 days to see earlier events."
        }
        return "Nothing in this range."
    }

    /// Shown after measurement, when the baseline trace produced neither number.
    private var showsBaselineGap: Bool {
        guard baselineMeasureFinished, let baselineFact else { return false }
        return baselineFact.heartRate == nil && baselineFact.qrsMS == nil
    }

    private var activeFilter: ClinicDateFilter {
        ChildDetailLogic.dateFilter(range: range, day: nil, lastSyncDate: child.lastSyncDate)
    }

    private var scheduleFact: ChildScheduleFact? {
        guard let schedule = child.schedule else { return nil }
        return ChildScheduleFact(
            cadence: schedule.cadence,
            timesPerWeek: schedule.timesPerWeek,
            weekdays: schedule.weekdays,
            durationMinutes: schedule.durationMinutes,
            reminderHour: schedule.reminderHour,
            reminderMinute: schedule.reminderMinute,
            recordWhenSymptoms: schedule.recordWhenSymptoms
        )
    }

    private var recordingFacts: [ChildRecordingFact] {
        child.recordings.map { recording in
            ChildRecordingFact(
                id: recording.id,
                startDate: recording.startDate,
                duration: recording.duration,
                status: recording.parentStatus,
                heartRate: recording.heartRate,
                prMS: recording.prMS,
                qrsMS: recording.qrsMS,
                axisDegrees: recording.axisDegrees,
                signalQuality: recording.signalQuality,
                reviewed: recording.reviewed
            )
        }
    }

    private var diaryFacts: [ChildDiaryFact] {
        child.diaryEvents.map { event in
            ChildDiaryFact(
                id: event.id,
                kind: event.kind,
                startedAt: event.startedAt,
                text: event.text,
                symptomName: event.symptomName
            )
        }
    }

    private var baselineFact: ChildBaselineFact? {
        guard let baseline = child.currentBaseline else { return nil }
        let measured = measuredBaseline?.id == baseline.id ? measuredBaseline : nil
        return ChildBaselineFact(
            id: baseline.id,
            version: baseline.version,
            fileName: baseline.fileName,
            recordedAt: baseline.recordedAt,
            duration: baseline.recording.duration,
            heartRate: measured?.heartRate,
            prMS: measured?.prMS,
            qrsMS: measured?.qrsMS,
            axisDegrees: measured?.axisDegrees,
            signalQuality: ""
        )
    }

    private var adherence: ChildAdherence {
        ChildDetailLogic.adherence(
            schedule: scheduleFact,
            recordings: recordingFacts,
            birthDate: child.birthDate,
            filter: activeFilter
        )
    }

    private var timelineDays: [ChildTimelineDay] {
        ChildDetailLogic.timeline(recordings: recordingFacts, diary: diaryFacts, filter: activeFilter)
    }

    private var rangeSummary: ChildRangeSummary {
        ChildDetailLogic.summary(
            range: range,
            day: nil,
            filter: activeFilter,
            recordings: recordingFacts,
            diary: diaryFacts
        )
    }

    private var ecgRows: [ChildECGRow] {
        ChildDetailLogic.ecgRows(recordings: recordingFacts, baseline: baselineFact, filter: activeFilter)
    }

    private var trendSeries: ChildTrendSeries {
        let missedDays = adherence.marks.filter { $0.state == .missed }.map(\.day)
        return ChildDetailLogic.trends(
            recordings: recordingFacts,
            extraMissedDays: missedDays,
            baselineHeartRate: baselineFact?.heartRate,
            baselineQRS: baselineFact?.qrsMS,
            filter: activeFilter
        )
    }

    private var diaryLists: ChildDiaryLists {
        ChildDetailLogic.diaryLists(diary: diaryFacts, filter: activeFilter)
    }

    private func measureBaseline() async {
        baselineMeasureFinished = false
        guard let baseline = child.currentBaseline else {
            measuredBaseline = nil
            baselineMeasureFinished = true
            return
        }
        let id = baseline.id
        let payload = baseline.recording
        let recordedAt = baseline.recordedAt
        let measured = await Task.detached(priority: .userInitiated) {
            ChildBaselineMeasure.measure(id: id, payload: payload, recordedAt: recordedAt)
        }.value
        guard !Task.isCancelled else { return }
        measuredBaseline = measured
        baselineMeasureFinished = true
    }

    private func resetBrowsing() {
        range = .sinceLastSync
        tab = .timeline
        path = NavigationPath()
        showsEdit = false
        showsSync = false
        showsLink = false
    }
}

/// macOS 27 value picker. The bordered control draws the selected segment's bezel.
private struct ClinicSegmentedPicker: NSViewRepresentable {
    @Binding var selection: ChildDetailTab

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(
            labels: ChildDetailTab.allCases.map(\.title),
            trackingMode: .selectOne,
            target: context.coordinator,
            action: #selector(Coordinator.changed(_:))
        )
        control.segmentStyle = .rounded
        control.segmentDistribution = .fit
        control.role = .valueSelection
        control.borderShape = .capsule
        control.controlSize = .regular
        control.setContentHuggingPriority(.required, for: .horizontal)
        control.setContentCompressionResistancePriority(.required, for: .horizontal)
        control.sizeToFit()
        select(selection, on: control)
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.selection = $selection
        select(selection, on: control)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSSegmentedControl, context: Context) -> CGSize? {
        let size = nsView.fittingSize
        guard size.width > 1, size.height > 1 else { return CGSize(width: 360, height: 28) }
        return size
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    private func select(_ tab: ChildDetailTab, on control: NSSegmentedControl) {
        let index = ChildDetailTab.allCases.firstIndex(of: tab) ?? 0
        guard control.selectedSegment != index else { return }
        control.selectedSegment = index
    }

    final class Coordinator: NSObject {
        var selection: Binding<ChildDetailTab>

        init(selection: Binding<ChildDetailTab>) {
            self.selection = selection
        }

        @objc func changed(_ sender: NSSegmentedControl) {
            let tabs = ChildDetailTab.allCases
            let index = sender.selectedSegment
            guard tabs.indices.contains(index) else { return }
            selection.wrappedValue = tabs[index]
        }
    }
}

#Preview {
    let library = ClinicLibrary(showsDemoClinic: false, inMemory: true)
    let child = Child.add(
        to: library.container.mainContext,
        fullName: "Amina Yusuf",
        nickname: "Amina",
        birthDate: Calendar.current.date(byAdding: .year, value: -7, to: .now) ?? .now,
        sex: .female,
        conditionText: "Follow-up"
    )
    ChildDetailView(child: child, backTitle: "All patients", onBack: {})
        .environment(library)
        .modelContainer(library.container)
        .frame(width: 1100, height: 760)
}
