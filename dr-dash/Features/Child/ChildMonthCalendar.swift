import SwiftUI

/// Month grid. Choosing a day filters the child timeline to that day.
struct ChildMonthCalendar: View {
    var selectedDay: Date?
    var eventDays: Set<Date>
    var onSelect: (Date) -> Void

    @State private var month: Date

    init(selectedDay: Date?, eventDays: Set<Date>, onSelect: @escaping (Date) -> Void) {
        self.selectedDay = selectedDay
        self.eventDays = eventDays
        self.onSelect = onSelect
        let calendar = Calendar.current
        let initial = selectedDay ?? .now
        let components = calendar.dateComponents([.year, .month], from: initial)
        _month = State(initialValue: calendar.date(from: components) ?? initial)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            weekdayRow
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(cells) { cell in
                    dayCell(cell)
                }
            }
        }
        .padding(12)
        .frame(width: 292)
        .background(ClinicPalette.canvas)
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    }

    private var header: some View {
        HStack {
            Button {
                shiftMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Previous month")

            Spacer(minLength: 8)

            Text(month.formatted(.dateTime.month(.wide).year()))
                .font(.headline)
                .foregroundStyle(ClinicPalette.primaryText)

            Spacer(minLength: 8)

            Button {
                shiftMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Next month")
        }
        .foregroundStyle(ClinicPalette.primaryText)
    }

    private var weekdayRow: some View {
        HStack(spacing: 4) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ClinicPalette.secondaryText)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var weekdaySymbols: [String] {
        let calendar = Calendar.current
        let symbols = calendar.veryShortWeekdaySymbols
        let shift = max(0, calendar.firstWeekday - 1)
        guard symbols.count == 7, shift < symbols.count else { return symbols }
        return Array(symbols[shift...]) + Array(symbols[..<shift])
    }

    private var cells: [ChildCalendarCell] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return [] }
        let first = interval.start
        let weekday = calendar.component(.weekday, from: first)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        let count = calendar.range(of: .day, in: .month, for: first)?.count ?? 0
        var cells: [ChildCalendarCell] = (0..<leading).map { ChildCalendarCell(id: "blank-\($0)", day: nil) }
        for offset in 0..<count {
            let day = calendar.date(byAdding: .day, value: offset, to: first)
            cells.append(ChildCalendarCell(id: "day-\(offset)", day: day))
        }
        return cells
    }

    @ViewBuilder
    private func dayCell(_ cell: ChildCalendarCell) -> some View {
        if let day = cell.day {
            let calendar = Calendar.current
            let isSelected = selectedDay.map { calendar.isDate($0, inSameDayAs: day) } ?? false
            let isToday = calendar.isDateInToday(day)
            let hasEvent = eventDays.contains { calendar.isDate($0, inSameDayAs: day) }
            Button {
                onSelect(calendar.startOfDay(for: day))
            } label: {
                VStack(spacing: 2) {
                    Text("\(calendar.component(.day, from: day))")
                        .font(.callout.weight(isSelected || isToday ? .semibold : .regular))
                    Circle()
                        .fill(hasEvent ? (isSelected ? Color.white : ClinicPalette.accentInk) : Color.clear)
                        .frame(width: 4, height: 4)
                }
                .frame(maxWidth: .infinity, minHeight: 34)
                .foregroundStyle(isSelected ? Color.white : ClinicPalette.primaryText)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(ClinicPalette.accent)
                    } else if isToday {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(ClinicPalette.accentInk, lineWidth: 1)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        } else {
            Color.clear
                .frame(minHeight: 34)
        }
    }

    private func shiftMonth(by value: Int) {
        let calendar = Calendar.current
        guard let shifted = calendar.date(byAdding: .month, value: value, to: month) else { return }
        month = shifted
    }
}

private struct ChildCalendarCell: Identifiable {
    var id: String
    var day: Date?
}
