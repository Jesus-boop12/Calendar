import XCTest
@testable import VoiceCalendar

/// Exercises the natural-language layer. Dates that depend on "today"/"tomorrow" are checked
/// relative to the real clock because `NSDataDetector` always resolves them against the current date.
final class CommandParserTests: XCTestCase {
    private let calendar = Calendar.current
    private var parser: CommandParser { CommandParser(now: Date(), defaultDurationMinutes: 60) }

    private func event(_ text: String, file: StaticString = #filePath, line: UInt = #line) -> EventDraft? {
        if case .addEvent(let draft) = parser.parse(text) { return draft }
        XCTFail("Expected an event for “\(text)”, got \(parser.parse(text))", file: file, line: line)
        return nil
    }

    // MARK: - Events

    func testAddEventWithWakePhraseAndTime() throws {
        let draft = try XCTUnwrap(event("Hey Calendar, add dentist tomorrow at 3 PM"))
        XCTAssertEqual(draft.title, "Dentist")
        XCTAssertTrue(calendar.isDateInTomorrow(draft.start))
        XCTAssertEqual(calendar.component(.hour, from: draft.start), 15)
        XCTAssertFalse(draft.isAllDay)
        XCTAssertEqual(draft.end.timeIntervalSince(draft.start), 3600, accuracy: 1)
        XCTAssertTrue(draft.hadExplicitDate)
    }

    func testMeetingWithPersonAndDuration() throws {
        let draft = try XCTUnwrap(event("schedule a meeting with John on Friday at 10 am for 2 hours"))
        XCTAssertEqual(draft.title, "Meeting with John")
        XCTAssertEqual(calendar.component(.weekday, from: draft.start), 6)
        XCTAssertEqual(calendar.component(.hour, from: draft.start), 10)
        XCTAssertEqual(draft.end.timeIntervalSince(draft.start), 7200, accuracy: 1)
        XCTAssertGreaterThan(draft.start, Date())
    }

    func testLocationIsExtracted() throws {
        let draft = try XCTUnwrap(event("add lunch with Sam at Chipotle tomorrow at noon"))
        XCTAssertEqual(draft.title, "Lunch with Sam")
        XCTAssertEqual(draft.location, "Chipotle")
        XCTAssertEqual(calendar.component(.hour, from: draft.start), 12)
        XCTAssertTrue(calendar.isDateInTomorrow(draft.start))
    }

    func testRecurringWeekdayEvent() throws {
        let draft = try XCTUnwrap(event("add team standup every weekday at 9 am"))
        XCTAssertEqual(draft.title, "Team standup")
        XCTAssertEqual(draft.recurrence, .weekdays)
        XCTAssertEqual(calendar.component(.hour, from: draft.start), 9)
        XCTAssertFalse(draft.isAllDay)
    }

    func testDateWithoutTimeBecomesAllDay() throws {
        let draft = try XCTUnwrap(event("add vacation on October 20"))
        XCTAssertEqual(draft.title, "Vacation")
        XCTAssertTrue(draft.isAllDay)
        XCTAssertEqual(calendar.component(.month, from: draft.start), 10)
        XCTAssertEqual(calendar.component(.day, from: draft.start), 20)
    }

    func testEventWithoutDateGetsFallbackSlot() throws {
        let draft = try XCTUnwrap(event("add haircut appointment"))
        XCTAssertEqual(draft.title, "Haircut appointment")
        XCTAssertFalse(draft.hadExplicitDate)
        XCTAssertGreaterThan(draft.start, Date())
    }

    func testBareHourIsTreatedAsAfternoon() throws {
        let draft = try XCTUnwrap(event("add dentist tomorrow at 3"))
        XCTAssertEqual(calendar.component(.hour, from: draft.start), 15)
    }

    func testCalendarSuffixIsIgnored() throws {
        let draft = try XCTUnwrap(event("put yoga class tomorrow at 7 am on my calendar please"))
        XCTAssertEqual(draft.title, "Yoga class")
        XCTAssertEqual(calendar.component(.hour, from: draft.start), 7)
    }

    // MARK: - Reminders

    func testReminderWithTime() throws {
        guard case .addReminder(let title, let due) = parser.parse("remind me to call Mom at 6 PM") else {
            return XCTFail("Expected a reminder")
        }
        XCTAssertEqual(title, "Call Mom")
        let dueDate = try XCTUnwrap(due)
        XCTAssertEqual(calendar.component(.hour, from: dueDate), 18)
        XCTAssertGreaterThan(dueDate, Date())
    }

    func testRelativeReminder() throws {
        guard case .addReminder(let title, let due) = parser.parse("remind me in 30 minutes to check the oven") else {
            return XCTFail("Expected a reminder")
        }
        XCTAssertEqual(title, "Check the oven")
        let dueDate = try XCTUnwrap(due)
        XCTAssertEqual(dueDate.timeIntervalSinceNow, 30 * 60, accuracy: 90)
    }

