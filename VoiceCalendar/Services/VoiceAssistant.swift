import AVFoundation
import EventKit
import Foundation
import Observation
import Speech
import SwiftData
import SwiftUI
import UIKit

/// What the assistant last did, shown in the overlay and the Today screen.
struct AssistantResponse: Identifiable, Equatable {
    enum Kind: Equatable {
        case success
        case info
        case error
    }

    enum CreatedItem: Equatable {
        case event(identifier: String)
        case reminder(identifier: String)
        case task(id: UUID)
        case note(id: UUID)
    }

    let id = UUID()
    let text: String
    let kind: Kind
    let heard: String
    let createdItem: CreatedItem?
    let timestamp: Date

    init(text: String, kind: Kind, heard: String, createdItem: CreatedItem? = nil) {
        self.text = text
        self.kind = kind
        self.heard = heard
        self.createdItem = createdItem
        self.timestamp = Date()
    }

    var symbolName: String {
        switch createdItem {
        case .event: return "calendar.badge.plus"
        case .reminder: return "bell.badge"
        case .task: return "checkmark.circle"
        case .note: return "note.text.badge.plus"
        case nil:
            switch kind {
            case .success: return "checkmark.circle.fill"
            case .info: return "info.circle"
            case .error: return "exclamationmark.triangle"
            }
        }
    }
}

/// Wraps an event identifier so it can drive a `.sheet(item:)`.
struct EventEditTarget: Identifiable, Equatable {
    let id: String
}

/// Orchestrates wake-word listening, command capture, parsing, execution and spoken feedback.
@Observable
@MainActor
final class VoiceAssistant {
    enum Phase: Equatable {
        /// Not listening at all.
        case off
        /// Microphone open, waiting to hear the wake phrase.
        case waitingForWakeWord
        /// Wake phrase heard (or mic tapped); capturing the command.
        case listening
        /// Command captured; parsing and executing.
        case thinking
        /// Reading the response out loud.
        case speaking
        /// Something prevented listening.
        case error(String)
    }

    private enum Mode {
        case wakeWord
        case command
    }

    private(set) var phase: Phase = .off
    /// Text captured after the wake phrase, updated live.
    private(set) var liveTranscript = ""
    private(set) var lastResponse: AssistantResponse?
    private(set) var history: [AssistantResponse] = []
    /// Drives the bottom overlay card.
    var isOverlayVisible = false
    /// Set when the user taps "Edit" on a just-created event.
    var eventToEdit: EventEditTarget?

    let speech = SpeechService()
    private let output = SpeechOutput()
    private let calendarService: CalendarService
    private let settings: AppSettings
    private let modelContainer: ModelContainer

    @ObservationIgnored private var mode: Mode = .wakeWord
    @ObservationIgnored private var silenceTask: Task<Void, Never>?
    @ObservationIgnored private var maxDurationTask: Task<Void, Never>?
    @ObservationIgnored private var restartTask: Task<Void, Never>?
    @ObservationIgnored private var dismissTask: Task<Void, Never>?
    @ObservationIgnored private var consecutiveFailures = 0
    @ObservationIgnored private var commandRetries = 0
    @ObservationIgnored private var lastSeenCommand = ""
    @ObservationIgnored private var isInForeground = true
    /// True while the user wants the assistant active (wake word on, or a manual command in flight).
    @ObservationIgnored private var wantsListening = false

    private var modelContext: ModelContext { modelContainer.mainContext }

    init(calendarService: CalendarService, settings: AppSettings, modelContainer: ModelContainer) {
        self.calendarService = calendarService
        self.settings = settings
        self.modelContainer = modelContainer

        speech.onResult = { [weak self] text, isFinal in
            self?.handleTranscript(text, isFinal: isFinal)
        }
        speech.onSessionEnded = { [weak self] error in
            self?.handleSessionEnded(error)
        }
    }

    var isListeningForWakeWord: Bool { phase == .waitingForWakeWord }
    var isCapturing: Bool { phase == .listening }
    var isBusy: Bool { phase == .thinking || phase == .speaking }
    var wakePhraseDisplay: String { settings.wakePhrase.trimmingCharacters(in: .whitespaces).isEmpty ? AppSettings.defaultWakePhrase : settings.wakePhrase }

    // MARK: - Public controls

    /// Starts wake-word listening if the user enabled it and permissions allow.
    func activateIfPossible() {
        guard settings.wakeWordEnabled else {
            if mode == .wakeWord { stopListening() }
            return
        }
        guard canListen else { return }
        startWakeWordLoop()
    }

