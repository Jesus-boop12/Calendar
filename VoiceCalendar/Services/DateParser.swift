import Foundation

/// A date (and optional end date) pulled out of free-form speech.
struct ParsedDate: Equatable {
    var start: Date
    var end: Date?
    /// True when the user said a time of day ("at 3", "noon", "this evening"), false for date-only phrases.
    var hasExplicitTime: Bool
    /// Where the date phrase sits in the original text, so it can be removed from the title.
    var range: Range<String.Index>
}

struct ParsedDuration: Equatable {
    var seconds: TimeInterval
    var range: Range<String.Index>
}

enum RecurrenceSpec: Equatable {
    case daily
    case weekdays
    /// `weekday` uses `Calendar` numbering: 1 = Sunday … 7 = Saturday. Nil means "same weekday as the start".
    case weekly(weekday: Int?)
    case monthly
    case yearly

    var spokenDescription: String {
        switch self {
        case .daily: return "every day"
        case .weekdays: return "every weekday"
        case .weekly(let weekday):
            if let weekday, (1...7).contains(weekday) {
                return "every " + Calendar.current.weekdaySymbols[weekday - 1]
            }
            return "every week"
        case .monthly: return "every month"
        case .yearly: return "every year"
        }
    }
}

/// Extracts dates, durations and recurrence from natural language using `NSDataDetector`
/// plus a handful of speech-friendly heuristics.
struct DateParser {
    var calendar: Calendar
    var now: Date

    init(calendar: Calendar = .current, now: Date = Date()) {
        self.calendar = calendar
        self.now = now
    }

    private static let numberWords: [String: Double] = [
        "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
        "seven": 7, "eight": 8, "nine": 9, "ten": 10, "twelve": 12, "fifteen": 15, "twenty": 20,
        "thirty": 30, "forty five": 45, "forty-five": 45, "ninety": 90,
        "half an": 0.5, "half a": 0.5, "a half": 0.5, "a couple of": 2, "couple of": 2, "a few": 3
    ]

    private static let numberAlternation =
        "\\d+(?:\\.\\d+)?|a couple of|couple of|a few|half an|half a|an|a|one|two|three|four|five|six|seven|eight|nine|ten|twelve|fifteen|twenty|thirty|forty[- ]five|ninety"

    // MARK: - Dates

    func extract(from text: String) -> ParsedDate? {
        if let relative = extractRelative(from: text) { return relative }
        if let detected = extractWithDetector(from: text) { return detected }
        return extractKeyword(from: text)
    }