    func testReminderWithoutTime() {
        guard case .addReminder(let title, let due) = parser.parse("set a reminder to water the plants") else {
            return XCTFail("Expected a reminder")
        }
        XCTAssertEqual(title, "Water the plants")
        XCTAssertNil(due)
    }

    // MARK: - Tasks

    func testAddToTasksForm() {
        guard case .addTask(let title, let due) = parser.parse("add buy milk to my tasks") else {
            return XCTFail("Expected a task")
        }
        XCTAssertEqual(title, "Buy milk")
        XCTAssertNil(due)
    }

    func testAddTaskWithDueDate() throws {
        guard case .addTask(let title, let due) = parser.parse("add a task finish the report by tomorrow at 5 pm") else {
            return XCTFail("Expected a task")
        }
        XCTAssertEqual(title, "Finish the report")
        let dueDate = try XCTUnwrap(due)
        XCTAssertTrue(calendar.isDateInTomorrow(dueDate))
        XCTAssertEqual(calendar.component(.hour, from: dueDate), 17)
    }

    func testNeedToSchedulingPhraseStaysAnEvent() throws {
        let draft = try XCTUnwrap(event("I need to schedule a call with the bank tomorrow at 11 am"))
        XCTAssertEqual(draft.title, "Call with the bank")
        XCTAssertEqual(calendar.component(.hour, from: draft.start), 11)
    }

    // MARK: - Notes

    func testNoteWithColon() {
        guard case .addNote(let title, let body) = parser.parse("take a note: ideas for the pitch") else {
            return XCTFail("Expected a note")
        }
        XCTAssertNil(title)
        XCTAssertEqual(body, "Ideas for the pitch")
    }

    func testNoteWithTitle() {
        guard case .addNote(let title, let body) = parser.parse("create a note called groceries: milk, eggs and bread") else {
            return XCTFail("Expected a note")
        }
        XCTAssertEqual(title, "Groceries")
        XCTAssertEqual(body, "Milk, eggs and bread")
    }

    // MARK: - Queries and misc

    func testScheduleQueryTomorrow() {
        guard case .querySchedule(let from, let to, let label) = parser.parse("what's on my schedule tomorrow") else {
            return XCTFail("Expected a schedule query")
        }
        XCTAssertEqual(label, "tomorrow")
        XCTAssertTrue(calendar.isDateInTomorrow(from))
        XCTAssertEqual(to.timeIntervalSince(from), 86_400, accuracy: 3_700)
    }

    func testCurlyApostropheQuery() {
        guard case .querySchedule(_, _, let label) = parser.parse("What\u{2019}s on my calendar today?") else {
            return XCTFail("Expected a schedule query")
        }
        XCTAssertEqual(label, "today")
    }

    func testNextQuery() {
        XCTAssertEqual(parser.parse("what's next"), .queryNext)
    }

    func testDeleteEvent() {
        guard case .deleteEvent(let query, let day) = parser.parse("delete dentist tomorrow") else {
            return XCTFail("Expected a delete")
        }
        XCTAssertEqual(query, "dentist")
        XCTAssertNotNil(day)
    }

    func testHelp() {
        XCTAssertEqual(parser.parse("what can you do"), .help)
    }

    func testUnknown() {
        if case .unknown = parser.parse("purple monkey dishwasher") {
            return
        }
        XCTFail("Expected unknown intent")
    }

    // MARK: - Wake word

    func testWakeWordDetection() {
        XCTAssertEqual(WakeWordDetector.command(after: "hey calendar", in: "Hey Calendar, add milk to my tasks"), "add milk to my tasks")
        XCTAssertEqual(WakeWordDetector.command(after: "hey calendar", in: "um hey calender add milk"), "add milk")
        XCTAssertEqual(WakeWordDetector.command(after: "hey calendar", in: "Hey Calendar"), "")
        XCTAssertNil(WakeWordDetector.command(after: "hey calendar", in: "add milk to my tasks"))
    }

    func testWakeWordUsesLastOccurrence() {
        let transcript = "Hey Calendar never mind. Hey Calendar add dentist tomorrow"
        XCTAssertEqual(WakeWordDetector.command(after: "hey calendar", in: transcript), "add dentist tomorrow")
    }

    // MARK: - Date parser

    func testDurationParsing() {
        let dateParser = DateParser()
        XCTAssertEqual(dateParser.extractDuration(from: "lunch for an hour and a half")?.seconds, 90 * 60)
        XCTAssertEqual(dateParser.extractDuration(from: "sync for 45 minutes")?.seconds, 45 * 60)
        XCTAssertEqual(dateParser.extractDuration(from: "review for two hours")?.seconds, 7200)
        XCTAssertNil(dateParser.extractDuration(from: "dinner for two"))
    }

    func testRecurrenceParsing() {
        let dateParser = DateParser()
        XCTAssertEqual(dateParser.extractRecurrence(from: "gym every monday")?.spec, .weekly(weekday: 2))
        XCTAssertEqual(dateParser.extractRecurrence(from: "standup daily")?.spec, .daily)
        XCTAssertEqual(dateParser.extractRecurrence(from: "rent every month")?.spec, .monthly)
    }
}
