import Foundation

/// Everything the assistant knows how to do with a spoken sentence.
enum VoiceIntent: Equatable {
    case addEvent(EventDraft)
    case addReminder(title: String, due: Date?)
    case addTask(title: String, due: Date?)
    case addNote(title: String?, body: String)
    case deleteEvent(titleQuery: String, on: Date?)
    case querySchedule(from: Date, to: Date, label: String)
    case queryNext
    case help
    case unknown(String)
}

struct EventDraft: Equatable {
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var location: String?
    var recurrence: RecurrenceSpec?
    /// False when the parser had to invent a time because none was spoken.
    var hadExplicitDate: Bool

    init(title: String,
         start: Date,
         end: Date,
         isAllDay: Bool = false,
         location: String? = nil,
         recurrence: RecurrenceSpec? = nil,
         hadExplicitDate: Bool = true) {
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.location = location
        self.recurrence = recurrence
        self.hadExplicitDate = hadExplicitDate
    }
}

/// Turns a transcript such as "Hey Calendar, add dentist tomorrow at 3 PM for an hour" into a `VoiceIntent`.
struct CommandParser {
    var calendar: Calendar
    var now: Date
    var defaultDurationMinutes: Int
    var wakePhrases: [String]

    init(calendar: Calendar = .current,
         now: Date = Date(),
         defaultDurationMinutes: Int = 60,
         wakePhrases: [String] = [AppSettings.defaultWakePhrase]) {
        self.calendar = calendar
        self.now = now
        self.defaultDurationMinutes = defaultDurationMinutes
        self.wakePhrases = wakePhrases
    }

    private var dateParser: DateParser { DateParser(calendar: calendar, now: now) }

    // MARK: - Entry point

    func parse(_ rawInput: String) -> VoiceIntent {
        let normalizedInput = rawInput
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
        var text = WakeWordDetector.stripping(wakePhrases, from: normalizedInput)
        text = Self.stripPoliteness(text).trimmingEdgePunctuation().collapsingWhitespace()
        text = Self.stripCalendarSuffix(text)
        guard !text.isEmpty else { return .unknown(rawInput) }
        let lower = text.lowercased()

        if Self.helpPhrases.contains(where: { lower == $0 || lower.hasWordPrefix($0) }) {
            return .help
        }
        if lower.containsAny(Self.queryPhrases) {
            return parseQuery(text)
        }
        if lower.hasAnyWordPrefix(Self.deletePrefixes) {
            return parseDelete(text)
        }
        if lower.hasAnyWordPrefix(Self.reminderPrefixes) {
            return parseReminder(text)
        }
        if lower.hasAnyWordPrefix(Self.notePrefixes) {
            return parseNote(text)
        }
        if let task = parseTaskIfMatches(text) {
            return task
        }
        if lower.hasAnyWordPrefix(Self.eventPrefixes) || lower.containsAny([" appointment", " meeting", " event"]) {
            return parseEvent(text)
        }
        if dateParser.extract(from: text) != nil {
            return parseEvent(text)
        }
        return .unknown(text)
    }

    // MARK: - Vocabulary

    private static let helpPhrases = ["help", "what can you do", "what can i say", "commands", "what can i ask", "how do i use this"]

    private static let queryPhrases = [
        "what's on my", "what is on my", "whats on my", "what do i have", "what have i got", "what's my schedule",
        "what is my schedule", "show my schedule", "show me my schedule", "read my schedule", "read me my",
        "what's my day", "how does my day look", "how's my day", "do i have anything", "do i have any",
        "what's next", "what is next", "whats next", "what's coming up", "what is coming up", "anything on my calendar",
        "what's on the calendar", "what's happening", "what am i doing", "when is my next", "what's my next",
        "when's my next", "list my events", "show my events", "my agenda", "what's on today", "what's on tomorrow",
        "am i free", "am i busy"
    ]

    private static let deletePrefixes = ["delete", "cancel", "remove", "clear"]

    private static let reminderPrefixes = [
        "remind me", "set a reminder", "set reminder", "set up a reminder", "add a reminder", "add reminder",
        "create a reminder", "create reminder", "new reminder", "reminder", "remember to", "don't let me forget",
        "dont let me forget", "don't forget to", "dont forget to", "make a reminder"
    ]

    private static let notePrefixes = [
        "take a note", "take note", "take down a note", "make a note", "create a note", "create note", "add a note",
        "add note", "new note", "write a note", "write down", "write this down", "jot down", "note to self",
        "note that", "note", "remember that", "save a note"
    ]

