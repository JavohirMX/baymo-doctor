import Foundation
import SwiftData

/// The child's recording plan. One schedule belongs to one child.
///
/// Weekdays use `Calendar` weekday numbers, 1 = Sunday through 7 = Saturday.
/// Those days are the plan only when `cadence` is `specificWeekdays`.
/// `timesPerWeek` counts any N recordings in the week, whichever days they fall on.
@Model
final class Schedule {
    var cadenceRaw: String
    /// Used when `cadence` is `timesPerWeek`. Ignored for the other cadences.
    var timesPerWeek: Int
    /// Sorted unique weekdays in 1...7. The plan only when cadence is `specificWeekdays`.
    var weekdays: [Int]
    /// Clamped to 1...15 by `normalize()` and by `init`.
    var durationMinutes: Int
    var reminderHour: Int
    var reminderMinute: Int
    var recordWhenSymptoms: Bool

    var child: Child?

    init(
        cadence: ScheduleCadence = .everyDay,
        weekdays: Set<Int> = [],
        durationMinutes: Int = Schedule.defaultDurationMinutes,
        reminderHour: Int = Schedule.defaultReminderHour,
        reminderMinute: Int = Schedule.defaultReminderMinute,
        recordWhenSymptoms: Bool = false
    ) {
        switch cadence {
        case .everyDay:
            self.cadenceRaw = ScheduleCadence.everyDayKey
            self.timesPerWeek = 1
        case .specificWeekdays:
            self.cadenceRaw = ScheduleCadence.specificWeekdaysKey
            self.timesPerWeek = 1
        case .timesPerWeek(let count):
            self.cadenceRaw = ScheduleCadence.timesPerWeekKey
            self.timesPerWeek = max(1, count)
        }
        self.weekdays = Self.normalizedWeekdays(weekdays)
        self.durationMinutes = Self.clampedDuration(durationMinutes)
        self.reminderHour = Self.clampedHour(reminderHour)
        self.reminderMinute = Self.clampedMinute(reminderMinute)
        self.recordWhenSymptoms = recordWhenSymptoms
    }

    static let defaultDurationMinutes = 5
    static let defaultReminderHour = 8
    static let defaultReminderMinute = 0

    var cadence: ScheduleCadence {
        get {
            switch cadenceRaw {
            case ScheduleCadence.specificWeekdaysKey:
                .specificWeekdays
            case ScheduleCadence.timesPerWeekKey:
                .timesPerWeek(max(1, timesPerWeek))
            default:
                .everyDay
            }
        }
        set {
            switch newValue {
            case .everyDay:
                cadenceRaw = ScheduleCadence.everyDayKey
            case .specificWeekdays:
                cadenceRaw = ScheduleCadence.specificWeekdaysKey
            case .timesPerWeek(let count):
                cadenceRaw = ScheduleCadence.timesPerWeekKey
                timesPerWeek = max(1, count)
            }
        }
    }

    var weekdaySet: Set<Int> {
        get { Set(weekdays) }
        set { weekdays = Self.normalizedWeekdays(newValue) }
    }

    /// Pulls duration, clock, weekdays, and the weekly count back into range.
    func normalize() {
        durationMinutes = Self.clampedDuration(durationMinutes)
        reminderHour = Self.clampedHour(reminderHour)
        reminderMinute = Self.clampedMinute(reminderMinute)
        weekdays = Self.normalizedWeekdays(Set(weekdays))
        if case .timesPerWeek(let count) = cadence {
            cadence = .timesPerWeek(max(1, count))
        }
    }

    func apply(_ payload: ClinicSchedulePayload) {
        cadence = payload.cadence
        weekdays = Self.normalizedWeekdays(Set(payload.weekdays))
        durationMinutes = payload.durationMinutes
        reminderHour = payload.reminderHour
        reminderMinute = payload.reminderMinute
        recordWhenSymptoms = payload.recordWhenSymptoms
        normalize()
    }

    static func clampedDuration(_ minutes: Int) -> Int {
        min(15, max(1, minutes))
    }

    static func clampedHour(_ hour: Int) -> Int {
        min(23, max(0, hour))
    }

    static func clampedMinute(_ minute: Int) -> Int {
        min(59, max(0, minute))
    }

    static func normalizedWeekdays(_ days: Set<Int>) -> [Int] {
        days.filter { (1...7).contains($0) }.sorted()
    }
}
