import Foundation
import SwiftData

/// Fields from the child-details step. A date of birth stays unset until the doctor picks one.
struct PatientDetailsDraft {
    var fullName = ""
    var nickname = ""
    var birthDate: Date?
    var sex: ChildSex = .other
    var conditionText = ""
    var setupNotes = ""

    static let nicknameLimit = 12

    var trimmedName: String {
        fullName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Keeps a nickname from growing past 12 characters.
    /// A value already longer than that stays until the doctor shortens it.
    static func limitedNickname(current: String, proposed: String) -> String {
        if proposed.count <= nicknameLimit {
            return proposed
        }
        if current.count > nicknameLimit, proposed.count < current.count {
            return proposed
        }
        if current.count <= nicknameLimit {
            return String(proposed.prefix(nicknameLimit))
        }
        return current
    }

    var canContinue: Bool {
        !trimmedName.isEmpty && birthDate != nil
    }

    init() {}

    init(child: Child) {
        fullName = child.fullName
        nickname = child.nickname
        birthDate = child.birthDate
        sex = child.sex
        conditionText = child.conditionText
        setupNotes = child.setupNotes
    }

    func write(to child: Child) {
        child.fullName = trimmedName
        child.nickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        child.birthDate = Calendar.current.startOfDay(for: min(birthDate ?? .now, .now))
        child.sex = sex
        child.conditionText = conditionText.trimmingCharacters(in: .whitespacesAndNewlines)
        child.setupNotes = setupNotes.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// The recording plan on the add and edit sheets. Weekday numbers are `Calendar` weekdays, 1 = Sunday.
struct ScheduleDraft {
    enum Frequency: Equatable {
        case everyDay
        case specificWeekdays
        case timesPerWeek
    }

    static let weekdayChoices: [(number: Int, title: String)] = [
        (2, "Mon"), (3, "Tue"), (4, "Wed"), (5, "Thu"), (6, "Fri"), (7, "Sat"), (1, "Sun"),
    ]

    var frequency: Frequency = .everyDay
    var timesPerWeek = 3
    var weekdays: Set<Int> = []
    var durationMinutes = Schedule.defaultDurationMinutes
    var reminder = ScheduleDraft.defaultReminder

    var isComplete: Bool {
        frequency != .specificWeekdays || !weekdays.isEmpty
    }

    init() {}

    init(schedule: Schedule?) {
        switch schedule?.cadence ?? .everyDay {
        case .everyDay:
            frequency = .everyDay
        case .specificWeekdays:
            frequency = .specificWeekdays
        case .timesPerWeek(let count):
            frequency = .timesPerWeek
            timesPerWeek = Self.clampedTimes(count)
        }
        if frequency != .timesPerWeek {
            timesPerWeek = Self.clampedTimes(schedule?.timesPerWeek ?? 3)
        }
        weekdays = Set((schedule?.weekdays ?? []).filter { (1...7).contains($0) })
        durationMinutes = min(15, max(1, schedule?.durationMinutes ?? Schedule.defaultDurationMinutes))
        reminder = Self.reminderDate(
            hour: schedule?.reminderHour ?? Schedule.defaultReminderHour,
            minute: schedule?.reminderMinute ?? Schedule.defaultReminderMinute
        )
    }

    var cadence: ScheduleCadence {
        switch frequency {
        case .everyDay:
            .everyDay
        case .specificWeekdays:
            .specificWeekdays
        case .timesPerWeek:
            .timesPerWeek(Self.clampedTimes(timesPerWeek))
        }
    }

    /// Copies the draft onto `schedule` through `ClinicSchedulePayload` and `Schedule.apply`.
    func apply(to schedule: Schedule) {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: reminder)
        let source = Schedule(
            cadence: cadence,
            weekdays: weekdays,
            durationMinutes: durationMinutes,
            reminderHour: parts.hour ?? Schedule.defaultReminderHour,
            reminderMinute: parts.minute ?? Schedule.defaultReminderMinute,
            recordWhenSymptoms: true
        )
        schedule.apply(ClinicSchedulePayload(schedule: source))
    }

    static func timesTitle(_ count: Int) -> String {
        count == 1 ? "1 time a week" : "\(count) times a week"
    }

    private static func clampedTimes(_ count: Int) -> Int {
        min(7, max(1, count))
    }

    private static var defaultReminder: Date {
        reminderDate(hour: Schedule.defaultReminderHour, minute: Schedule.defaultReminderMinute)
    }

    private static func reminderDate(hour: Int, minute: Int) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components) ?? .now
    }
}
