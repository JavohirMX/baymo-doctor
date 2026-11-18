import SwiftUI

struct BaselineFileSummary: Equatable {
    var fileName: String
    var recordedAt: Date
}

struct ChildDetailsForm: View {
    @Binding var details: PatientDetailsDraft

    var body: some View {
        Section {
            TextField("Full name", text: $details.fullName)
            TextField("Nickname", text: $details.nickname)
            DatePicker(
                "Date of birth",
                selection: birthDateBinding,
                in: dateRange,
                displayedComponents: .date
            )
            Picker("Sex", selection: $details.sex) {
                ForEach(ChildSex.allCases) { sex in
                    Text(sex.title).tag(sex)
                }
            }
            TextField("Health condition", text: $details.conditionText, axis: .vertical)
                .lineLimit(2...4)
            TextField("Setup notes", text: $details.setupNotes, axis: .vertical)
                .lineLimit(3...6)
        }
    }

    private var birthDateBinding: Binding<Date> {
        Binding(
            get: { details.birthDate ?? suggestedBirth },
            set: { details.birthDate = min($0, .now) }
        )
    }

    private var dateRange: ClosedRange<Date> {
        let start = Calendar.current.date(byAdding: .year, value: -120, to: .now) ?? .distantPast
        let end = Date.now
        return start <= end ? start...end : end...end
    }

    private var suggestedBirth: Date {
        let shifted = Calendar.current.date(byAdding: .year, value: -8, to: .now) ?? .now
        return Calendar.current.startOfDay(for: shifted)
    }
}

struct BaselineFileCard: View {
    var file: BaselineFileSummary?
    var error: String?
    var footnote: String?
    var onChoose: () -> Void

    var body: some View {
        Section("Baseline ECG") {
            if let file {
                LabeledContent("File") {
                    Text(file.fileName)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                LabeledContent("Recorded", value: file.recordedAt.formatted(date: .abbreviated, time: .omitted))
                ClinicSecondaryButton(title: "Replace", action: onChoose)
                    .fixedSize()
            } else {
                Text("JSON or CSV with at least one ECG lead.")
                    .foregroundStyle(ClinicPalette.secondaryText)
                ClinicSecondaryButton(title: "Choose file", action: onChoose)
                    .fixedSize()
            }
            if let footnote {
                Text(footnote)
                    .font(.caption)
                    .foregroundStyle(ClinicPalette.secondaryText)
            }
            if let error {
                Text(error)
                    .foregroundStyle(ClinicPalette.foreground(.red))
            }
        }
    }
}

struct ScheduleForm: View {
    @Binding var draft: ScheduleDraft

    var body: some View {
        Section("Recording schedule") {
            Picker("How often", selection: frequencyChoice) {
                Text("Every day").tag(ScheduleChoice.everyDay)
                Text("Specific days").tag(ScheduleChoice.specificWeekdays)
                Divider()
                ForEach(1...7, id: \.self) { count in
                    Text(ScheduleDraft.timesTitle(count)).tag(ScheduleChoice.times(count))
                }
            }
            .pickerStyle(.menu)
            if draft.frequency == .specificWeekdays {
                LabeledContent("Days") {
                    HStack(spacing: 4) {
                        ForEach(ScheduleDraft.weekdayChoices, id: \.number) { day in
                            dayChip(number: day.number, title: day.title)
                        }
                    }
                    .fixedSize(horizontal: true, vertical: true)
                }
                if draft.weekdays.isEmpty {
                    Text("Choose at least one day.")
                        .foregroundStyle(ClinicPalette.secondaryText)
                }
            } else if draft.frequency == .timesPerWeek {
                Text(timesNote)
                    .font(.callout)
                    .foregroundStyle(ClinicPalette.secondaryText)
            }
            LabeledContent("Length") {
                Stepper(value: $draft.durationMinutes, in: 1...15) {
                    Text("\(draft.durationMinutes) min")
                }
                .fixedSize()
            }
            .accessibilityValue("\(draft.durationMinutes) minutes")
            DatePicker("Reminder", selection: $draft.reminder, displayedComponents: .hourAndMinute)
                .datePickerStyle(.stepperField)
            Toggle("Record when symptoms happen", isOn: $draft.recordWhenSymptoms)
        }
    }

    private var timesNote: String {
        let count = min(7, max(1, draft.timesPerWeek))
        return count == 1 ? "Any 1 day in the week." : "Any \(count) days in the week."
    }

    @ViewBuilder
    private func dayChip(number: Int, title: String) -> some View {
        let selected = draft.weekdays.contains(number)
        if selected {
            Button(title) { toggleWeekday(number) }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
        } else {
            Button(title) { toggleWeekday(number) }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
        }
    }

    private func toggleWeekday(_ number: Int) {
        if draft.weekdays.contains(number) {
            draft.weekdays.remove(number)
        } else {
            draft.weekdays.insert(number)
        }
    }

    private var frequencyChoice: Binding<ScheduleChoice> {
        Binding {
            switch draft.frequency {
            case .everyDay: .everyDay
            case .specificWeekdays: .specificWeekdays
            case .timesPerWeek: .times(min(7, max(1, draft.timesPerWeek)))
            }
        } set: { choice in
            switch choice {
            case .everyDay:
                draft.frequency = .everyDay
            case .specificWeekdays:
                draft.frequency = .specificWeekdays
            case .times(let count):
                draft.frequency = .timesPerWeek
                draft.timesPerWeek = count
            }
        }
    }

    private enum ScheduleChoice: Hashable {
        case everyDay
        case specificWeekdays
        case times(Int)
    }
}

struct AddPatientStepHeader: View {
    enum Step {
        case details
        case baseline
    }

    var step: Step

    var body: some View {
        HStack(spacing: 20) {
            AddPatientStepItem(
                index: "1",
                title: "Child details",
                state: step == .details ? .current : .complete
            )
            AddPatientStepItem(
                index: "2",
                title: "Baseline and schedule",
                state: step == .baseline ? .current : .upcoming
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(step == .details ? "Step 1 of 2, Child details" : "Step 2 of 2, Baseline and schedule")
    }
}

private struct AddPatientStepItem: View {
    enum State {
        case current
        case complete
        case upcoming
    }

    var index: String
    var title: String
    var state: State

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(fill)
                if state == .upcoming {
                    Circle().strokeBorder(ClinicPalette.separator)
                }
                if state == .complete {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(ClinicPalette.accentInk)
                } else {
                    Text(index)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(state == .current ? Color.white : ClinicPalette.secondaryText)
                }
            }
            .frame(width: 20, height: 20)
            Text(title)
                .font(state == .current ? .body.weight(.semibold) : .body)
                .foregroundStyle(state == .upcoming ? ClinicPalette.secondaryText : ClinicPalette.primaryText)
        }
    }

    private var fill: Color {
        switch state {
        case .current:
            ClinicPalette.accent
        case .complete:
            ClinicPalette.accentInk.opacity(0.16)
        case .upcoming:
            Color.clear
        }
    }
}
