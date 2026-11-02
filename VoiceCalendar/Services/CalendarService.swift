import EventKit
import Foundation
import Observation

enum CalendarError: LocalizedError {
    case noCalendarAccess
    case noReminderAccess
    case noWritableCalendar
    case noWritableReminderList
    case eventNotFound(String)

    var errorDescription: String? {
        switch self {
        case .noCalendarAccess:
            return "I need access to your calendar first. You can allow it in Settings."
        case .noReminderAccess:
            return "I need access to Reminders first. You can allow it in Settings."
        case .noWritableCalendar:
            return "There is no calendar I can write to. Add an account in the Calendar app."
        case .noWritableReminderList:
            return "There is no reminder list I can write to. Add one in the Reminders app."
        case .eventNotFound(let query):
            return "I couldn't find an event matching “\(query)”."
        }
    }
}

/// Thin wrapper around `EKEventStore` that keeps the app in sync with the iPhone Calendar and Reminders apps.
@Observable
@MainActor
final class CalendarService {
    let store = EKEventStore()
    private let calendar = Calendar.current

    /// Bumped whenever EventKit reports a change so SwiftUI views can reload.
    private(set) var changeToken = 0
    @ObservationIgnored private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.changeToken += 1
            }
        }
    }

    // MARK: - Access

    var hasEventAccess: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }
    var hasReminderAccess: Bool { EKEventStore.authorizationStatus(for: .reminder) == .fullAccess }

    @discardableResult
    func requestEventAccess() async -> Bool {
        do {
            let granted = try await store.requestFullAccessToEvents()
            changeToken += 1
            return granted
        } catch {
            return false
        }
    }

    @discardableResult
    func requestReminderAccess() async -> Bool {
        do {
            let granted = try await store.requestFullAccessToReminders()
            changeToken += 1
            return granted
        } catch {
            return false
        }
    }

    // MARK: - Reading events

    func events(from start: Date, to end: Date) -> [EKEvent] {
        guard hasEventAccess, end > start else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).sorted { lhs, rhs in
            if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
            return lhs.startDate < rhs.startDate
        }
    }

    func events(on day: Date) -> [EKEvent] {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        return events(from: start, to: end)
    }

    /// Events grouped by the day they start on, for the month grid.
    func eventsByDay(inMonthOf date: Date) -> [Date: [EKEvent]] {
        guard let interval = calendar.dateInterval(of: .month, for: date) else { return [:] }
        let padded = calendar.date(byAdding: .day, value: -7, to: interval.start) ?? interval.start
        let paddedEnd = calendar.date(byAdding: .day, value: 14, to: interval.end) ?? interval.end
        var result: [Date: [EKEvent]] = [:]
        for event in events(from: padded, to: paddedEnd) {
            let key = calendar.startOfDay(for: event.startDate)
            result[key, default: []].append(event)
        }
        return result
    }

    func nextEvent(after date: Date = Date()) -> EKEvent? {
        guard let horizon = calendar.date(byAdding: .day, value: 30, to: date) else { return nil }
        return events(from: date, to: horizon).first { !$0.isAllDay && $0.startDate > date }
            ?? events(from: date, to: horizon).first { $0.endDate > date }
    }

    func event(withIdentifier identifier: String) -> EKEvent? {
        store.event(withIdentifier: identifier)
    }

    // MARK: - Writing events

    @discardableResult
    func createEvent(from draft: EventDraft, alarmLeadMinutes: Int?, notes: String? = nil) throws -> EKEvent {
        guard hasEventAccess else { throw CalendarError.noCalendarAccess }
        guard let target = store.defaultCalendarForNewEvents
                ?? store.calendars(for: .event).first(where: { $0.allowsContentModifications }) else {
            throw CalendarError.noWritableCalendar
        }
        let event = EKEvent(eventStore: store)
        event.calendar = target
        apply(draft, to: event)
        if let notes, !notes.isEmpty { event.notes = notes }
        if let lead = alarmLeadMinutes {
            event.addAlarm(EKAlarm(relativeOffset: TimeInterval(-lead * 60)))
        }
        try store.save(event, span: .thisEvent, commit: true)
        changeToken += 1
        return event
    }

    func apply(_ draft: EventDraft, to event: EKEvent) {
        event.title = draft.title
        event.isAllDay = draft.isAllDay
        if draft.isAllDay {
            let start = calendar.startOfDay(for: draft.start)
            event.startDate = start
            event.endDate = max(calendar.startOfDay(for: draft.end), start)
        } else {
            event.startDate = draft.start
            event.endDate = max(draft.end, draft.start.addingTimeInterval(5 * 60))
        }
        event.location = draft.location?.isEmpty == false ? draft.location : nil
        if let recurrence = draft.recurrence {
            event.recurrenceRules = [recurrenceRule(for: recurrence)]
        }
    }

    func save(_ event: EKEvent, span: EKSpan = .thisEvent) throws {
        try store.save(event, span: span, commit: true)
        changeToken += 1
    }

    func delete(_ event: EKEvent, span: EKSpan = .thisEvent) throws {
        try store.remove(event, span: span, commit: true)
        changeToken += 1
    }

    /// Finds the best event match for a spoken title, optionally limited to one day.
    func findEvent(matching query: String, on day: Date?) -> EKEvent? {
        let candidates: [EKEvent]
        if let day {
            candidates = events(on: day)
        } else {
            let horizon = calendar.date(byAdding: .day, value: 60, to: Date()) ?? Date()
            candidates = events(from: Date(), to: horizon)
        }
        let needle = query.lowercased().trimmingEdgePunctuation()
        guard !needle.isEmpty else { return candidates.first }
        if let exact = candidates.first(where: { ($0.title ?? "").lowercased() == needle }) { return exact }
        if let contains = candidates.first(where: { ($0.title ?? "").lowercased().contains(needle) }) { return contains }
        let words = needle.split(separator: " ").map(String.init).filter { $0.count > 2 }
        return candidates.first { event in
            let title = (event.title ?? "").lowercased()
            return words.contains { title.contains($0) }
        }
    }

    func recurrenceRule(for spec: RecurrenceSpec) -> EKRecurrenceRule {
        switch spec {
        case .daily:
            return EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil)
        case .weekdays:
            let days: [EKWeekday] = [.monday, .tuesday, .wednesday, .thursday, .friday]
            return EKRecurrenceRule(recurrenceWith: .weekly,
                                    interval: 1,
                                    daysOfTheWeek: days.map { EKRecurrenceDayOfWeek($0) },
                                    daysOfTheMonth: nil,
                                    monthsOfTheYear: nil,
                                    weeksOfTheYear: nil,
                                    daysOfTheYear: nil,
                                    setPositions: nil,
                                    end: nil)
        case .weekly(let weekday):
            if let weekday, let day = EKWeekday(rawValue: weekday) {
                return EKRecurrenceRule(recurrenceWith: .weekly,
                                        interval: 1,
                                        daysOfTheWeek: [EKRecurrenceDayOfWeek(day)],
                                        daysOfTheMonth: nil,
                                        monthsOfTheYear: nil,
                                        weeksOfTheYear: nil,
                                        daysOfTheYear: nil,
                                        setPositions: nil,
                                        end: nil)
            }
            return EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil)
        case .monthly:
            return EKRecurrenceRule(recurrenceWith: .monthly, interval: 1, end: nil)
        case .yearly:
            return EKRecurrenceRule(recurrenceWith: .yearly, interval: 1, end: nil)
        }
    }

    // MARK: - Reminders

    func fetchIncompleteReminders() async -> [EKReminder] {
        guard hasReminderAccess else { return [] }
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        let reminders: [EKReminder] = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }
        return reminders.sorted { lhs, rhs in
            switch (dueDate(of: lhs), dueDate(of: rhs)) {
            case let (l?, r?): return l < r
            case (nil, _?): return false
            case (_?, nil): return true
            default: return (lhs.title ?? "") < (rhs.title ?? "")
            }
        }
    }

    func dueDate(of reminder: EKReminder) -> Date? {
        guard let components = reminder.dueDateComponents else { return nil }
        return calendar.date(from: components)
    }

    @discardableResult
    func createReminder(title: String, due: Date?, notes: String? = nil, addAlarm: Bool) throws -> EKReminder {
        guard hasReminderAccess else { throw CalendarError.noReminderAccess }
        guard let target = store.defaultCalendarForNewReminders()
                ?? store.calendars(for: .reminder).first(where: { $0.allowsContentModifications }) else {
            throw CalendarError.noWritableReminderList
        }
        let reminder = EKReminder(eventStore: store)
        reminder.calendar = target
        reminder.title = title
        if let notes, !notes.isEmpty { reminder.notes = notes }
        if let due {
            reminder.dueDateComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: due)
            if addAlarm {
                reminder.addAlarm(EKAlarm(absoluteDate: due))
            }
        }
        try store.save(reminder, commit: true)
        changeToken += 1
        return reminder
    }

    func setReminder(_ reminder: EKReminder, completed: Bool) throws {
        reminder.isCompleted = completed
        try store.save(reminder, commit: true)
        changeToken += 1
    }

    func delete(_ reminder: EKReminder) throws {
        try store.remove(reminder, commit: true)
        changeToken += 1
    }
}
