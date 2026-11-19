import Foundation

/// A recording reduced to the fields the list, sort, and review rules need.
nonisolated struct ClinicAttentionRecording: Identifiable, Equatable, Sendable {
    var id: UUID
    var startDate: Date
    var parentStatus: ParentRecordingStatus
    var reviewed: Bool
}

/// A child reduced to the fields the patient list needs. Sorting does not touch SwiftData.
nonisolated struct ClinicChildSummary: Identifiable, Equatable, Sendable {
    var id: UUID
    var fullName: String
    var nickname: String
    var birthDate: Date
    var conditionText: String
    var lastSyncDate: Date?
    var latestSyncLowerBound: Date? = nil
    var hasLatestSyncBound: Bool = false
    var phoneLinked: Bool
    var recordings: [ClinicAttentionRecording]
}

/// Inclusive date window. A nil bound is open. `all` includes every date.
/// `excludesStart` makes the start exclusive, matching the phone's send cursor.
nonisolated struct ClinicDateFilter: Equatable, Sendable {
    var start: Date?
    var end: Date?
    var excludesStart = false

    static let all = ClinicDateFilter(start: nil, end: nil)
    /// Matches nothing. Used when Since last sync is selected and the child has never synced.
    static let unsynced = ClinicDateFilter(start: .distantFuture, end: nil)

    func contains(_ date: Date) -> Bool {
        if let start {
            if excludesStart {
                if date <= start { return false }
            } else if date < start {
                return false
            }
        }
        if let end, date > end { return false }
        return true
    }
}

/// Since last sync. A live sync stores an exclusive lower bound; nil means the whole history.
/// Demo children leave `hasLatestSyncBound` false and keep an inclusive start at `lastSyncDate`.
nonisolated struct ClinicSyncWindow: Equatable, Sendable {
    var lastSyncDate: Date?
    var latestSyncLowerBound: Date?
    var hasLatestSyncBound: Bool

    func sinceLastSyncFilter() -> ClinicDateFilter {
        if hasLatestSyncBound {
            guard let latestSyncLowerBound else { return .all }
            return ClinicDateFilter(start: latestSyncLowerBound, end: nil, excludesStart: true)
        }
        guard let lastSyncDate else { return .unsynced }
        return ClinicDateFilter(start: lastSyncDate, end: nil)
    }

    /// The covered end is already the newest event, so the stored batch should all be visible.
    static func revealsWholeHistory(
        lastSyncDate: Date?,
        newestEvent: Date?,
        hasLatestSyncBound: Bool
    ) -> Bool {
        guard !hasLatestSyncBound, let lastSyncDate, let newestEvent else { return false }
        return lastSyncDate == newestEvent
    }
}

/// The badge drawn in the Status column.
nonisolated struct ClinicListStatus: Equatable, Sendable {
    var title: String
    var tone: ClinicTone
}

/// Sidebar lists. Counts and membership use the same attention and link rules as the table.
nonisolated enum ClinicSidebarSection: String, CaseIterable, Identifiable, Sendable {
    case needsAttention
    case allPatients
    case notLinked

    var id: String { rawValue }

    var title: String {
        switch self {
        case .needsAttention: "Needs attention"
        case .allPatients: "All patients"
        case .notLinked: "Not linked"
        }
    }

    var systemImage: String {
        switch self {
        case .needsAttention: "exclamationmark.circle"
        case .allPatients: "person.2"
        case .notLinked: "iphone.slash"
        }
    }
}

/// Sort orders the patient list can show. Needs attention is the default.
nonisolated enum ClinicSort: String, CaseIterable, Identifiable, Sendable {
    case needsAttention
    case name
    case lastSync
    case age

    var id: String { rawValue }

    var title: String {
        switch self {
        case .needsAttention: "Needs attention"
        case .name: "Name"
        case .lastSync: "Last sync"
        case .age: "Age"
        }
    }
}