    private static let eventPrefixes = [
        "add", "schedule", "create", "book", "put", "set up", "setup", "make", "plan", "new", "enter",
        "i have a", "i have an", "i've got a", "i've got an", "there's a", "there is a"
    ]

    // MARK: - Pre-processing

    private static func stripPoliteness(_ text: String) -> String {
        let pattern = "^(?:\\s*(?:please|hey|ok|okay|hi|um|uh|can you|could you|would you|will you|i want you to|i'd like you to|i need you to|i want to|i'd like to|go ahead and)[,\\s]+)+"
        if let match = Pattern.first(pattern, in: text) {
            return text.removing(match.range)
        }
        return text
    }

    private static func stripCalendarSuffix(_ text: String) -> String {
        var result = text
        let suffixes = "(?:\\s*,?\\s*(?:please|thanks|thank you|to my calendar|on my calendar|in my calendar|to the calendar|in the calendar|on the calendar|to calendar|to my schedule|on my schedule|in my schedule))+\\s*$"
        if let match = Pattern.first(suffixes, in: result) {
            result = result.removing(match.range)
        }
        return result.trimmingEdgePunctuation()
    }

    // MARK: - Events

    private static let eventPrefixPattern =
        "^(?:add|schedule|create|book|put|set up|setup|make|plan|new|enter|i have|i've got|there's|there is)\\s+" +
        "(?:a\\s+|an\\s+|the\\s+)?(?:new\\s+)?(?:calendar\\s+)?" +
        "(event|appointment|appt|meeting|call|entry|session|lunch|dinner|breakfast|workout|class)?" +
        "(?:\\s+(called|titled|named|for|about|with|that says)\\b|\\s*(:))?\\s*"

    func parseEvent(_ text: String) -> VoiceIntent {
        var working = text
        var noun: String?
        var connector = ""

        if let match = Pattern.first(Self.eventPrefixPattern, in: working) {
            noun = match.group(1)?.lowercased()
            connector = (match.group(2) ?? match.group(3) ?? "").lowercased()
            working = working.removing(match.range)
        }

        let isAllDaySpoken = Pattern.matches("\\ball[- ]day\\b|\\bwhole day\\b|\\bentire day\\b", in: working)
        if let match = Pattern.first("\\s*(?:for\\s+the\\s+)?(?:all[- ]day|the whole day|whole day|entire day)\\s*", in: working) {
            working = working.removing(match.range)
        }

        var recurrence: RecurrenceSpec?
        if let found = dateParser.extractRecurrence(from: working) {
            recurrence = found.spec
            working = working.removing(found.range)
        }

        var duration: TimeInterval?
        if let found = dateParser.extractDuration(from: working) {
            duration = found.seconds
            working = working.removing(found.range)
        }

        var parsedDate = dateParser.extract(from: working)
        if let found = parsedDate {
            working = working.removing(found.range)
            // "from 2 to 4": the detector sometimes returns only the first time, leaving "to 4 PM" behind.
            if found.end == nil, duration == nil, let second = dateParser.extract(from: working),
               second.hasExplicitTime, second.start > found.start,
               calendar.isDate(second.start, inSameDayAs: found.start) {
                let before = String(working[..<second.range.lowerBound])
                if Pattern.matches("\\b(?:to|until|till|through)\\s*$", in: before) {
                    parsedDate?.end = second.start
                    working = working.removing(second.range)
                    // Re-search on the updated string: the earlier range is stale after removal.
                    if let joiner = Pattern.first("\\b(?:to|until|till|through)\\s*$", in: working) {
                        working = working.removing(joiner.range)
                    }
                }
            }
        }

        var location: String?
        if let match = Pattern.first("\\s+(?:at|in)\\s+(?:the\\s+)?([a-z][a-z0-9' .&\\-]{1,40})$", in: working),
           let place = match.group(1),
           !Pattern.matches("\\d", in: place),
           !Self.timeWords.contains(place.lowercased().trimmingEdgePunctuation()),
           place.split(separator: " ").count <= 5 {
            location = place.trimmingEdgePunctuation().capitalizingFirstLetter()
            working = working.removing(match.range)
        }

        var title = Self.cleanTitle(working)
        if let noun {
            let nounTitle = noun.capitalizingFirstLetter()
            switch connector {
            case "with", "about":
                title = title.isEmpty ? nounTitle : "\(nounTitle) \(connector) \(title)"
            case "for", "called", "titled", "named", "that says", ":":
                title = title.isEmpty ? nounTitle : title
            default:
                if title.isEmpty {
                    title = nounTitle
                } else if ["meeting", "call", "lunch", "dinner", "breakfast", "workout", "class", "session"].contains(noun) {
                    title = "\(nounTitle) \(title)"
                }
            }
        }
        if title.isEmpty { title = "New event" }
        title = title.capitalizingFirstLetter()

        // Resolve the start date.
        var start: Date
        var hasExplicitTime: Bool
        var hadExplicitDate = true
        if let parsedDate {
            start = parsedDate.start
            hasExplicitTime = parsedDate.hasExplicitTime
        } else if case .weekly(let weekday?) = recurrence {
            start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: dateParser.nextWeekday(weekday, from: now, includeToday: true)) ?? now
            hasExplicitTime = false
            hadExplicitDate = false
        } else {
            start = Self.nextReasonableSlot(after: now, calendar: calendar)
            hasExplicitTime = true
            hadExplicitDate = false
        }
        if case .weekly(let weekday?) = recurrence, parsedDate != nil, calendar.component(.weekday, from: start) != weekday {
            let day = dateParser.nextWeekday(weekday, from: start, includeToday: true)
            let comps = calendar.dateComponents([.hour, .minute], from: start)
            start = calendar.date(bySettingHour: comps.hour ?? 9, minute: comps.minute ?? 0, second: 0, of: day) ?? day
        }

