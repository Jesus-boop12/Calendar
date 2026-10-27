import EventKit
import SwiftData
import SwiftUI

struct TasksView: View {
    private enum Segment: String, CaseIterable {
        case tasks = "Tasks"
        case reminders = "Reminders"
    }

    @State private var segment: Segment = .tasks

    var body: some View {
        NavigationStack {
            Group {
                switch segment {
                case .tasks:
                    TaskListView()
                case .reminders:
                    RemindersListView()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Section", selection: $segment) {
                        ForEach(Segment.allCases, id: \.self) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
            }
        }
    }
}

// MARK: - Local tasks

private struct TaskSection: Identifiable {
    let id: String
    let title: String
    let tasks: [TaskItem]
}

@MainActor
struct TaskListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(VoiceAssistant.self) private var assistant
    @Query(sort: \TaskItem.createdAt, order: .reverse) private var tasks: [TaskItem]

    @State private var editing: TaskItem?
    @State private var creating = false
    @State private var showCompleted = false

    private let calendar = Calendar.current

    var body: some View {
        List {
            ForEach(sections) { section in
                Section(section.title) {
                    ForEach(section.tasks) { task in
                        TaskRow(task: task) { toggle(task) }
                            .contentShape(Rectangle())
                            .onTapGesture { editing = task }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { delete(task) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }
            if !completed.isEmpty {
                Section {
                    DisclosureGroup(isExpanded: $showCompleted) {
                        ForEach(completed) { task in
                            TaskRow(task: task) { toggle(task) }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) { delete(task) } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                        Button("Clear completed", role: .destructive) { clearCompleted() }
                    } label: {
                        Text("Completed (\(completed.count))")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .safeAreaPadding(.bottom, 90)
        .overlay {
            if tasks.isEmpty {
                ContentUnavailableView {
                    Label("No tasks yet", systemImage: "checklist")
                } description: {
                    Text("Tap + or say “\(assistant.wakePhraseDisplay), add buy milk to my tasks”.")
                } actions: {
                    Button("Add a task") { creating = true }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { creating = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("New task")
            }
        }
        .sheet(isPresented: $creating) { TaskEditorView(task: nil) }
        .sheet(item: $editing) { task in TaskEditorView(task: task) }
    }

    private var open: [TaskItem] { tasks.filter { !$0.isCompleted } }
    private var completed: [TaskItem] {
        tasks.filter(\.isCompleted).sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    private var sections: [TaskSection] {
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? now
        let byDue: (TaskItem, TaskItem) -> Bool = { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }

        let overdue = open.filter { ($0.dueDate ?? .distantFuture) < now && ($0.dueDate ?? .distantFuture) < startOfToday }.sorted(by: byDue)
        let today = open.filter { task in
            guard let due = task.dueDate else { return false }
            return due >= startOfToday && due < endOfToday
        }.sorted(by: byDue)
        let upcoming = open.filter { ($0.dueDate ?? .distantPast) >= endOfToday }.sorted(by: byDue)
        let someday = open.filter { $0.dueDate == nil }.sorted { $0.priorityRaw > $1.priorityRaw }

        var result: [TaskSection] = []
        if !overdue.isEmpty { result.append(TaskSection(id: "overdue", title: "Overdue", tasks: overdue)) }
        if !today.isEmpty { result.append(TaskSection(id: "today", title: "Today", tasks: today)) }
        if !upcoming.isEmpty { result.append(TaskSection(id: "upcoming", title: "Upcoming", tasks: upcoming)) }
        if !someday.isEmpty { result.append(TaskSection(id: "someday", title: "Anytime", tasks: someday)) }
        return result
    }

    private func toggle(_ task: TaskItem) {
        withAnimation {
            task.markCompleted(!task.isCompleted)
        }
        NotificationService.shared.scheduleTaskNotification(for: task)
        try? modelContext.save()
        assistant.agendaDidChange()
    }

    private func delete(_ task: TaskItem) {
        NotificationService.shared.cancelTaskNotification(for: task)
        withAnimation {
            modelContext.delete(task)
        }
        try? modelContext.save()
        assistant.agendaDidChange()
    }

    private func clearCompleted() {
        withAnimation {
            for task in completed {
                NotificationService.shared.cancelTaskNotification(for: task)
                modelContext.delete(task)
            }
        }
        try? modelContext.save()
    }
}

struct TaskRow: View {
    let task: TaskItem
    let toggle: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Button(action: toggle) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(task.isCompleted ? Color.appAccent : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isCompleted ? "Mark incomplete" : "Mark complete")

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .strikethrough(task.isCompleted)
                    .foregroundStyle(task.isCompleted ? .secondary : .primary)
                HStack(spacing: 10) {
                    if let due = task.dueDate {
                        Label(Formatters.compact(due), systemImage: "clock")
                            .foregroundStyle(task.isOverdue ? Color.red : Color.secondary)
                    }
                    if let symbol = task.priority.symbolName {
                        Image(systemName: symbol)
                            .foregroundStyle(.orange)
                    }
                    if task.createdByVoice {
                        Image(systemName: "waveform")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
            }
            Spacer(minLength: 0)
        }
    }
}

@MainActor
struct TaskEditorView: View {
    let task: TaskItem?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(VoiceAssistant.self) private var assistant

    @State private var title: String
    @State private var details: String
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var priority: TaskPriority

    init(task: TaskItem?) {
        self.task = task
        _title = State(initialValue: task?.title ?? "")
        _details = State(initialValue: task?.details ?? "")
        _hasDueDate = State(initialValue: task?.dueDate != nil)
        _dueDate = State(initialValue: task?.dueDate ?? CommandParser.nextReasonableSlot(after: Date(), calendar: .current))
        _priority = State(initialValue: task?.priority ?? .none)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What needs doing?", text: $title)
                        .font(.body.weight(.medium))
                    TextField("Details", text: $details, axis: .vertical)
                        .lineLimit(2...5)
                }
                Section {
                    Toggle("Due date", isOn: $hasDueDate.animation())
                    if hasDueDate {
                        DatePicker("Due", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                    }
                } footer: {
                    if hasDueDate {
                        Text("You'll get a notification when the task is due.")
                    }
                }
                Section {
                    Picker("Priority", selection: $priority) {
                        ForEach(TaskPriority.allCases) { level in
                            Text(level.label).tag(level)
                        }
                    }
                }
                if let task {
                    Section {
                        Button("Delete Task", role: .destructive) {
                            NotificationService.shared.cancelTaskNotification(for: task)
                            modelContext.delete(task)
                            try? modelContext.save()
                            dismiss()
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle(task == nil ? "New Task" : "Edit Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(task == nil ? "Add" : "Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        let target: TaskItem
        if let task {
            task.title = trimmed
            task.details = details
            task.dueDate = hasDueDate ? dueDate : nil
            task.priority = priority
            target = task
        } else {
            target = TaskItem(title: trimmed, details: details, dueDate: hasDueDate ? dueDate : nil, priority: priority)
            modelContext.insert(target)
        }
        try? modelContext.save()
        NotificationService.shared.scheduleTaskNotification(for: target)
        assistant.agendaDidChange()
        dismiss()
    }
}

// MARK: - Reminders (EventKit)

@MainActor
struct RemindersListView: View {
    @Environment(CalendarService.self) private var calendarService
    @Environment(\.openURL) private var openURL

    @State private var reminders: [EKReminder] = []
    @State private var creating = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            ForEach(reminders, id: \.calendarItemIdentifier) { reminder in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Button {
                        complete(reminder)
                    } label: {
                        Image(systemName: "circle")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Complete reminder")

                    VStack(alignment: .leading, spacing: 3) {
                        Text(reminder.title ?? "Untitled")
                        if let due = calendarService.dueDate(of: reminder) {
                            Label(Formatters.compact(due), systemImage: "clock")
                                .font(.caption)
                                .foregroundStyle(due < Date() ? Color.red : Color.secondary)
                        }
                        if let notes = reminder.notes, !notes.isEmpty {
                            Text(notes)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { delete(reminder) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .safeAreaPadding(.bottom, 90)
        .overlay {
            if !calendarService.hasReminderAccess {
                ContentUnavailableView {
                    Label("Reminders access needed", systemImage: "bell.slash")
                } description: {
                    Text("Allow access so reminders you create here show up in the Reminders app.")
                } actions: {
                    Button("Allow access") {
                        Task { await calendarService.requestReminderAccess() }
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
            } else if reminders.isEmpty {
                ContentUnavailableView {
                    Label("No reminders", systemImage: "bell")
                } description: {
                    Text("Say “remind me to call Mom at 6 PM” or tap + to add one.")
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { creating = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("New reminder")
                    .disabled(!calendarService.hasReminderAccess)
            }
        }
        .sheet(isPresented: $creating, onDismiss: { Task { await load() } }) {
            ReminderEditorView()
        }
        .task(id: calendarService.changeToken) { await load() }
        .refreshable { await load() }
        .alert("Something went wrong", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func load() async {
        reminders = await calendarService.fetchIncompleteReminders()
    }

    private func complete(_ reminder: EKReminder) {
        do {
            NotificationService.shared.cancelReminderNotification(for: reminder)
            try calendarService.setReminder(reminder, completed: true)
            withAnimation {
                reminders.removeAll { $0.calendarItemIdentifier == reminder.calendarItemIdentifier }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ reminder: EKReminder) {
        do {
            NotificationService.shared.cancelReminderNotification(for: reminder)
            try calendarService.delete(reminder)
            withAnimation {
                reminders.removeAll { $0.calendarItemIdentifier == reminder.calendarItemIdentifier }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

@MainActor
struct ReminderEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CalendarService.self) private var calendarService
    @Environment(AppSettings.self) private var settings

    @State private var title = ""
    @State private var notes = ""
    @State private var hasDueDate = true
    @State private var dueDate = CommandParser.nextReasonableSlot(after: Date(), calendar: .current)
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Remind me to…", text: $title)
                        .font(.body.weight(.medium))
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }
                Section {
                    Toggle("Date & time", isOn: $hasDueDate.animation())
                    if hasDueDate {
                        DatePicker("Remind at", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                    }
                } footer: {
                    Text("Saved to the Reminders app, so it also appears on your other Apple devices.")
                }
            }
            .navigationTitle("New Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .fontWeight(.semibold)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alert("Couldn't save", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func save() {
        do {
            let due = hasDueDate ? dueDate : nil
            let reminder = try calendarService.createReminder(title: title.trimmingCharacters(in: .whitespaces),
                                                              due: due,
                                                              notes: notes,
                                                              addAlarm: settings.useSystemAlerts)
            if let due, !settings.useSystemAlerts {
                NotificationService.shared.scheduleReminderNotification(for: reminder, at: due)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
