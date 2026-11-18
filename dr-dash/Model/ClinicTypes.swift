import Foundation

/// Sex recorded for a child. Raw values are the transfer spellings.
nonisolated enum ChildSex: String, Codable, CaseIterable, Identifiable, Sendable {
    case male
    case female
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .male: "Male"
        case .female: "Female"
        case .other: "Other"
        }
    }
}

/// Phone link stored on the child. The link sheet's waiting and failure states are not all persisted.
nonisolated enum LinkState: String, Codable, CaseIterable, Identifiable, Sendable {
    case notLinked
    case waiting
    case linked

    var id: String { rawValue }
}

/// Result the parent app already decided. This clinic does not reclassify the trace.
///
/// `changeDetected`, `urgent`, and `unsure` are flagged results. `missed` is a missed check.
nonisolated enum ParentRecordingStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case noChange
    case changeDetected
    case urgent
    case unsure
    case missed
    case notAnalyzed

    var id: String { rawValue }

    var listTitle: String {
        switch self {
        case .noChange: "No change"
        case .changeDetected: "Change detected"
        case .urgent: "Urgent"
        case .unsure: "Unsure"
        case .missed: "Missed"
        case .notAnalyzed: "Not analysed"
        }
    }

    var tone: ClinicTone {
        switch self {
        case .noChange: .green
        case .changeDetected, .unsure: .amber
        case .missed, .notAnalyzed: .neutral
        case .urgent: .red
        }
    }

    /// Change, urgent, and unsure. Missed checks use a separate rule in `ClinicListLogic`.
    var isFlaggedResult: Bool {
        switch self {
        case .changeDetected, .urgent, .unsure: true
        case .noChange, .missed, .notAnalyzed: false
        }
    }

    /// Lower sorts first when several unreviewed results compete for the list badge.
    var attentionRank: Int {
        switch self {
        case .urgent: 0
        case .unsure: 1
        case .changeDetected: 2
        case .missed: 3
        case .notAnalyzed: 4
        case .noChange: 5
        }
    }
}

/// Diary kinds match the parent app: symptom, activity, and journal.
nonisolated enum DiaryEventKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case symptom
    case activity
    case journal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .symptom: "Symptom"
        case .activity: "Activity"
        case .journal: "Journal"
        }
    }
}

/// How often the child should record.
///
/// `specificWeekdays` uses the schedule's weekday set (Calendar weekday, 1 = Sunday).
/// `timesPerWeek` counts any N recordings in the week, on any days.
nonisolated enum ScheduleCadence: Equatable, Sendable, Hashable {
    case everyDay
    case specificWeekdays
    case timesPerWeek(Int)

    static let everyDayKey = "everyDay"
    static let specificWeekdaysKey = "specificWeekdays"
    static let timesPerWeekKey = "timesPerWeek"

    var storageKey: String {
        switch self {
        case .everyDay: Self.everyDayKey
        case .specificWeekdays: Self.specificWeekdaysKey
        case .timesPerWeek: Self.timesPerWeekKey
        }
    }
}

extension ScheduleCadence: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case timesPerWeek
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case Self.everyDayKey:
            self = .everyDay
        case Self.specificWeekdaysKey:
            self = .specificWeekdays
        case Self.timesPerWeekKey:
            let count = try container.decode(Int.self, forKey: .timesPerWeek)
            guard count >= 1 else {
                throw DecodingError.dataCorruptedError(
                    forKey: .timesPerWeek,
                    in: container,
                    debugDescription: "timesPerWeek must be at least 1."
                )
            }
            self = .timesPerWeek(count)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Unknown schedule kind \(kind)."
            )
        }
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .everyDay:
            try container.encode(Self.everyDayKey, forKey: .kind)
        case .specificWeekdays:
            try container.encode(Self.specificWeekdaysKey, forKey: .kind)
        case .timesPerWeek(let count):
            try container.encode(Self.timesPerWeekKey, forKey: .kind)
            try container.encode(count, forKey: .timesPerWeek)
        }
    }
}

/// Badge color the list and later screens share. The design layer maps these to paints.
nonisolated enum ClinicTone: String, CaseIterable, Sendable {
    case teal
    case amber
    case red
    case green
    case neutral
}
