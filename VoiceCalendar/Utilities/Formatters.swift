import Foundation

enum Formatters {
    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    static let weekdayDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEE, MMMM d")
        return formatter
    }()

    static let monthYear: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter
    }()

    static let dayNumber: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("d")
        return formatter
    }()

    static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    /// "Today at 3:00 PM", "Tomorrow at 9:00 AM", "Friday, Oct 17 at 2:30 PM"
    static func spoken(_ date: Date, allDay: Bool = false, calendar: Calendar = .current, now: Date = Date()) -> String {
        let dayPart: String
        if calendar.isDate(date, inSameDayAs: now) {
            dayPart = "today"
        } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            dayPart = "tomorrow"
        } else if let week = calendar.date(byAdding: .day, value: 6, to: now), date < week, date > now {
            let formatter = DateFormatter()
            formatter.setLocalizedDateFormatFromTemplate("EEEE")
            dayPart = "on " + formatter.string(from: date)
        } else {
            let formatter = DateFormatter()
            formatter.setLocalizedDateFormatFromTemplate("EEEE MMMM d")
            dayPart = "on " + formatter.string(from: date)
        }
        if allDay { return dayPart }
        return "\(dayPart) at \(time.string(from: date))"
    }

    /// Compact display used in lists: "Today 3:00 PM", "Tomorrow", "Oct 17, 2:30 PM".
    static func compact(_ date: Date, allDay: Bool = false, calendar: Calendar = .current) -> String {
        let now = Date()
        let day: String
        if calendar.isDateInToday(date) {
            day = "Today"
        } else if calendar.isDateInTomorrow(date) {
            day = "Tomorrow"
        } else if calendar.isDateInYesterday(date) {
            day = "Yesterday"
        } else if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            let formatter = DateFormatter()
            formatter.setLocalizedDateFormatFromTemplate("EEE MMM d")
            day = formatter.string(from: date)
        } else {
            day = shortDate.string(from: date)
        }
        return allDay ? day : "\(day) · \(time.string(from: date))"
    }
}
