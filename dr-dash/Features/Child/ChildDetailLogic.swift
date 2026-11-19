import Foundation

/// Ranges the child page can show. `ClinicDateFilter` has no cases for these,
/// so this wraps one. A chosen calendar day replaces the range until it is cleared.
nonisolated enum ChildTimelineRange: String, CaseIterable, Identifiable, Sendable {
    case sinceLastSync
    case all
    case last7Days
    case last30Days

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sinceLastSync: "Since last sync"
        case .all: "All"
        case .last7Days: "Last 7 days"
        case .last30Days: "Last 30 days"
        }
    }
}

nonisolated enum ChildDetailTab: String, CaseIterable, Identifiable, Sendable {
    case timeline
    case ecgs
    case diary

    var id: String { rawValue }

    var title: String {
        switch self {
        case .timeline: "Timeline"
        case .ecgs: "ECGs"
        case .diary: "Symptoms & Journal"
        }
    }
}

nonisolated struct ChildScheduleFact: Equatable, Sendable {
    var cadence: ScheduleCadence
    var timesPerWeek: Int
    var weekdays: [Int]
    var durationMinutes: Int
    var reminderHour: Int
    var reminderMinute: Int
    var recordWhenSymptoms: Bool
}

nonisolated struct ChildRecordingFact: Equatable, Sendable, Identifiable {
    var id: UUID
    var startDate: Date
    var duration: TimeInterval
    var status: ParentRecordingStatus
    var heartRate: Int?
    var prMS: Int?
    var qrsMS: Int?
    var axisDegrees: Int?
    var signalQuality: String
    var reviewed: Bool

    var attention: ClinicAttentionRecording {
        ClinicAttentionRecording(
            id: id,
            startDate: startDate,
            parentStatus: status,
            reviewed: reviewed
        )
    }
}

nonisolated struct ChildDiaryFact: Equatable, Sendable, Identifiable {
    var id: UUID
    var kind: DiaryEventKind
    var startedAt: Date
    var text: String
    var symptomName: String?
}

/// Heart rate, PR, QRS, and axis measured from the current baseline trace.
/// Nil fields mean the measurement did not produce a number.
nonisolated struct ChildBaselineMeasure: Equatable, Sendable {
    var id: UUID
    var heartRate: Int?
    var prMS: Int?
    var qrsMS: Int?
    var axisDegrees: Int?

    static func measure(id: UUID, payload: StoredECGPayload, recordedAt: Date) -> ChildBaselineMeasure {
        let trace = ECGRecording(payload: payload, id: id, startDate: recordedAt)
        let intervals = BeatIntervals.measure(trace)
        return ChildBaselineMeasure(
            id: id,
            heartRate: intervals?.heartRate,
            prMS: intervals?.pr,
            qrsMS: intervals?.qrs,
            axisDegrees: ECGViewerMeasurement.axisDegrees(of: trace)
        )
    }
}

/// Measurements stay nil until `ChildBaselineMeasure` produces them.
nonisolated struct ChildBaselineFact: Equatable, Sendable, Identifiable {
    var id: UUID
    var version: Int
    var fileName: String
    var recordedAt: Date
    var duration: TimeInterval
    var heartRate: Int?
    var prMS: Int?
    var qrsMS: Int?
    var axisDegrees: Int?
    var signalQuality: String
}

nonisolated struct ChildAdherence: Equatable, Sendable {
    var marks: [ChildAdherenceMark]
    var caption: String
}

nonisolated struct ChildAdherenceMark: Identifiable, Equatable, Sendable {
    var id: String
    var day: Date
    var state: State
    var accessibilityLabel: String

    enum State: String, Sendable {
        case recorded
        case missed
    }
}

nonisolated struct ChildTimelineDay: Identifiable, Equatable, Sendable {
    var day: Date
    var entries: [ChildTimelineEntry]

    var id: Date { day }
}

