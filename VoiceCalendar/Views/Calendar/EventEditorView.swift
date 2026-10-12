import EventKit
import SwiftUI

@MainActor
struct EventEditorView: View {
    enum Mode {
        case create(defaultStart: Date)
        case edit(EKEvent)
    }

    let mode: Mode

    @Environment(\.dismiss) private var dismiss
    @Environment(CalendarService.self) private var calendarService
    @Environment(AppSettings.self) private var settings
    @Environment(VoiceAssistant.self) private var assistant

    @State private var title = ""
    @State private var location = ""
    @State private var notes = ""
    @State private var isAllDay = false
    @State private var start: Date
    @State private var end: Date
    /// Minutes before the event; -1 means no alert.
    @State private var alertLead: Int
    @State private var errorMessage: String?
    @State private var confirmDelete = false

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .create(let defaultStart):
            _start = State(initialValue: defaultStart)
            _end = State(initialValue: defaultStart.addingTimeInterval(TimeInterval(AppSettings.shared.defaultEventDurationMinutes * 60)))
            _alertLead = State(initialValue: AppSettings.shared.useSystemAlerts ? AppSettings.shared.eventAlertLeadMinutes : -1)
        case .edit(let event):
            _title = State(initialValue: event.title ?? "")
            _location = State(initialValue: event.location ?? "")
            _notes = State(initialValue: event.notes ?? "")
            _isAllDay = State(initialValue: event.isAllDay)
            _start = State(initialValue: event.startDate)
            _end = State(initialValue: event.endDate)
            let lead = event.alarms?.first.map { Int(-$0.relativeOffset / 60) } ?? -1
            _alertLead = State(initialValue: lead)
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var components: DatePickerComponents {
        isAllDay ? [.date] : [.date, .hourAndMinute]
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                        .font(.body.weight(.medium))
                    TextField("Location", text: $location)
                }
                Section {
                    Toggle("All-day", isOn: $isAllDay)
                    DatePicker("Starts", selection: $start, displayedComponents: components)
                    DatePicker("Ends", selection: $end, in: start..., displayedComponents: components)
                }
                Section {
                    Picker("Alert", selection: $alertLead) {
                        Text("None").tag(-1)
                        Text("At time of event").tag(0)
                        Text("5 minutes before").tag(5)
                        Text("10 minutes before").tag(10)
                        Text("15 minutes before").tag(15)
                        Text("30 minutes before").tag(30)
                        Text("1 hour before").tag(60)
                        Text("1 day before").tag(1440)
                    }
                } footer: {
                    Text("Alerts are stored on the event, so the iPhone Calendar app delivers them too.")
                }
                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 90)
                }
                if isEditing {
                    Section {
                        Button("Delete Event", role: .destructive) { confirmDelete = true }
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Event" : "New Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") { save() }
                        .fontWeight(.semibold)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onChange(of: start) { oldValue, newValue in
                // Keep the duration stable when the start moves.
                end = end.addingTimeInterval(newValue.timeIntervalSince(oldValue))
            }
            .alert("Couldn't save", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .confirmationDialog("Delete this event?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete Event", role: .destructive) { delete() }
            }
        }
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        let trimmedLocation = location.trimmingCharacters(in: .whitespaces)
        let draft = EventDraft(title: trimmedTitle,
                               start: start,
                               end: max(end, start),
                               isAllDay: isAllDay,
                               location: trimmedLocation.isEmpty ? nil : trimmedLocation)
        do {
            switch mode {
            case .create:
                let event = try calendarService.createEvent(from: draft,
                                                            alarmLeadMinutes: alertLead >= 0 ? alertLead : nil,
                                                            notes: notes)
                if !settings.useSystemAlerts, alertLead >= 0 {
                    NotificationService.shared.scheduleEventNotification(for: event, leadMinutes: alertLead)
                }
            case .edit(let event):
                calendarService.apply(draft, to: event)
                event.notes = notes.isEmpty ? nil : notes
                event.alarms = alertLead >= 0 ? [EKAlarm(relativeOffset: TimeInterval(-alertLead * 60))] : nil
                try calendarService.save(event)
                NotificationService.shared.cancelEventNotification(for: event)
                if !settings.useSystemAlerts, alertLead >= 0 {
                    NotificationService.shared.scheduleEventNotification(for: event, leadMinutes: alertLead)
                }
            }
            assistant.agendaDidChange()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete() {
        guard case .edit(let event) = mode else { return }
        do {
            NotificationService.shared.cancelEventNotification(for: event)
            try calendarService.delete(event, span: event.hasRecurrenceRules ? .futureEvents : .thisEvent)
            assistant.agendaDidChange()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