/// Search, sort, age, and the needs-attention rule. Not a view.
nonisolated enum ClinicListLogic {
    /// Completed years. A future birth date is 0.
    static func ageYears(born: Date, on now: Date = .now, calendar: Calendar = .current) -> Int {
        let years = calendar.dateComponents([.year], from: born, to: now).year ?? 0
        return max(0, years)
    }

    static func ageLabel(born: Date, on now: Date = .now, calendar: Calendar = .current) -> String {
        let years = ageYears(born: born, on: now, calendar: calendar)
        return years == 1 ? "1 year" : "\(years) years"
    }

    /// Compact age used in the patient table and the child header, as in "7 yrs".
    static func ageCompact(born: Date, on now: Date = .now, calendar: Calendar = .current) -> String {
        "\(ageYears(born: born, on: now, calendar: calendar)) yrs"
    }

    /// Case-insensitive match on the full name and the nickname.
    static func matches(_ child: ClinicChildSummary, query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return child.fullName.localizedStandardContains(trimmed)
            || child.nickname.localizedStandardContains(trimmed)
    }

    /// Unreviewed `changeDetected`, `urgent`, or `unsure` always count.
    /// An unreviewed `missed` check counts when it sits in the Since last sync window.
    /// A child who has never synced has no missed checks in that window.
    ///
    /// Reviewed recordings never count. `noChange` and `notAnalyzed` never count.
    /// The child stays in Needs attention while any recording still matches this rule.
    /// `ClinicSyncMerge` does not move `lastSyncDate`. A missed check from an earlier
    /// sync drops out of this rule once a later sync moves the window past it.
    static func recordingNeedsAttention(
        _ recording: ClinicAttentionRecording,
        lastSyncDate: Date?,
        latestSyncLowerBound: Date? = nil,
        hasLatestSyncBound: Bool = false
    ) -> Bool {
        guard !recording.reviewed else { return false }
        switch recording.parentStatus {
        case .changeDetected, .urgent, .unsure:
            return true
        case .missed:
            return ClinicSyncWindow(
                lastSyncDate: lastSyncDate,
                latestSyncLowerBound: latestSyncLowerBound,
                hasLatestSyncBound: hasLatestSyncBound
            ).sinceLastSyncFilter().contains(recording.startDate)
        case .noChange, .notAnalyzed:
            return false
        }
    }

    static func needsAttention(_ child: ClinicChildSummary) -> Bool {
        child.recordings.contains { recordingNeedsAttention($0, child: child) }
    }

    static func recordingNeedsAttention(
        _ recording: ClinicAttentionRecording,
        child: ClinicChildSummary
    ) -> Bool {
        recordingNeedsAttention(
            recording,
            lastSyncDate: child.lastSyncDate,
            latestSyncLowerBound: child.latestSyncLowerBound,
            hasLatestSyncBound: child.hasLatestSyncBound
        )
    }

    static func inSection(_ child: ClinicChildSummary, _ section: ClinicSidebarSection) -> Bool {
        switch section {
        case .allPatients:
            true
        case .needsAttention:
            needsAttention(child)
        case .notLinked:
            !child.phoneLinked
        }
    }

    /// Ids of recordings that are still unreviewed and start inside `filter`, in input order.
    static func unreviewedIDs(
        _ recordings: [ClinicAttentionRecording],
        in filter: ClinicDateFilter = .all
    ) -> [UUID] {
        recordings.compactMap { recording in
            guard !recording.reviewed, filter.contains(recording.startDate) else { return nil }
            return recording.id
        }
    }

    static func filtered(
        _ children: [ClinicChildSummary],
        query: String,
        sort: ClinicSort,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [ClinicChildSummary] {
        sorted(children.filter { matches($0, query: query) }, by: sort, now: now, calendar: calendar)
    }

    /// Needs attention comes first, then last sync (newest first, never-synced last).
    /// Name, last sync, and age are the other orders. Ties break on name, then id.
    static func sorted(
        _ children: [ClinicChildSummary],
        by sort: ClinicSort,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [ClinicChildSummary] {
        children.sorted { lhs, rhs in
            switch sort {
            case .needsAttention:
                let leftFlag = needsAttention(lhs)
                let rightFlag = needsAttention(rhs)
                if leftFlag != rightFlag { return leftFlag }
                if let syncOrder = lastSyncOrder(lhs.lastSyncDate, rhs.lastSyncDate) {
                    return syncOrder
                }
                return nameIsBefore(lhs, rhs)
            case .name:
                return nameIsBefore(lhs, rhs)
            case .lastSync:
                if let syncOrder = lastSyncOrder(lhs.lastSyncDate, rhs.lastSyncDate) {
                    return syncOrder
                }
                return nameIsBefore(lhs, rhs)
            case .age:
                let leftAge = ageYears(born: lhs.birthDate, on: now, calendar: calendar)
                let rightAge = ageYears(born: rhs.birthDate, on: now, calendar: calendar)
                if leftAge != rightAge { return leftAge > rightAge }
                return nameIsBefore(lhs, rhs)
            }
        }
    }

    static func listStatus(for child: ClinicChildSummary) -> ClinicListStatus {
        let flagged = child.recordings
            .filter { recordingNeedsAttention($0, child: child) }
            .sorted { lhs, rhs in
                if lhs.parentStatus.attentionRank != rhs.parentStatus.attentionRank {
                    return lhs.parentStatus.attentionRank < rhs.parentStatus.attentionRank
                }
                return lhs.startDate > rhs.startDate
            }
        if let top = flagged.first {
            return ClinicListStatus(title: top.parentStatus.listTitle, tone: top.parentStatus.tone)
        }
        if let latest = child.recordings.max(by: { lhs, rhs in
            if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
            return lhs.id.uuidString < rhs.id.uuidString
        }) {
            return ClinicListStatus(title: latest.parentStatus.listTitle, tone: latest.parentStatus.tone)
        }
        if child.phoneLinked {
            return ClinicListStatus(title: "Phone linked", tone: .teal)
        }
        return ClinicListStatus(title: "Not linked", tone: .neutral)
    }

    /// Status pills for one patient row. An urgent result stands alone. Otherwise the row
    /// can show a change, a missed count, and new unreviewed recordings together.
    static func listBadges(for child: ClinicChildSummary) -> [ClinicListStatus] {
        let recordings = child.recordings
        let urgent = recordings.contains { !$0.reviewed && $0.parentStatus == .urgent }
        if urgent {
            return [ClinicListStatus(title: "Urgent result", tone: .red)]
        }
        var badges: [ClinicListStatus] = []
        let changed = recordings.contains {
            !$0.reviewed && ($0.parentStatus == .changeDetected || $0.parentStatus == .unsure)
        }
        if changed {
            badges.append(ClinicListStatus(title: "Change detected", tone: .amber))
        }
        let missed = recordings.filter {
            $0.parentStatus == .missed && recordingNeedsAttention($0, child: child)
        }.count
        if missed > 0 {
            badges.append(ClinicListStatus(title: missed == 1 ? "1 missed" : "\(missed) missed", tone: .neutral))
        }
        let newData = recordings.contains { !$0.reviewed && $0.parentStatus == .noChange }
        if newData {
            badges.append(ClinicListStatus(title: "New data", tone: .teal))
        }
        if !badges.isEmpty { return badges }
        if recordings.isEmpty {
            return [listStatus(for: child)]
        }
        return [ClinicListStatus(title: "No flags", tone: .neutral)]
    }

    /// True when `lhs` should come first. Newer syncs come first. A missing sync comes last.
    private static func lastSyncOrder(_ lhs: Date?, _ rhs: Date?) -> Bool? {
        switch (lhs, rhs) {
        case let (left?, right?) where left != right:
            return left > right
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        default:
            return nil
        }
    }

    private static func nameIsBefore(_ lhs: ClinicChildSummary, _ rhs: ClinicChildSummary) -> Bool {
        let order = lhs.fullName.localizedStandardCompare(rhs.fullName)
        if order != .orderedSame { return order == .orderedAscending }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