nonisolated struct ChildTimelineEntry: Identifiable, Equatable, Sendable {
    var id: UUID
    var date: Date
    var kind: Kind
    var title: String
    var detail: String
    var statusTitle: String?
    var statusTone: ClinicTone?
    /// True for a recording that is not a missed check. The id is that recording's id.
    var opensRecording: Bool

    enum Kind: String, Sendable {
        case recording
        case symptom
        case activity
        case journal

        var systemImage: String {
            switch self {
            case .recording: "waveform.path.ecg"
            case .symptom: "cross.case"
            case .activity: "figure.walk"
            case .journal: "text.book.closed"
            }
        }

        var label: String {
            switch self {
            case .recording: "Recording"
            case .symptom: "Symptom"
            case .activity: "Activity"
            case .journal: "Journal"
            }
        }
    }
}

nonisolated struct ChildECGRow: Identifiable, Equatable, Sendable {
    var id: String
    var recordingID: UUID?
    var canOpen: Bool
    var title: String
    var subtitle: String
    var resultTitle: String
    var resultTone: ClinicTone
    var heartRate: String
    var pr: String
    var qrs: String
    var axis: String
    var signal: String
    var length: String
}

nonisolated struct ChildTrendSeries: Equatable, Sendable {
    var points: [ChildTrendPoint]
    var missedDays: [Date]
    var baselineHeartRate: Int?
    var baselineQRS: Int?
}

nonisolated struct ChildTrendPoint: Identifiable, Equatable, Sendable {
    var id: UUID
    var date: Date
    var heartRate: Int?
    var qrsMS: Int?
    var tone: ClinicTone
}

nonisolated struct ChildDiaryLists: Equatable, Sendable {
    var symptoms: [ChildDiaryRow]
    var activities: [ChildDiaryRow]
    var journal: [ChildDiaryRow]
}

nonisolated struct ChildDiaryRow: Identifiable, Equatable, Sendable {
    var id: UUID
    var date: Date
    var title: String
    var detail: String
}

nonisolated struct ChildRangeSummary: Equatable, Sendable {
    var title: String
    var detail: String
    var results: [ChildCountRow]
    var symptoms: [ChildCountRow]
    var vestNote: String
}

nonisolated struct ChildCountRow: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var count: Int
    var tone: ClinicTone?
}