        let isAllDay = isAllDaySpoken || !hasExplicitTime
        var end: Date
        if isAllDay {
            start = calendar.startOfDay(for: start)
            end = start
        } else if let duration {
            end = start.addingTimeInterval(duration)
        } else if let explicitEnd = parsedDate?.end, explicitEnd > start {
            end = explicitEnd
        } else {
            end = start.addingTimeInterval(TimeInterval(defaultDurationMinutes * 60))
        }

        let draft = EventDraft(title: title,
                               start: start,
                               end: end,
                               isAllDay: isAllDay,
                               location: location,
                               recurrence: recurrence,
                               hadExplicitDate: hadExplicitDate)
        return .addEvent(draft)
    }

    /// Words that follow "at" without naming a place.
    private static let timeWords: Set<String> = [
        "noon", "midnight", "night", "tonight", "morning", "afternoon", "evening", "lunch", "lunchtime", "once", "all",
        "first", "least", "most", "some point", "the latest", "the earliest"
    ]

    /// Next round hour, skipping late night.
    static func nextReasonableSlot(after date: Date, calendar: Calendar) -> Date {
        var components = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        components.hour = (components.hour ?? 0) + 1
        components.minute = 0
        components.second = 0
        var slot = calendar.date(from: components) ?? date
        let hour = calendar.component(.hour, from: slot)
        if hour >= 21 || hour < 7 {
            let base = hour >= 21 ? calendar.date(byAdding: .day, value: 1, to: slot) ?? slot : slot
            slot = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: base) ?? slot
        }
        return slot
    }

    // MARK: - Reminders

    private static let reminderPrefixPattern =
        "^(?:remind me(?:\\s+to|\\s+that|\\s+about|\\s+of)?|set (?:up )?(?:a |an )?reminder(?:\\s+to|\\s+for|\\s+that|\\s+about)?|" +
        "(?:add|create|make) (?:a |an )?reminder(?:\\s+to|\\s+for|\\s+that|\\s+about)?|new reminder(?:\\s+to|\\s+for|:)?|" +
        "reminder(?:\\s+to|\\s+for|:)?|remember to|don'?t let me forget(?: to)?|don'?t forget to)\\s*"

    func parseReminder(_ text: String) -> VoiceIntent {
        var working = text
        if let match = Pattern.first(Self.reminderPrefixPattern, in: working) {
            working = working.removing(match.range)
        }
        var due: Date?
        if let found = dateParser.extract(from: working) {
            due = found.hasExplicitTime ? found.start : (calendar.date(bySettingHour: 9, minute: 0, second: 0, of: found.start) ?? found.start)
            working = working.removing(found.range)
        }
        var title = Self.cleanTitle(working)
        if title.isEmpty { title = "Reminder" }
        return .addReminder(title: title.capitalizingFirstLetter(), due: due)
    }

    // MARK: - Tasks

    private func parseTaskIfMatches(_ text: String) -> VoiceIntent? {
        let lower = text.lowercased()
        var working: String?

        if let match = Pattern.first("^(?:add|create|make|new|put)\\s+(?:a\\s+|an\\s+)?(?:new\\s+)?(?:task|to-?do(?:\\s+item)?|todo(?:\\s+item)?)(?:\\s+to|\\s+for|\\s+called|\\s+titled|:|,)?\\s*", in: text) {
            working = text.removing(match.range)
        } else if let match = Pattern.first("^(?:task|to-?do|todo)(?::|,|\\s+to)?\\s+", in: text) {
            working = text.removing(match.range)
        } else if let match = Pattern.first("^(?:add|put)\\s+(.+?)\\s+(?:to|on|in)\\s+(?:my\\s+)?(?:tasks?|task list|to-?do(?:\\s+list)?|todo(?:\\s+list)?)\\s*$", in: text) {
            working = match.group(1)
        } else if lower.hasAnyWordPrefix(["i need to", "i have to", "i've got to", "i gotta", "i should", "i must"]) {
            if let match = Pattern.first("^(?:i need to|i have to|i've got to|i gotta|i should|i must)\\s+", in: text) {
                let rest = text.removing(match.range)
                // "I need to schedule a meeting…" is still an event command.
                if rest.lowercased().hasAnyWordPrefix(["schedule", "add", "book", "set up", "remind", "note", "create"]) {
                    return parse(rest)
                }
                working = rest
            }
        } else if lower.hasAnyWordPrefix(["add to my tasks", "add to my to-do", "add to my to do", "add to my todo"]) {
            if let match = Pattern.first("^add to my (?:tasks?|to-?do(?: list)?|todo(?: list)?)(?::|,)?\\s*", in: text) {
                working = text.removing(match.range)
            }
        }

        guard var body = working else { return nil }
        var due: Date?
        if let found = dateParser.extract(from: body) {
            due = found.hasExplicitTime ? found.start : (calendar.date(bySettingHour: 9, minute: 0, second: 0, of: found.start) ?? found.start)
            body = body.removing(found.range)
        }
        var title = Self.cleanTitle(body)
        if title.isEmpty { title = "New task" }
        return .addTask(title: title.capitalizingFirstLetter(), due: due)
    }

    // MARK: - Notes

    private static let notePrefixPattern =
        "^(?:take (?:a |down )?notes?(?:\\s+that|\\s+of|:|,)?|take down a note(?:\\s+that|:|,)?|make (?:a )?note(?:\\s+that|\\s+of|:|,)?|" +
        "(?:create|add|save|write) (?:a )?(?:new )?note(?:\\s+that|\\s+saying|\\s+called|\\s+titled|:|,)?|new note(?::|,)?|" +
        "write (?:this |that )?down(?:\\s+that|:|,)?|jot (?:this |that )?down(?:\\s+that|:|,)?|note to self(?::|,)?|note that|note(?::|,)|note|remember that)\\s*"

    func parseNote(_ text: String) -> VoiceIntent {
        var working = text
        var title: String?
        if let match = Pattern.first(Self.notePrefixPattern, in: working) {
            let prefix = match.group(0)?.lowercased() ?? ""
            working = working.removing(match.range)
            if prefix.contains("called") || prefix.contains("titled") {
                if let split = Pattern.first("^(.+?)(?:\\s*[:,]\\s*|\\s+(?:saying|that says|with|and say|and write)\\s+)(.+)$", in: working),
                   let heading = split.group(1), let rest = split.group(2) {
                    title = Self.cleanTitle(heading).capitalizingFirstLetter()
                    working = rest
                } else {
                    title = Self.cleanTitle(working).capitalizingFirstLetter()
                    working = ""
                }
            }
        }
        if title == nil, let split = Pattern.first("^(?:called|titled|named)\\s+(.+?)(?:\\s*[:,]\\s*|\\s+(?:saying|that says|with)\\s+)(.+)$", in: working),
           let heading = split.group(1), let rest = split.group(2) {
            title = Self.cleanTitle(heading).capitalizingFirstLetter()
            working = rest
        }
        var body = working.trimmingEdgePunctuation().collapsingWhitespace()
        if let match = Pattern.first("^(?:that|to|about)\\s+", in: body) {
            body = body.removing(match.range)
        }
        body = body.capitalizingFirstLetter()
        if body.isEmpty, let title { body = title }
        if body.isEmpty { body = "Empty note" }
        return .addNote(title: title, body: body)
    }

    // MARK: - Delete

    private func parseDelete(_ text: String) -> VoiceIntent {
        var working = text
        if let match = Pattern.first("^(?:delete|cancel|remove|clear)\\s+(?:my\\s+|the\\s+|a\\s+|an\\s+)?(?:event|appointment|meeting|entry)?\\s*(?:called|titled|named|for|with)?\\s*", in: working) {
            working = working.removing(match.range)
        }
        var on: Date?
        if let found = dateParser.extract(from: working) {
            on = found.start
            working = working.removing(found.range)
        }
        let query = Self.cleanTitle(working)
        return .deleteEvent(titleQuery: query, on: on)
    }

    // MARK: - Queries

    private func parseQuery(_ text: String) -> VoiceIntent {
        let lower = text.lowercased()
        let parsed = dateParser.extract(from: text)

        if parsed == nil, lower.containsAny(["next", "coming up"]) {
            return .queryNext
        }
        if lower.containsAny(["this week", "the week", "my week"]) {
            let start = calendar.startOfDay(for: now)
            let end = calendar.dateInterval(of: .weekOfYear, for: now)?.end ?? calendar.date(byAdding: .day, value: 7, to: start)!
            return .querySchedule(from: now, to: end, label: "this week")
        }
        if lower.contains("next week"), let interval = calendar.dateInterval(of: .weekOfYear, for: now) {
            let end = calendar.date(byAdding: .day, value: 7, to: interval.end) ?? interval.end
            return .querySchedule(from: interval.end, to: end, label: "next week")
        }
        if lower.contains("weekend") {
            let saturday = dateParser.nextWeekday(7, from: now, includeToday: true)
            let end = calendar.date(byAdding: .day, value: 2, to: saturday) ?? saturday
            return .querySchedule(from: max(now, saturday), to: end, label: "this weekend")
        }

        let day = calendar.startOfDay(for: parsed?.start ?? now)
        let end = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        let label: String
        if calendar.isDateInToday(day) {
            label = "today"
        } else if calendar.isDateInTomorrow(day) {
            label = "tomorrow"
        } else {
            label = "on " + Formatters.weekdayDate.string(from: day)
        }
        return .querySchedule(from: calendar.isDateInToday(day) ? now : day, to: end, label: label)
    }

    // MARK: - Title cleanup

    static func cleanTitle(_ raw: String) -> String {
        var title = raw.trimmingEdgePunctuation().collapsingWhitespace()
        var changed = true
        while changed && !title.isEmpty {
            changed = false
            if let match = Pattern.first("^(?:to|that|about|for|on|at|of|in|is|and|a|an|the|,|:)\\s+", in: title) {
                title = title.removing(match.range)
                changed = true
            }
            if let match = Pattern.first("\\s+(?:on|at|for|from|by|in|this|next|around|about|to|and|the|a|an|until|till|starting|beginning|is)$", in: title) {
                title = title.removing(match.range)
                changed = true
            }
            let trimmed = title.trimmingEdgePunctuation()
            if trimmed != title {
                title = trimmed
                changed = true
            }
        }
        return title
    }
}