    /// Called when the wake-word toggle or background setting changes.
    func settingsChanged() {
        if settings.wakeWordEnabled {
            if phase == .off || phase.isError { activateIfPossible() }
        } else if mode == .wakeWord {
            stopListening()
        }
    }

    /// The mic button: skip the wake phrase and capture a command right away.
    func startManualCommand() {
        output.stop()
        cancelTimers()
        if speech.isRunning { speech.stop() }
        restartTask?.cancel()

        guard canListen else {
            mode = .command
            respond(AssistantResponse(text: "Microphone and speech recognition access are needed for voice commands. You can allow them in Settings.", kind: .error, heard: ""))
            return
        }

        wantsListening = true
        mode = .command
        commandRetries = 0
        lastSeenCommand = ""
        liveTranscript = ""
        lastResponse = nil
        isOverlayVisible = true
        phase = .listening
        Haptics.impact(.medium)
        startRecognition()
        armMaxDurationTimer()
        armSilenceTimer(seconds: 6)
    }

    /// Tapping the mic while capturing finishes the command immediately.
    func finishCommandNow() {
        guard phase == .listening else { return }
        finalizeCommand()
    }

    /// Dismisses the overlay and goes back to wake-word listening (or off).
    func dismiss() {
        output.stop()
        cancelTimers()
        dismissTask?.cancel()
        isOverlayVisible = false
        liveTranscript = ""
        if phase == .listening || phase == .thinking || phase == .speaking {
            speech.stop()
            resumeIdleState()
        }
    }

    func stopListening() {
        wantsListening = false
        cancelTimers()
        restartTask?.cancel()
        output.stop()
        speech.stop()
        speech.deactivateAudioSession()
        mode = .wakeWord
        phase = .off
    }

    func handleScenePhase(_ scenePhase: ScenePhase) {
        switch scenePhase {
        case .active:
            isInForeground = true
            consecutiveFailures = 0
            if settings.wakeWordEnabled, phase == .off || phase.isError {
                activateIfPossible()
            }
        case .background:
            isInForeground = false
            if !settings.listenInBackground, mode == .wakeWord {
                speech.stop()
                restartTask?.cancel()
                phase = .off
            }
        default:
            break
        }
    }

    // MARK: - Listening loop

    private var canListen: Bool {
        SFSpeechAuthorizationHelper.isAuthorized && AVAudioApplicationHelper.isGranted
    }

    private func startWakeWordLoop() {
        wantsListening = true
        mode = .wakeWord
        lastSeenCommand = ""
        phase = .waitingForWakeWord
        startRecognition()
    }

    private func startRecognition() {
        do {
            try speech.start(preferOnDevice: settings.preferOnDeviceRecognition)
            consecutiveFailures = 0
        } catch {
            consecutiveFailures += 1
            phase = .error(error.localizedDescription)
            if mode == .command {
                isOverlayVisible = true
            }
        }
    }