/// Schedule text, adherence, timeline grouping, and the ECG table. Not a view.
nonisolated enum ChildDetailLogic {
    /// Recordings come from a 5-electrode vest and are not a standard 12-lead ECG.
    static let vestNote = "Recordings come from a 5-electrode vest and are not a standard 12-lead ECG."

    /// Matches nothing. Used when Since last sync is selected and the child has never synced.
    static let unsynced = ClinicDateFilter.unsynced

    private static let dash = "—"
    private static let dayCap = 400

    static func isUnsynced(_ filter: ClinicDateFilter) -> Bool {
        filter.start == .distantFuture
    }

    static func initials(fullName: String) -> String {
        initials(nickname: "", fullName: fullName)
    }

    /// Nickname initial plus the last name initial, matching the clinic roster circles.
    static func initials(nickname: String, fullName: String) -> String {
        let nick = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = fullName.split { $0.isWhitespace || $0.isNewline }.map(String.init)
        if let first = nick.first, let last = parts.last?.first, nick.caseInsensitiveCompare(fullName) != .orderedSame {
            return String([first, last]).uppercased()
        }
        let letters = parts.prefix(2).compactMap(\.first)
        guard !letters.isEmpty else {
            let fallback = nick.prefix(2)
            return fallback.isEmpty ? "?" : String(fallback).uppercased()
        }
        return String(letters).uppercased()
    }

    static func windowTitle(range: ChildTimelineRange, day: Date?) -> String {
        if let day {
            return day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
        }
        return range.title
    }

    /// Inclusive window. A selected day wins over the range menu.
    /// Since last sync uses `ClinicSyncWindow`: the whole latest live sync, or `lastSyncDate` for demo children.
    /// A child who has never synced matches nothing.
    static func dateFilter(
        range: ChildTimelineRange,
        day: Date?,
        lastSyncDate: Date?,
        latestSyncLowerBound: Date? = nil,
        hasLatestSyncBound: Bool = false,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> ClinicDateFilter {
        if let day {
            return daySpan(day, calendar: calendar)
        }
        switch range {
        case .sinceLastSync:
            return ClinicSyncWindow(
                lastSyncDate: lastSyncDate,
                latestSyncLowerBound: latestSyncLowerBound,
                hasLatestSyncBound: hasLatestSyncBound
            ).sinceLastSyncFilter()
        case .all:
            return .all
        case .last7Days:
            return trailingDays(7, endingAt: now, calendar: calendar)
        case .last30Days:
            return trailingDays(30, endingAt: now, calendar: calendar)
        }
    }

    static func scheduleSummary(_ schedule: ChildScheduleFact, calendar: Calendar = .current) -> String {
        let cadence: String
        switch schedule.cadence {
        case .everyDay:
            cadence = "Every day"
        case .specificWeekdays:
            let names = orderedWeekdays(schedule.weekdays, calendar: calendar)
                .map { weekdayName($0, calendar: calendar) }
                .filter { !$0.isEmpty }
            cadence = names.isEmpty ? "Specific weekdays" : names.joined(separator: ", ")
        case .timesPerWeek(let count):
            switch max(1, count) {
            case 1: cadence = "Once a week"
            case 2: cadence = "Twice a week"
            default: cadence = "\(max(1, count)) times a week"
            }
        }
        var parts = [
            cadence,
            "\(schedule.durationMinutes) min",
            "Reminder \(reminderText(hour: schedule.reminderHour, minute: schedule.reminderMinute, calendar: calendar))",
        ]
        parts.append("Also when symptoms")
        return parts.joined(separator: " · ")
    }

    /// One bar per scheduled day in the filter, oldest first.
    /// Filled when that day has a recording whose status is not `missed`.
    /// Missed when the plan expected a check, the day has already ended, and no such recording exists.
    /// Today stays unmarked until a recording or an explicit missed check arrives.
    /// `timesPerWeek` uses one bar per expected recording in each finished week the filter covers in full.
    static func adherence(
        schedule: ChildScheduleFact?,
        recordings: [ChildRecordingFact],
        birthDate: Date,
        filter: ClinicDateFilter,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> ChildAdherence {
        if isUnsynced(filter) {
            return ChildAdherence(marks: [], caption: "Not synced yet")
        }
        guard let schedule else {
            return ChildAdherence(marks: [], caption: "No schedule set")
        }
        if case .specificWeekdays = schedule.cadence, schedule.weekdays.isEmpty {
            return ChildAdherence(marks: [], caption: "No weekdays are selected on this schedule.")
        }
        guard let window = adherenceWindow(
            filter: filter,
            recordings: recordings,
            birthDate: birthDate,
            now: now,
            calendar: calendar
        ) else {
            return ChildAdherence(marks: [], caption: "No scheduled days in this range.")
        }

        let days = cappedDays(from: window.start, through: window.end, calendar: calendar)
        let built: (marks: [ChildAdherenceMark], todayOpen: Bool)
        switch schedule.cadence {
        case .timesPerWeek(let count):
            built = weeklyMarks(
                expected: max(1, count),
                recordings: recordings,
                filter: filter,
                days: days.days,
                now: now,
                calendar: calendar
            )
        case .everyDay, .specificWeekdays:
            built = dailyMarks(
                schedule: schedule,
                recordings: recordings,
                filter: filter,
                days: days.days,
                now: now,
                calendar: calendar
            )
        }

        var marks = built.marks
        var truncated = days.truncated
        if marks.count > dayCap {
            marks = Array(marks.suffix(dayCap))
            truncated = true
        }
        var caption = adherenceCaption(marks: marks, todayOpen: built.todayOpen)
        if marks.isEmpty, case .timesPerWeek = schedule.cadence {
            caption = "No completed weeks in this range."
        }
        if truncated {
            caption += " Showing the latest \(dayCap) days."
        }
        return ChildAdherence(marks: marks, caption: caption)
    }

    static func timeline(
        recordings: [ChildRecordingFact],
        diary: [ChildDiaryFact],
        filter: ClinicDateFilter,
        calendar: Calendar = .current
    ) -> [ChildTimelineDay] {
        var entries: [ChildTimelineEntry] = []
        for recording in recordings where filter.contains(recording.startDate) {
            entries.append(recordingEntry(recording))
        }
        for event in diary where filter.contains(event.startedAt) {
            entries.append(diaryEntry(event))
        }
        let grouped = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { day in
            let items = grouped[day, default: []].sorted { lhs, rhs in
                if lhs.date != rhs.date { return lhs.date > rhs.date }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return ChildTimelineDay(day: day, entries: items)
        }
    }

    static func eventDays(
        recordings: [ChildRecordingFact],
        diary: [ChildDiaryFact],
        filter: ClinicDateFilter,
        calendar: Calendar = .current
    ) -> Set<Date> {
        var days = Set<Date>()
        for recording in recordings where filter.contains(recording.startDate) {
            days.insert(calendar.startOfDay(for: recording.startDate))
        }
        for event in diary where filter.contains(event.startedAt) {
            days.insert(calendar.startOfDay(for: event.startedAt))
        }
        return days
    }

    static func summary(
        range: ChildTimelineRange,
        day: Date?,
        filter: ClinicDateFilter,
        recordings: [ChildRecordingFact],
        diary: [ChildDiaryFact],
        calendar: Calendar = .current
    ) -> ChildRangeSummary {
        var change = 0
        var noChange = 0
        var urgent = 0
        var missed = 0
        var unsure = 0
        var notAnalyzed = 0
        for recording in recordings where filter.contains(recording.startDate) {
            switch recording.status {
            case .changeDetected: change += 1
            case .noChange: noChange += 1
            case .urgent: urgent += 1
            case .missed: missed += 1
            case .unsure: unsure += 1
            case .notAnalyzed: notAnalyzed += 1
            }
        }
        var results = [
            countRow(.changeDetected, count: change),
            countRow(.noChange, count: noChange),
            countRow(.urgent, count: urgent),
            countRow(.missed, count: missed),
        ]
        if unsure > 0 {
            results.append(countRow(.unsure, count: unsure))
        }
        if notAnalyzed > 0 {
            results.append(countRow(.notAnalyzed, count: notAnalyzed))
        }

        var symptomCounts: [String: Int] = [:]
        for event in diary where event.kind == .symptom && filter.contains(event.startedAt) {
            symptomCounts[symptomLabel(event), default: 0] += 1
        }
        let symptoms = symptomCounts
            .map { ChildCountRow(id: "symptom-\($0.key)", title: $0.key, count: $0.value, tone: nil) }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }

        return ChildRangeSummary(
            title: day == nil ? range.title : "Selected day",
            detail: filterDetail(filter, calendar: calendar),
            results: results,
            symptoms: symptoms,
            vestNote: vestNote
        )
    }

    static func trends(
        recordings: [ChildRecordingFact],
        extraMissedDays: [Date],
        baselineHeartRate: Int?,
        baselineQRS: Int?,
        filter: ClinicDateFilter,
        calendar: Calendar = .current
    ) -> ChildTrendSeries {
        let points = recordings
            .filter { filter.contains($0.startDate) && $0.status != .missed }
            .filter { $0.heartRate != nil || $0.qrsMS != nil }
            .sorted { lhs, rhs in
                if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .map { recording in
                ChildTrendPoint(
                    id: recording.id,
                    date: recording.startDate,
                    heartRate: recording.heartRate,
                    qrsMS: recording.qrsMS,
                    tone: recording.status.tone
                )
            }

        var missed = Set(extraMissedDays.map { calendar.startOfDay(for: $0) })
        for recording in recordings where recording.status == .missed && filter.contains(recording.startDate) {
            missed.insert(calendar.startOfDay(for: recording.startDate))
        }
        let measured = Set(points.map { calendar.startOfDay(for: $0.date) })
        missed.subtract(measured)

        return ChildTrendSeries(
            points: points,
            missedDays: missed.sorted(),
            baselineHeartRate: baselineHeartRate,
            baselineQRS: baselineQRS
        )
    }

    /// Baseline first, then recordings in the filter, newest first.
    /// A missed check stays in the table and does not open the viewer.
    static func ecgRows(
        recordings: [ChildRecordingFact],
        baseline: ChildBaselineFact?,
        filter: ClinicDateFilter
    ) -> [ChildECGRow] {
        var rows: [ChildECGRow] = []
        if let baseline {
            rows.append(baselineRow(baseline))
        }
        let filtered = recordings
            .filter { filter.contains($0.startDate) }
            .sorted { lhs, rhs in
                if lhs.startDate != rhs.startDate { return lhs.startDate > rhs.startDate }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        rows.append(contentsOf: filtered.map(recordingRow))
        return rows
    }

    static func diaryLists(diary: [ChildDiaryFact], filter: ClinicDateFilter) -> ChildDiaryLists {
        let included = diary
            .filter { filter.contains($0.startedAt) }
            .sorted { lhs, rhs in
                if lhs.startedAt != rhs.startedAt { return lhs.startedAt > rhs.startedAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        return ChildDiaryLists(
            symptoms: included.filter { $0.kind == .symptom }.map(diaryRow),
            activities: included.filter { $0.kind == .activity }.map(diaryRow),
            journal: included.filter { $0.kind == .journal }.map(diaryRow)
        )
    }

    // MARK: - Filter

    private static func daySpan(_ day: Date, calendar: Calendar) -> ClinicDateFilter {
        let start = calendar.startOfDay(for: day)
        return ClinicDateFilter(start: start, end: endOfDay(start, calendar: calendar))
    }

    private static func trailingDays(_ count: Int, endingAt now: Date, calendar: Calendar) -> ClinicDateFilter {
        let endDay = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -(max(1, count) - 1), to: endDay) ?? endDay
        return ClinicDateFilter(start: start, end: endOfDay(endDay, calendar: calendar))
    }

    private static func endOfDay(_ day: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: day)
        let next = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return next.addingTimeInterval(-0.001)
    }

    private static func filterDetail(_ filter: ClinicDateFilter, calendar: Calendar) -> String {
        if isUnsynced(filter) {
            return "This child has not been synced."
        }
        if filter.start == nil, filter.end == nil {
            return "Every recording and journal entry."
        }
        if let start = filter.start, let end = filter.end {
            if calendar.isDate(start, inSameDayAs: end) {
                return dateText(start, includeTime: false)
            }
            return "\(dateText(start, includeTime: false)) – \(dateText(end, includeTime: false))"
        }
        if let start = filter.start {
            let includeTime = calendar.startOfDay(for: start) != start
            return "From \(dateText(start, includeTime: includeTime))"
        }
        if let end = filter.end {
            return "Through \(dateText(end, includeTime: false))"
        }
        return "Every recording and journal entry."
    }

    private static func dateText(_ date: Date, includeTime: Bool) -> String {
        if includeTime {
            date.formatted(date: .abbreviated, time: .shortened)
        } else {
            date.formatted(date: .abbreviated, time: .omitted)
        }
    }

    // MARK: - Adherence

    private static func adherenceWindow(
        filter: ClinicDateFilter,
        recordings: [ChildRecordingFact],
        birthDate: Date,
        now: Date,
        calendar: Calendar
    ) -> (start: Date, end: Date)? {
        let today = calendar.startOfDay(for: now)
        let birth = calendar.startOfDay(for: birthDate)
        let end = min(filter.end.map { calendar.startOfDay(for: $0) } ?? today, today)
        let start: Date
        if let filterStart = filter.start {
            start = max(calendar.startOfDay(for: filterStart), birth)
        } else if let earliest = recordings.map(\.startDate).min() {
            start = max(calendar.startOfDay(for: earliest), birth)
        } else {
            return nil
        }
        guard start <= end else { return nil }
        return (start, end)
    }

    private static func cappedDays(
        from start: Date,
        through end: Date,
        calendar: Calendar
    ) -> (days: [Date], truncated: Bool) {
        var start = calendar.startOfDay(for: start)
        let end = calendar.startOfDay(for: end)
        var truncated = false
        if let earliestKept = calendar.date(byAdding: .day, value: -(dayCap - 1), to: end), start < earliestKept {
            start = earliestKept
            truncated = true
        }
        var days: [Date] = []
        var day = start
        while day <= end && days.count < dayCap {
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { break }
            day = next
        }
        return (days, truncated)
    }

    private static func dailyMarks(
        schedule: ChildScheduleFact,
        recordings: [ChildRecordingFact],
        filter: ClinicDateFilter,
        days: [Date],
        now: Date,
        calendar: Calendar
    ) -> (marks: [ChildAdherenceMark], todayOpen: Bool) {
        let weekdays = Set(schedule.weekdays)
        let today = calendar.startOfDay(for: now)
        var marks: [ChildAdherenceMark] = []
        var todayOpen = false
        for day in days {
            let scheduled: Bool
            switch schedule.cadence {
            case .everyDay:
                scheduled = true
            case .specificWeekdays:
                scheduled = weekdays.contains(calendar.component(.weekday, from: day))
            case .timesPerWeek:
                scheduled = false
            }
            guard scheduled else { continue }
            let onDay = recordings.filter {
                calendar.isDate($0.startDate, inSameDayAs: day) && filter.contains($0.startDate)
            }
            if onDay.contains(where: { $0.status != .missed }) {
                marks.append(mark(day: day, state: .recorded, scope: "day", index: 0, calendar: calendar))
            } else if onDay.contains(where: { $0.status == .missed }) || day < today {
                marks.append(mark(day: day, state: .missed, scope: "day", index: 0, calendar: calendar))
            } else if calendar.isDate(day, inSameDayAs: today) {
                todayOpen = true
            }
        }
        return (marks, todayOpen)
    }

    /// A week counts as missed only after it has ended and the filter covers that whole week.
    /// Recordings already in the filter still fill a bar before the week ends.
    private static func weeklyMarks(
        expected: Int,
        recordings: [ChildRecordingFact],
        filter: ClinicDateFilter,
        days: [Date],
        now: Date,
        calendar: Calendar
    ) -> (marks: [ChildAdherenceMark], todayOpen: Bool) {
        var weekStarts: [Date] = []
        var seen = Set<Date>()
        for day in days {
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: day) else { continue }
            if seen.insert(interval.start).inserted {
                weekStarts.append(interval.start)
            }
        }

        let today = calendar.startOfDay(for: now)
        var marks: [ChildAdherenceMark] = []
        for weekStart in weekStarts {
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: weekStart) else { continue }
            let weekEnd = calendar.startOfDay(
                for: calendar.date(byAdding: .day, value: -1, to: interval.end) ?? weekStart
            )
            let done = recordings.filter { recording in
                let day = calendar.startOfDay(for: recording.startDate)
                return day >= weekStart
                    && day <= weekEnd
                    && recording.status != .missed
                    && filter.contains(recording.startDate)
            }.count
            let filled = min(done, expected)
            for index in 0..<filled {
                marks.append(mark(day: weekStart, state: .recorded, scope: "week", index: index, calendar: calendar))
            }
            let startsInside = filter.start.map { weekStart >= calendar.startOfDay(for: $0) } ?? true
            let endsInside = filter.end.map { weekEnd <= calendar.startOfDay(for: $0) } ?? true
            let weekEnded = weekEnd < today
            guard weekEnded, startsInside, endsInside else { continue }
            let shortfall = max(0, expected - done)
            for offset in 0..<shortfall {
                marks.append(
                    mark(day: weekStart, state: .missed, scope: "week", index: filled + offset, calendar: calendar)
                )
            }
        }
        return (marks, false)
    }

    private static func mark(
        day: Date,
        state: ChildAdherenceMark.State,
        scope: String,
        index: Int,
        calendar: Calendar
    ) -> ChildAdherenceMark {
        let dayLabel = day.formatted(date: .long, time: .omitted)
        let stateLabel = state == .recorded ? "recorded" : "missed"
        let prefix = scope == "week" ? "Week of \(dayLabel)" : dayLabel
        return ChildAdherenceMark(
            id: "\(scope)-\(day.timeIntervalSinceReferenceDate)-\(index)-\(state.rawValue)",
            day: calendar.startOfDay(for: day),
            state: state,
            accessibilityLabel: "\(prefix), \(stateLabel)"
        )
    }

    private static func adherenceCaption(marks: [ChildAdherenceMark], todayOpen: Bool) -> String {
        let recorded = marks.filter { $0.state == .recorded }.count
        let missed = marks.filter { $0.state == .missed }.count
        var caption: String
        if marks.isEmpty {
            caption = todayOpen ? "Today's check is still open." : "No scheduled days in this range."
        } else if missed == 0 {
            caption = recorded == 1 ? "1 scheduled check recorded" : "\(recorded) scheduled checks recorded"
        } else if recorded == 0 {
            caption = missed == 1 ? "1 scheduled check missed" : "\(missed) scheduled checks missed"
        } else {
            caption = "\(recorded) of \(recorded + missed) done, \(missed) missed"
        }
        if todayOpen, !marks.isEmpty {
            caption += " Today is still open."
        }
        return caption
    }

    // MARK: - Rows

    private static func recordingEntry(_ recording: ChildRecordingFact) -> ChildTimelineEntry {
        ChildTimelineEntry(
            id: recording.id,
            date: recording.startDate,
            kind: .recording,
            title: recording.status == .missed ? "Scheduled recording missed" : "Recording, \(lengthText(recording.duration))",
            detail: recordingDetail(recording),
            statusTitle: recording.status.listTitle,
            statusTone: recording.status.tone,
            opensRecording: recording.status != .missed
        )
    }

    private static func recordingDetail(_ recording: ChildRecordingFact) -> String {
        var parts: [String] = []
        if let heartRate = recording.heartRate {
            parts.append("HR \(heartRate) bpm")
        }
        if let qrs = recording.qrsMS {
            parts.append("QRS \(qrs) ms")
        }
        if !recording.signalQuality.isEmpty {
            parts.append("\(recording.signalQuality) signal.")
        }
        if parts.isEmpty {
            return recording.reviewed ? "Reviewed." : ""
        }
        return parts.joined(separator: ", ")
    }

    private static func diaryEntry(_ event: ChildDiaryFact) -> ChildTimelineEntry {
        let row = diaryRow(event)
        return ChildTimelineEntry(
            id: event.id,
            date: event.startedAt,
            kind: timelineKind(event.kind),
            title: row.title,
            detail: row.detail,
            statusTitle: nil,
            statusTone: nil,
            opensRecording: false
        )
    }

    private static func diaryRow(_ event: ChildDiaryFact) -> ChildDiaryRow {
        let text = trimmed(event.text)
        switch event.kind {
        case .symptom:
            let title = symptomLabel(event)
            return ChildDiaryRow(
                id: event.id,
                date: event.startedAt,
                title: title,
                detail: text == title ? "" : text
            )
        case .activity:
            return ChildDiaryRow(
                id: event.id,
                date: event.startedAt,
                title: text.isEmpty ? "Activity" : text,
                detail: ""
            )
        case .journal:
            return ChildDiaryRow(
                id: event.id,
                date: event.startedAt,
                title: "Journal",
                detail: text
            )
        }
    }

    private static func timelineKind(_ kind: DiaryEventKind) -> ChildTimelineEntry.Kind {
        switch kind {
        case .symptom: .symptom
        case .activity: .activity
        case .journal: .journal
        }
    }

    private static func symptomLabel(_ event: ChildDiaryFact) -> String {
        let name = trimmed(event.symptomName)
        if !name.isEmpty { return name }
        let text = trimmed(event.text)
        return text.isEmpty ? "Symptom" : text
    }

    private static func countRow(_ status: ParentRecordingStatus, count: Int) -> ChildCountRow {
        ChildCountRow(id: status.rawValue, title: status.listTitle, count: count, tone: status.tone)
    }

    private static func baselineRow(_ baseline: ChildBaselineFact) -> ChildECGRow {
        let name = trimmed(baseline.fileName)
        let file = name.isEmpty ? "Baseline file" : name
        let date = baseline.recordedAt.formatted(date: .abbreviated, time: .omitted)
        return ChildECGRow(
            id: "baseline-\(baseline.id.uuidString)",
            recordingID: nil,
            canOpen: false,
            title: "Baseline",
            subtitle: "Version \(baseline.version) · \(file) · \(date)",
            resultTitle: "Baseline",
            resultTone: .teal,
            heartRate: measurement(baseline.heartRate, unit: "bpm"),
            pr: measurement(baseline.prMS, unit: "ms"),
            qrs: measurement(baseline.qrsMS, unit: "ms"),
            axis: axisText(baseline.axisDegrees),
            signal: signalText(baseline.signalQuality),
            length: lengthText(baseline.duration)
        )
    }

    private static func recordingRow(_ recording: ChildRecordingFact) -> ChildECGRow {
        ChildECGRow(
            id: recording.id.uuidString,
            recordingID: recording.id,
            canOpen: recording.status != .missed,
            title: recording.startDate.formatted(date: .abbreviated, time: .shortened),
            subtitle: recording.reviewed ? "Reviewed" : "Not reviewed",
            resultTitle: recording.status.listTitle,
            resultTone: recording.status.tone,
            heartRate: measurement(recording.heartRate, unit: "bpm"),
            pr: measurement(recording.prMS, unit: "ms"),
            qrs: measurement(recording.qrsMS, unit: "ms"),
            axis: axisText(recording.axisDegrees),
            signal: signalText(recording.signalQuality),
            length: lengthText(recording.duration)
        )
    }

    private static func measurement(_ value: Int?, unit: String) -> String {
        guard let value else { return dash }
        return "\(value) \(unit)"
    }

    private static func axisText(_ value: Int?) -> String {
        guard let value else { return dash }
        return "\(value)°"
    }

    private static func lengthText(_ duration: TimeInterval) -> String {
        guard duration > 0 else { return dash }
        let total = Int(duration.rounded())
        let minutes = total / 60
        let seconds = total % 60
        if minutes > 0, seconds > 0 { return "\(minutes) min \(seconds) sec" }
        if minutes > 0 { return minutes == 1 ? "1 min" : "\(minutes) min" }
        return seconds == 1 ? "1 sec" : "\(seconds) sec"
    }

    private static func signalText(_ quality: String) -> String {
        let text = trimmed(quality)
        return text.isEmpty ? dash : text
    }

    private static func trimmed(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    // MARK: - Schedule words

    private static func orderedWeekdays(_ weekdays: [Int], calendar: Calendar) -> [Int] {
        weekdays.sorted { lhs, rhs in
            let left = (lhs - calendar.firstWeekday + 7) % 7
            let right = (rhs - calendar.firstWeekday + 7) % 7
            return left < right
        }
    }

    private static func weekdayName(_ weekday: Int, calendar: Calendar) -> String {
        let symbols = calendar.shortWeekdaySymbols
        let index = weekday - 1
        guard symbols.indices.contains(index) else { return "" }
        return symbols[index]
    }

    private static func reminderText(hour: Int, minute: Int, calendar: Calendar) -> String {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let date = calendar.date(from: components) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }
}