/// Finds the wake phrase inside a running transcript.
enum WakeWordDetector {
    /// Common mis-hearings of "Hey Calendar" that should still trigger the assistant.
    static func variants(for phrase: String) -> [String] {
        let lower = phrase.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        var set: [String] = [lower]
        if lower == "hey calendar" {
            set += ["hey calender", "hey, calendar", "hey, calender", "hey calendars", "hi calendar", "ok calendar", "okay calendar", "hey cal"]
        } else {
            set.append(lower.replacingOccurrences(of: " ", with: ", "))
        }
        return set
    }

    /// Range of the last wake-phrase occurrence in `transcript`, if any.
    static func range(of phrase: String, in transcript: String) -> Range<String.Index>? {
        var best: Range<String.Index>?
        for variant in variants(for: phrase) {
            var searchRange = transcript.startIndex..<transcript.endIndex
            while let found = transcript.range(of: variant, options: [.caseInsensitive, .diacriticInsensitive], range: searchRange) {
                if let current = best {
                    if found.lowerBound > current.lowerBound { best = found }
                } else {
                    best = found
                }
                searchRange = found.upperBound..<transcript.endIndex
            }
        }
        return best
    }

    /// Text spoken after the wake phrase, with leading punctuation removed.
    static func command(after phrase: String, in transcript: String) -> String? {
        guard let range = range(of: phrase, in: transcript) else { return nil }
        let rest = String(transcript[range.upperBound...])
        return rest.trimmingCharacters(in: CharacterSet(charactersIn: " ,.:;!?-")).collapsingWhitespace()
    }

    static func stripping(_ phrases: [String], from text: String) -> String {
        for phrase in phrases {
            if let command = command(after: phrase, in: text) {
                return command
            }
        }
        return text
    }
}