    /// "in 30 minutes", "in an hour", "in 2 days"
    private func extractRelative(from text: String) -> ParsedDate? {
        let pattern = "\\bin\\s+(\(Self.numberAlternation))\\s+(minutes?|mins?|hours?|hrs?|days?|weeks?|months?)\\b"
        guard let match = Pattern.first(pattern, in: text),
              let amountText = match.group(1)?.lowercased(),
              let unit = match.group(2)?.lowercased() else { return nil }
        let amount = Double(amountText) ?? Self.numberWords[amountText] ?? 1

        var start = now
        var explicitTime = true
        if unit.hasPrefix("min") {
            start = now.addingTimeInterval(amount * 60)
        } else if unit.hasPrefix("h") {
            start = now.addingTimeInterval(amount * 3600)
        } else if unit.hasPrefix("day") {
            start = calendar.date(byAdding: .day, value: Int(amount.rounded()), to: now) ?? now
            explicitTime = false
        } else if unit.hasPrefix("week") {
            start = calendar.date(byAdding: .day, value: Int((amount * 7).rounded()), to: now) ?? now
            explicitTime = false
        } else if unit.hasPrefix("month") {
            start = calendar.date(byAdding: .month, value: Int(amount.rounded()), to: now) ?? now
            explicitTime = false
        }
        // Round down to the minute so notifications line up with what was said.
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: start)
        start = calendar.date(from: components) ?? start
        return ParsedDate(start: start, end: nil, hasExplicitTime: explicitTime, range: match.range)
    }

    private func extractWithDetector(from text: String) -> ParsedDate? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = detector.matches(in: text, options: [], range: nsRange)

        for match in matches {
            guard let date = match.date, let range = Range(match.range, in: text) else { continue }
            let matched = String(text[range])
            let lower = matched.lowercased()

            var start = date
            var explicitTime = Self.containsExplicitTime(lower)
            if !explicitTime, let hour = Self.dayPartHour(lower) {
                start = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: date) ?? date
                explicitTime = true
            }
            start = disambiguateBareHour(start, matched: lower)
            start = rollForwardIfPast(start, matched: lower, explicitTime: explicitTime)

            var end: Date?
            if match.duration > 0 {
                end = start.addingTimeInterval(match.duration)
            }
            return ParsedDate(start: start, end: end, hasExplicitTime: explicitTime, range: range)
        }
        return nil
    }

    /// Phrases `NSDataDetector` does not reliably understand.
    private func extractKeyword(from text: String) -> ParsedDate? {
        let today = calendar.startOfDay(for: now)
        let keywords: [(pattern: String, resolve: () -> (Date, Bool)?)] = [
            ("\\bend of (?:the )?day\\b", { (self.calendar.date(bySettingHour: 17, minute: 0, second: 0, of: today) ?? today, true) }),
            ("\\bnext week\\b", {
                guard let interval = self.calendar.dateInterval(of: .weekOfYear, for: self.now) else { return nil }
                return (interval.end, false)
            }),
            ("\\bthis weekend\\b", { (self.nextWeekday(7, from: self.now, includeToday: true), false) }),
            ("\\bnext weekend\\b", {
                let saturday = self.nextWeekday(7, from: self.now, includeToday: false)
                return (self.calendar.date(byAdding: .day, value: 7, to: saturday) ?? saturday, false)
            }),
            ("\\bright now\\b|\\bnow\\b", { (self.now, true) })
        ]
        for keyword in keywords {
            if let match = Pattern.first(keyword.pattern, in: text), let resolved = keyword.resolve() {
                return ParsedDate(start: resolved.0, end: nil, hasExplicitTime: resolved.1, range: match.range)
            }
        }
        return nil
    }

    // MARK: - Durations

    /// "for 2 hours", "for 30 minutes", "for an hour and a half"
    func extractDuration(from text: String) -> ParsedDuration? {
        let special: [(String, TimeInterval)] = [
            ("\\bfor\\s+(?:about\\s+|around\\s+)?an hour and a half\\b", 90 * 60),
            ("\\bfor\\s+(?:about\\s+|around\\s+)?(?:half an hour|a half hour|half hour)\\b", 30 * 60),
            ("\\bfor\\s+(?:about\\s+|around\\s+)?(?:a quarter hour|quarter of an hour)\\b", 15 * 60)
        ]
        for (pattern, seconds) in special {
            if let match = Pattern.first(pattern, in: text) {
                return ParsedDuration(seconds: seconds, range: match.range)
            }
        }
        let pattern = "\\bfor\\s+(?:about\\s+|around\\s+)?(\(Self.numberAlternation))\\s+(hours?|hrs?|minutes?|mins?)\\b"
        guard let match = Pattern.first(pattern, in: text),
              let amountText = match.group(1)?.lowercased(),
              let unit = match.group(2)?.lowercased() else { return nil }
        let amount = Double(amountText) ?? Self.numberWords[amountText] ?? 1
        let seconds = unit.hasPrefix("h") ? amount * 3600 : amount * 60
        return ParsedDuration(seconds: seconds, range: match.range)
    }

    // MARK: - Recurrence

    func extractRecurrence(from text: String) -> (spec: RecurrenceSpec, range: Range<String.Index>)? {
        let pattern = "\\b(?:every|each)\\s+(day|morning|evening|night|week|month|year|weekday|monday|tuesday|wednesday|thursday|friday|saturday|sunday)s?\\b|\\b(daily|weekly|monthly|yearly|annually)\\b"
        guard let match = Pattern.first(pattern, in: text) else { return nil }
        let word = (match.group(1) ?? match.group(2) ?? "").lowercased()
        let spec: RecurrenceSpec
        switch word {
        case "day", "morning", "evening", "night", "daily": spec = .daily
        case "weekday": spec = .weekdays
        case "week", "weekly": spec = .weekly(weekday: nil)
        case "month", "monthly": spec = .monthly
        case "year", "yearly", "annually": spec = .yearly
        default:
            if let index = calendar.weekdaySymbols.firstIndex(where: { $0.lowercased() == word }) {
                spec = .weekly(weekday: index + 1)
            } else {
                spec = .weekly(weekday: nil)
            }
        }
        return (spec, match.range)
    }

    // MARK: - Helpers

    func nextWeekday(_ weekday: Int, from date: Date, includeToday: Bool) -> Date {
        let today = calendar.startOfDay(for: date)
        let current = calendar.component(.weekday, from: today)
        var delta = (weekday - current + 7) % 7
        if delta == 0 && !includeToday { delta = 7 }
        return calendar.date(byAdding: .day, value: delta, to: today) ?? today
    }

    static func containsExplicitTime(_ lower: String) -> Bool {
        Pattern.matches("\\d{1,2}(?::\\d{2})?\\s*(?:a\\.?m\\.?|p\\.?m\\.?)\\b|\\d{1,2}:\\d{2}|\\bnoon\\b|\\bmidnight\\b|\\bo'?clock\\b|\\bat\\s+\\d{1,2}\\b", in: lower)
    }

    /// Default hours for vague parts of the day.
    static func dayPartHour(_ lower: String) -> Int? {
        if lower.contains("morning") { return 9 }
        if lower.contains("lunch") { return 12 }
        if lower.contains("afternoon") { return 14 }
        if lower.contains("evening") { return 18 }
        if lower.contains("tonight") || lower.contains("night") { return 20 }
        return nil
    }

    /// "at 3" (no AM/PM) is far more likely to mean 3 PM than 3 AM.
    private func disambiguateBareHour(_ date: Date, matched: String) -> Date {
        guard let match = Pattern.first("\\bat\\s+(\\d{1,2})(?::\\d{2})?\\b(?!\\s*(?:a\\.?m|p\\.?m|o'?clock))", in: matched),
              let hourText = match.group(1), let spokenHour = Int(hourText) else { return date }
        let hour = calendar.component(.hour, from: date)
        if hour == spokenHour, (1...6).contains(hour) {
            return calendar.date(byAdding: .hour, value: 12, to: date) ?? date
        }
        return date
    }

    private func rollForwardIfPast(_ date: Date, matched: String, explicitTime: Bool) -> Date {
        guard date < now.addingTimeInterval(-60) else { return date }
        if matched.contains("yesterday") || matched.contains("ago") || matched.contains("last ") { return date }
        let hasAmPm = Pattern.matches("\\b(?:a\\.?m|p\\.?m)\\b", in: matched)

        if explicitTime, calendar.isDate(date, inSameDayAs: now), !hasAmPm,
           let later = calendar.date(byAdding: .hour, value: 12, to: date),
           later > now, calendar.isDate(later, inSameDayAs: now) {
            return later
        }
        if Pattern.matches("\\b(19|20)\\d{2}\\b", in: matched) { return date }
        if Pattern.matches("\\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\\b", in: matched),
           let nextYear = calendar.date(byAdding: .year, value: 1, to: date) {
            return nextYear
        }
        if calendar.isDate(date, inSameDayAs: now), let tomorrow = calendar.date(byAdding: .day, value: 1, to: date) {
            return tomorrow
        }
        return date
    }
}
