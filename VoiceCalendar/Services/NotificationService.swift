import EventKit
import Foundation
import UserNotifications

/// Schedules local notifications for events, reminders, tasks and the daily briefing.
final class NotificationService {
    static let shared = NotificationService()

    enum Category {
        static let event = "EVENT"
        static let reminder = "REMINDER"
        static let task = "TASK"
        static let briefing = "BRIEFING"
    }

    private let center = UNUserNotificationCenter.current()
    private let dailyBriefingIdentifier = "daily-briefing"

    private init() {
        registerCategories()
    }

    // MARK: - Authorization

    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            return false
        }
    }

    private func registerCategories() {
        let complete = UNNotificationAction(identifier: "COMPLETE_TASK", title: "Mark Done", options: [])
        let taskCategory = UNNotificationCategory(identifier: Category.task, actions: [complete], intentIdentifiers: [])
        let eventCategory = UNNotificationCategory(identifier: Category.event, actions: [], intentIdentifiers: [])
        let reminderCategory = UNNotificationCategory(identifier: Category.reminder, actions: [], intentIdentifiers: [])
        let briefingCategory = UNNotificationCategory(identifier: Category.briefing, actions: [], intentIdentifiers: [])
        center.setNotificationCategories([taskCategory, eventCategory, reminderCategory, briefingCategory])
    }

    // MARK: - Generic scheduling

    /// Schedules a one-off notification at `date`. Dates in the past are ignored.
    func schedule(identifier: String,
                  title: String,
                  body: String,
                  at date: Date,
                  category: String,
                  userInfo: [String: String] = [:]) {
        guard date > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = category
        content.userInfo = userInfo

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        center.add(request)
    }

    func cancel(identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    // MARK: - Events

    static func eventIdentifier(_ event: EKEvent) -> String {
        "event-\(event.eventIdentifier ?? event.calendarItemIdentifier)"
    }

    func scheduleEventNotification(for event: EKEvent, leadMinutes: Int) {
        guard let start = event.startDate else { return }
        let fireDate = event.isAllDay
            ? Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: start) ?? start
            : start.addingTimeInterval(TimeInterval(-leadMinutes * 60))

        let title = event.title ?? "Upcoming event"
        let body: String
        if event.isAllDay {
            body = "All day today"
        } else if leadMinutes == 0 {
            body = "Starting now" + (event.location.map { " · \($0)" } ?? "")
        } else {
            body = "Starts in \(leadMinutes) minutes at \(Formatters.time.string(from: start))"
                + (event.location.map { " · \($0)" } ?? "")
        }
        schedule(identifier: Self.eventIdentifier(event),
                 title: title,
                 body: body,
                 at: fireDate,
                 category: Category.event,
                 userInfo: ["eventIdentifier": event.eventIdentifier ?? ""])
    }

    func cancelEventNotification(for event: EKEvent) {
        cancel(identifiers: [Self.eventIdentifier(event)])
    }

    // MARK: - Reminders

    static func reminderIdentifier(_ reminder: EKReminder) -> String {
        "reminder-\(reminder.calendarItemIdentifier)"
    }

    func scheduleReminderNotification(for reminder: EKReminder, at date: Date) {
        schedule(identifier: Self.reminderIdentifier(reminder),
                 title: "Reminder",
                 body: reminder.title ?? "You asked to be reminded",
                 at: date,
                 category: Category.reminder)
    }

    func cancelReminderNotification(for reminder: EKReminder) {
        cancel(identifiers: [Self.reminderIdentifier(reminder)])
    }

    // MARK: - Tasks

    func scheduleTaskNotification(for task: TaskItem) {
        cancel(identifiers: [task.notificationIdentifier])
        guard let due = task.dueDate, !task.isCompleted else { return }
        schedule(identifier: task.notificationIdentifier,
                 title: "Task due",
                 body: task.title,
                 at: due,
                 category: Category.task,
                 userInfo: ["taskID": task.id.uuidString])
    }

    func cancelTaskNotification(for task: TaskItem) {
        cancel(identifiers: [task.notificationIdentifier])
    }

    // MARK: - Daily briefing

    /// Schedules (or replaces) tomorrow morning's summary. Call this whenever the agenda changes.
    func scheduleDailyBriefing(enabled: Bool, hour: Int, eventsTomorrow: [EKEvent], tasksTomorrow: [TaskItem]) {
        cancel(identifiers: [dailyBriefingIdentifier])
        guard enabled else { return }

        let calendar = Calendar.current
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())),
              let fireDate = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: tomorrow) else { return }

        var parts: [String] = []
        if eventsTomorrow.isEmpty {
            parts.append("No events on your calendar.")
        } else {
            let first = eventsTomorrow.sorted { $0.startDate < $1.startDate }.prefix(3)
            let names = first.map { event -> String in
                if event.isAllDay { return event.title ?? "Event" }
                return "\(event.title ?? "Event") at \(Formatters.time.string(from: event.startDate))"
            }
            let more = eventsTomorrow.count > 3 ? " and \(eventsTomorrow.count - 3) more" : ""
            parts.append("\(eventsTomorrow.count) event\(eventsTomorrow.count == 1 ? "" : "s"): \(names.joined(separator: ", "))\(more).")
        }
        if !tasksTomorrow.isEmpty {
            parts.append("\(tasksTomorrow.count) task\(tasksTomorrow.count == 1 ? "" : "s") due.")
        }

        schedule(identifier: dailyBriefingIdentifier,
                 title: "Good morning ☀️",
                 body: parts.joined(separator: " "),
                 at: fireDate,
                 category: Category.briefing)
    }
}
