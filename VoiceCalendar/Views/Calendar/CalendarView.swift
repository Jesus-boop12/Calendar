import EventKit
import SwiftUI

struct CalendarView: View {
    @Environment(CalendarService.self) private var calendarService

    @State private var displayedMonth = Calendar.current.startOfMonth(for: Date())
    @State private var selectedDate = Date()
    @State private var eventsByDay: [Date: [EKEvent]] = [:]
    @State private var selection: EventSelection?
    @State private var creating = false

    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                MonthGridView(month: displayedMonth, selectedDate: $selectedDate, eventsByDay: eventsByDay)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .gesture(
                        DragGesture(minimumDistance: 40)
                            .onEnded { value in
                                if value.translation.width < -40 {
                                    shiftMonth(by: 1)
                                } else if value.translation.width > 40 {
                                    shiftMonth(by: -1)
                                }
                            }
                    )
                Divider()
                    .padding(.top, 10)
                dayList
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(Formatters.monthYear.string(from: displayedMonth))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button { shiftMonth(by: -1) } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel("Previous month")
                    Button("Today") { goToToday() }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { shiftMonth(by: 1) } label: { Image(systemName: "chevron.right") }
                        .accessibilityLabel("Next month")
                    Button { creating = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("New event")
                }
            }
            .task(id: calendarService.changeToken) { reload() }
            .onChange(of: displayedMonth) { reload() }
            .onChange(of: selectedDate) { _, newValue in
                if !calendar.isDate(newValue, equalTo: displayedMonth, toGranularity: .month) {
                    displayedMonth = calendar.startOfMonth(for: newValue)
                }
            }
            .sheet(item: $selection) { selected in
                EventEditorView(mode: .edit(selected.event))
            }
            .sheet(isPresented: $creating) {
                EventEditorView(mode: .create(defaultStart: defaultStart))
            }
        }
    }

    private var selectedEvents: [EKEvent] {
        eventsByDay[calendar.startOfDay(for: selectedDate)] ?? []
    }

    private var dayList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(Formatters.weekdayDate.string(from: selectedDate))
                        .font(.headline)
                    Spacer()
                    if !calendarService.hasEventAccess {
                        Label("No calendar access", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.top, 12)

                if selectedEvents.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "calendar")
                            .font(.title)
                            .foregroundStyle(.tertiary)
                        Text("Nothing planned")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("Add event") { creating = true }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                } else {
                    ForEach(selectedEvents, id: \.calendarItemIdentifier) { event in
                        EventRow(event: event)
                            .onTapGesture { selection = EventSelection(event: event) }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 140)
        }
    }

    private var defaultStart: Date {
        if calendar.isDateInToday(selectedDate) {
            return CommandParser.nextReasonableSlot(after: Date(), calendar: calendar)
        }
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: selectedDate) ?? selectedDate
    }

    private func reload() {
        eventsByDay = calendarService.eventsByDay(inMonthOf: displayedMonth)
    }

    private func shiftMonth(by value: Int) {
        guard let next = calendar.date(byAdding: .month, value: value, to: displayedMonth) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            displayedMonth = calendar.startOfMonth(for: next)
            if !calendar.isDate(selectedDate, equalTo: displayedMonth, toGranularity: .month) {
                selectedDate = displayedMonth
            }
        }
    }

    private func goToToday() {
        withAnimation {
            selectedDate = Date()
            displayedMonth = calendar.startOfMonth(for: Date())
        }
    }
}

struct MonthGridView: View {
    let month: Date
    @Binding var selectedDate: Date
    let eventsByDay: [Date: [EKEvent]]

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 4) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    if let day {
                        DayCell(date: day,
                                isSelected: calendar.isDate(day, inSameDayAs: selectedDate),
                                isToday: calendar.isDateInToday(day),
                                colors: colors(for: day))
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.15)) { selectedDate = day }
                            }
                    } else {
                        Color.clear.frame(height: 48)
                    }
                }
            }
        }
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }

    private var days: [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: interval.start)
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7
        var result: [Date?] = Array(repeating: nil, count: leading)
        for offset in 0..<range.count {
            result.append(calendar.date(byAdding: .day, value: offset, to: interval.start))
        }
        return result
    }

    private func colors(for day: Date) -> [Color] {
        let events = eventsByDay[calendar.startOfDay(for: day)] ?? []
        var seen: [Color] = []
        for event in events {
            let color: Color
            if let cgColor = event.calendar?.cgColor {
                color = Color(cgColor: cgColor)
            } else {
                color = .accentColor
            }
            if !seen.contains(color) { seen.append(color) }
            if seen.count == 3 { break }
        }
        return seen
    }
}

private struct DayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let colors: [Color]

    var body: some View {
        VStack(spacing: 4) {
            Text(Formatters.dayNumber.string(from: date))
                .font(.body.weight(isToday ? .bold : .regular))
                .foregroundStyle(foreground)
                .frame(width: 36, height: 36)
                .background(
                    Circle().fill(isSelected ? Color.accentColor : Color.clear)
                )
                .overlay(
                    Circle().strokeBorder(isToday && !isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
                )
            HStack(spacing: 3) {
                ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                    Circle()
                        .fill(color)
                        .frame(width: 5, height: 5)
                }
            }
            .frame(height: 6)
        }
        .frame(height: 48)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityLabel(Formatters.weekdayDate.string(from: date))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var foreground: Color {
        if isSelected { return .white }
        if isToday { return .accentColor }
        return .primary
    }
}