    private func scheduleRestart(after delay: Duration = .milliseconds(400)) {
        restartTask?.cancel()
        restartTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled else { return }
            guard self.wantsListening, self.settings.wakeWordEnabled, self.canListen else { return }
            guard self.isInForeground || self.settings.listenInBackground else { return }
            if self.consecutiveFailures >= 5 {
                self.phase = .error("Listening stopped after repeated errors. Tap the microphone to try again.")
                return
            }
            self.startWakeWordLoop()
        }
    }

    private func handleTranscript(_ text: String, isFinal: Bool) {
        switch mode {
        case .wakeWord:
            guard let command = WakeWordDetector.command(after: settings.normalizedWakePhrase, in: text) else { return }
            // Wake phrase heard: switch to command capture within the same recognition session.
            mode = .command
            commandRetries = 0
            phase = .listening
            isOverlayVisible = true
            lastResponse = nil
            dismissTask?.cancel()
            Haptics.impact(.medium)
            liveTranscript = command
            lastSeenCommand = command
            armMaxDurationTimer()
            armSilenceTimer(seconds: command.isEmpty ? 6 : 1.6)

        case .command:
            let command = WakeWordDetector.command(after: settings.normalizedWakePhrase, in: text) ?? text
            let cleaned = command.collapsingWhitespace()
            if cleaned != lastSeenCommand {
                lastSeenCommand = cleaned
                liveTranscript = cleaned
                armSilenceTimer(seconds: cleaned.isEmpty ? 6 : 1.6)
            }
            if isFinal {
                finalizeCommand()
            }
        }
    }

    private func handleSessionEnded(_ error: Error?) {
        switch mode {
        case .command:
            if phase == .listening {
                if liveTranscript.isEmpty, error != nil {
                    // Nothing usable was heard (often a timeout); restart capture once, then give up.
                    commandRetries += 1
                    if commandRetries <= 1 {
                        startRecognition()
                        return
                    }
                    respond(AssistantResponse(text: "I didn't catch that. Try saying “add dentist tomorrow at 3 PM”.", kind: .info, heard: ""))
                } else {
                    finalizeCommand()
                }
            }
        case .wakeWord:
            if let error {
                let nsError = error as NSError
                // Code 1110 (no speech) and 216 (cancelled) are routine; anything else counts as a failure.
                if nsError.code != 1110 && nsError.code != 216 && nsError.code != 301 {
                    consecutiveFailures += 1
                }
            }
            if wantsListening, settings.wakeWordEnabled {
                scheduleRestart()
            } else {
                phase = .off
            }
        }
    }

    // MARK: - Timers

    private func armSilenceTimer(seconds: Double) {
        silenceTask?.cancel()
        silenceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, !Task.isCancelled, self.phase == .listening else { return }
            if self.liveTranscript.isEmpty {
                self.speech.stop()
                self.respond(AssistantResponse(text: "I'm listening, but didn't hear a command. Try “add dentist tomorrow at 3 PM”.", kind: .info, heard: ""))
            } else {
                self.finalizeCommand()
            }
        }
    }

    private func armMaxDurationTimer() {
        maxDurationTask?.cancel()
        maxDurationTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard let self, !Task.isCancelled, self.phase == .listening else { return }
            self.finalizeCommand()
        }
    }

    private func cancelTimers() {
        silenceTask?.cancel()
        maxDurationTask?.cancel()
        silenceTask = nil
        maxDurationTask = nil
    }

    // MARK: - Command execution

    private func finalizeCommand() {
        guard phase == .listening else { return }
        cancelTimers()
        let command = liveTranscript.trimmingEdgePunctuation().collapsingWhitespace()
        speech.stop()
        guard !command.isEmpty else {
            respond(AssistantResponse(text: "I didn't catch a command. Try “remind me to call Mom at 6 PM”.", kind: .info, heard: ""))
            return
        }
        phase = .thinking
        Haptics.impact(.light)
        Task { [weak self] in
            guard let self else { return }
            let response = await self.execute(command)
            self.respond(response)
        }
    }

    /// Parses and performs a command. Exposed so the UI can offer a typed command box too.
    func execute(_ command: String) async -> AssistantResponse {
        let parser = CommandParser(now: Date(),
                                   defaultDurationMinutes: settings.defaultEventDurationMinutes,
                                   wakePhrases: [settings.normalizedWakePhrase, AppSettings.defaultWakePhrase.lowercased()])
        let intent = parser.parse(command)

        switch intent {
        case .addEvent(let draft):
            return addEvent(draft, heard: command)
        case .addReminder(let title, let due):
            return addReminder(title: title, due: due, heard: command)
        case .addTask(let title, let due):
            return addTask(title: title, due: due, heard: command)
        case .addNote(let title, let body):
            return addNote(title: title, body: body, heard: command)
        case .deleteEvent(let query, let day):
            return deleteEvent(matching: query, on: day, heard: command)
        case .querySchedule(let from, let to, let label):
            return describeSchedule(from: from, to: to, label: label, heard: command)
        case .queryNext:
            return describeNextEvent(heard: command)
        case .help:
            return AssistantResponse(text: "Try: “add dentist tomorrow at 3 PM”, “remind me to call Mom at 6”, “add buy milk to my tasks”, “take a note: ideas for Friday”, or “what's on my schedule tomorrow?”", kind: .info, heard: command)
        case .unknown(let text):
            return AssistantResponse(text: "Sorry, I didn't understand “\(text)”. Try starting with add, remind me, take a note, or add task.", kind: .error, heard: command)
        }
    }

    private func addEvent(_ draft: EventDraft, heard: String) -> AssistantResponse {
        guard calendarService.hasEventAccess else {
            return AssistantResponse(text: CalendarError.noCalendarAccess.localizedDescription, kind: .error, heard: heard)
        }
        do {
            let lead = settings.useSystemAlerts ? settings.eventAlertLeadMinutes : nil
            let event = try calendarService.createEvent(from: draft, alarmLeadMinutes: lead)
            if !settings.useSystemAlerts {
                NotificationService.shared.scheduleEventNotification(for: event, leadMinutes: settings.eventAlertLeadMinutes)
            }
            refreshDailyBriefing()

            var text = "Added “\(draft.title)” \(Formatters.spoken(draft.start, allDay: draft.isAllDay))"
            if let recurrence = draft.recurrence { text += ", \(recurrence.spokenDescription)" }
            if let location = draft.location { text += " at \(location)" }
            text += "."
            if !draft.hadExplicitDate { text += " I didn't hear a time, so tap Edit to change it." }
            return AssistantResponse(text: text, kind: .success, heard: heard, createdItem: .event(identifier: event.eventIdentifier))
        } catch {
            return AssistantResponse(text: error.localizedDescription, kind: .error, heard: heard)
        }
    }

    private func addReminder(title: String, due: Date?, heard: String) -> AssistantResponse {
        guard calendarService.hasReminderAccess else {
            // Fall back to a local task so the request is never lost.
            let fallback = addTask(title: title, due: due, heard: heard)
            return AssistantResponse(text: "Reminders access is off, so I saved it as a task instead. " + fallback.text, kind: .info, heard: heard, createdItem: fallback.createdItem)
        }
        do {
            let reminder = try calendarService.createReminder(title: title, due: due, addAlarm: settings.useSystemAlerts)
            if let due, !settings.useSystemAlerts {
                NotificationService.shared.scheduleReminderNotification(for: reminder, at: due)
            }
            let when = due.map { " " + Formatters.spoken($0) } ?? ", with no time set"
            return AssistantResponse(text: "Okay, I'll remind you to \(lowercasedFirst(title))\(when).", kind: .success, heard: heard, createdItem: .reminder(identifier: reminder.calendarItemIdentifier))
        } catch {
            return AssistantResponse(text: error.localizedDescription, kind: .error, heard: heard)
        }
    }

    private func addTask(title: String, due: Date?, heard: String) -> AssistantResponse {
        let task = TaskItem(title: title, dueDate: due, createdByVoice: true)
        modelContext.insert(task)
        do {
            try modelContext.save()
        } catch {
            return AssistantResponse(text: "I couldn't save that task: \(error.localizedDescription)", kind: .error, heard: heard)
        }
        NotificationService.shared.scheduleTaskNotification(for: task)
        refreshDailyBriefing()
        let when = due.map { ", due " + Formatters.spoken($0) } ?? ""
        return AssistantResponse(text: "Added “\(title)” to your tasks\(when).", kind: .success, heard: heard, createdItem: .task(id: task.id))
    }

    private func addNote(title: String?, body: String, heard: String) -> AssistantResponse {
        let note = Note(title: title ?? "", body: body, createdByVoice: true)
        modelContext.insert(note)
        do {
            try modelContext.save()
        } catch {
            return AssistantResponse(text: "I couldn't save that note: \(error.localizedDescription)", kind: .error, heard: heard)
        }
        return AssistantResponse(text: "Saved a note: “\(note.displayTitle)”.", kind: .success, heard: heard, createdItem: .note(id: note.id))
    }

    private func deleteEvent(matching query: String, on day: Date?, heard: String) -> AssistantResponse {
        guard calendarService.hasEventAccess else {
            return AssistantResponse(text: CalendarError.noCalendarAccess.localizedDescription, kind: .error, heard: heard)
        }
        guard let event = calendarService.findEvent(matching: query, on: day) else {
            return AssistantResponse(text: CalendarError.eventNotFound(query.isEmpty ? "that" : query).localizedDescription, kind: .error, heard: heard)
        }
        let title = event.title ?? "the event"
        let when = Formatters.spoken(event.startDate, allDay: event.isAllDay)
        do {
            NotificationService.shared.cancelEventNotification(for: event)
            try calendarService.delete(event)
            refreshDailyBriefing()
            return AssistantResponse(text: "Deleted “\(title)” \(when).", kind: .success, heard: heard)
        } catch {
            return AssistantResponse(text: error.localizedDescription, kind: .error, heard: heard)
        }
    }

    private func describeSchedule(from: Date, to: Date, label: String, heard: String) -> AssistantResponse {
        guard calendarService.hasEventAccess else {
            return AssistantResponse(text: CalendarError.noCalendarAccess.localizedDescription, kind: .error, heard: heard)
        }
        let events = calendarService.events(from: from, to: to)
        if events.isEmpty {
            return AssistantResponse(text: "You have nothing on your calendar \(label).", kind: .info, heard: heard)
        }
        let multiDay = to.timeIntervalSince(from) > 36 * 3600
        let descriptions = events.prefix(5).map { event -> String in
            let title = event.title ?? "Untitled"
            if event.isAllDay {
                return multiDay ? "\(title) \(Formatters.spoken(event.startDate, allDay: true))" : "\(title) all day"
            }
            return multiDay ? "\(title) \(Formatters.spoken(event.startDate))" : "\(title) at \(Formatters.time.string(from: event.startDate))"
        }
        var text = "You have \(events.count) event\(events.count == 1 ? "" : "s") \(label): " + descriptions.joined(separator: ", ")
        if events.count > 5 { text += ", and \(events.count - 5) more" }
        text += "."
        return AssistantResponse(text: text, kind: .info, heard: heard)
    }

    private func describeNextEvent(heard: String) -> AssistantResponse {
        guard calendarService.hasEventAccess else {
            return AssistantResponse(text: CalendarError.noCalendarAccess.localizedDescription, kind: .error, heard: heard)
        }
        guard let event = calendarService.nextEvent() else {
            return AssistantResponse(text: "You have nothing coming up in the next 30 days.", kind: .info, heard: heard)
        }
        var text = "Next up is “\(event.title ?? "Untitled")” \(Formatters.spoken(event.startDate, allDay: event.isAllDay))"
        if let location = event.location, !location.isEmpty { text += " at \(location)" }
        text += "."
        return AssistantResponse(text: text, kind: .info, heard: heard)
    }

    // MARK: - Responding

    private func respond(_ response: AssistantResponse) {
        cancelTimers()
        lastResponse = response
        history.insert(response, at: 0)
        if history.count > 20 { history.removeLast(history.count - 20) }
        isOverlayVisible = true
        liveTranscript = response.heard

        switch response.kind {
        case .success: Haptics.notify(.success)
        case .info: Haptics.notify(.warning)
        case .error: Haptics.notify(.error)
        }

        if settings.spokenFeedback {
            phase = .speaking
            output.speak(response.text) { [weak self] in
                self?.afterResponse()
            }
        } else {
            afterResponse()
        }
    }

    private func afterResponse() {
        resumeIdleState()
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard let self, !Task.isCancelled else { return }
            if self.phase != .listening && self.phase != .thinking && self.phase != .speaking {
                self.isOverlayVisible = false
            }
        }
    }

    private func resumeIdleState() {
        mode = .wakeWord
        lastSeenCommand = ""
        if settings.wakeWordEnabled, canListen, isInForeground || settings.listenInBackground {
            wantsListening = true
            phase = .waitingForWakeWord
            scheduleRestart(after: .milliseconds(250))
        } else {
            wantsListening = false
            phase = .off
            speech.deactivateAudioSession()
        }
    }

    private func refreshDailyBriefing() {
        let calendar = Calendar.current
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())),
              let dayAfter = calendar.date(byAdding: .day, value: 1, to: tomorrow) else { return }
        let events = calendarService.events(from: tomorrow, to: dayAfter)
        let descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate { !$0.isCompleted })
        let tasks = ((try? modelContext.fetch(descriptor)) ?? []).filter { task in
            guard let due = task.dueDate else { return false }
            return due >= tomorrow && due < dayAfter
        }
        NotificationService.shared.scheduleDailyBriefing(enabled: settings.dailyBriefingEnabled,
                                                         hour: settings.dailyBriefingHour,
                                                         eventsTomorrow: events,
                                                         tasksTomorrow: tasks)
    }

    /// Public hook so views can refresh the briefing after manual edits.
    func agendaDidChange() {
        refreshDailyBriefing()
    }

    private func lowercasedFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        // Keep proper nouns / acronyms intact: only lowercase if the second character is lowercase.
        if text.count > 1, text[text.index(after: text.startIndex)].isUppercase { return text }
        return first.lowercased() + text.dropFirst()
    }
}

extension VoiceAssistant.Phase {
    var isError: Bool {
        if case .error = self { return true }
        return false
    }
}

// MARK: - Small helpers

enum SFSpeechAuthorizationHelper {
    static var isAuthorized: Bool { SFSpeechRecognizer.authorizationStatus() == .authorized }
}

enum AVAudioApplicationHelper {
    static var isGranted: Bool { AVAudioApplication.shared.recordPermission == .granted }
}

enum Haptics {
    @MainActor
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    @MainActor
    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
}
