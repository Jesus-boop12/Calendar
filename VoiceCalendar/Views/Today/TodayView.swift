import EventKit
import SwiftData
import SwiftUI

struct TodayView: View {
    private enum QuickAdd: String, Identifiable {
        case event, task, note, reminder
        var id: String { rawValue }
    }

    @Environment(CalendarService.self) private var calendarService
    @Environment(VoiceAssistant.self) private var assistant
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Query(filter: #Predicate<TaskItem> { !$0.isCompleted }, sort: \TaskItem.createdAt) private var openTasks: [TaskItem]

    @State private var events: [EKEvent] = []
    @State private var now = Date()
    @State private var quickAdd: QuickAdd?
    @State private var selectedEvent: EventSelection?

    private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    nextUpCard
                    VoiceTipCard()
                    eventsSection
                    tasksSection
                    if !assistant.history.isEmpty {
                        recentVoiceSection
                    }
                }
                .padding(.horizontal)
                .padding(.top, 4)
                .padding(.bottom, 140)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("New Event", systemImage: "calendar.badge.plus") { quickAdd = .event }
                        Button("New Reminder", systemImage: "bell.badge") { quickAdd = .reminder }
                        Button("New Task", systemImage: "checkmark.circle") { quickAdd = .task }
                        Button("New Note", systemImage: "note.text.badge.plus") { quickAdd = .note }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                }
            }
            .sheet(item: $quickAdd) { item in
                switch item {
                case .event:
                    EventEditorView(mode: .create(defaultStart: CommandParser.nextReasonableSlot(after: Date(), calendar: calendar)))
                case .task:
                    TaskEditorView(task: nil)
                case .note:
                    NewNoteSheet()
                case .reminder:
                    ReminderEditorView()
                }
            }
            .sheet(item: $selectedEvent) { selection in
                EventEditorView(mode: .edit(selection.event))
            }
            .task(id: calendarService.changeToken) { reload() }
            .onReceive(clock) { _ in
                now = Date()
                reload()
            }
            .refreshable { reload() }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(greeting)
                .font(.largeTitle.weight(.bold))
            Text(Formatters.weekdayDate.string(from: now))
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var nextUpCard: some View {
        if let next = events.first(where: { !$0.isAllDay && $0.endDate > now }) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(next.startDate > now ? "Next up" : "Happening now", systemImage: "clock.fill")
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.white.opacity(0.85))
                    Spacer()
                    Text(next.startDate > now
                         ? Formatters.relative.localizedString(for: next.startDate, relativeTo: now)
                         : "until \(Formatters.time.string(from: next.endDate))")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.85))
                }
                Text(next.title ?? "Untitled")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                HStack(spacing: 14) {
                    Label("\(Formatters.time.string(from: next.startDate)) – \(Formatters.time.string(from: next.endDate))", systemImage: "calendar")
                    if let location = next.location, !location.isEmpty {
                        Label(location, systemImage: "mappin.and.ellipse")
                            .lineLimit(1)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.9))
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.75)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .onTapGesture { selectedEvent = EventSelection(event: next) }
        } else if calendarService.hasEventAccess {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(events.isEmpty ? "Nothing scheduled today" : "You're done for today")
                        .font(.headline)
                    Text("Say “\(assistant.wakePhraseDisplay)” to add something.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .cardStyle()
        } else {
            Button {
                Task {
                    if await calendarService.requestEventAccess() {
                        reload()
                    } else if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .font(.title2)
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Calendar access needed")
                            .font(.headline)
                        Text("Allow access so your events sync with the iPhone Calendar.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
                .cardStyle()
            }
            .buttonStyle(.plain)
        }
    }

    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Schedule", actionTitle: "Add") { quickAdd = .event }
            if events.isEmpty {
                Text(calendarService.hasEventAccess ? "No events today." : "Connect your calendar to see today's events.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .cardStyle()
            } else {
                ForEach(events, id: \.calendarItemIdentifier) { event in
                    EventRow(event: event)
                        .opacity(event.endDate < now && !event.isAllDay ? 0.55 : 1)
                        .onTapGesture { selectedEvent = EventSelection(event: event) }
                }
            }
        }
    }

    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Tasks", actionTitle: "Add") { quickAdd = .task }
            if todaysTasks.isEmpty {
                Text("No tasks due today.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .cardStyle()
            } else {
                VStack(spacing: 0) {
                    ForEach(todaysTasks) { task in
                        TaskRow(task: task) { toggle(task) }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                        if task.id != todaysTasks.last?.id {
                            Divider().padding(.leading, 48)
                        }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    private var recentVoiceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Recent voice actions")
            VStack(spacing: 0) {
                ForEach(assistant.history.prefix(4)) { response in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: response.symbolName)
                            .foregroundStyle(response.kind == .error ? Color.red : Color.accentColor)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            if !response.heard.isEmpty {
                                Text("“\(response.heard)”")
                                    .font(.subheadline.weight(.medium))
                            }
                            Text(response.text)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Text(response.timestamp, style: .time)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    if response.id != assistant.history.prefix(4).last?.id {
                        Divider().padding(.leading, 48)
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    // MARK: - Data

    private var greeting: String {
        let hour = calendar.component(.hour, from: now)
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Hello"
        }
    }

    private var todaysTasks: [TaskItem] {
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        return openTasks
            .filter { task in
                guard let due = task.dueDate else { return false }
                return due < endOfToday
            }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    private func reload() {
        events = calendarService.events(on: now)
    }

    private func toggle(_ task: TaskItem) {
        withAnimation {
            task.markCompleted(!task.isCompleted)
        }
        NotificationService.shared.scheduleTaskNotification(for: task)
        try? modelContext.save()
        assistant.agendaDidChange()
    }
}

/// Presents a fresh note inside its own navigation stack.
struct NewNoteSheet: View {
    @Environment(\.modelContext) private var modelContext
    @State private var note: Note?

    var body: some View {
        NavigationStack {
            if let note {
                NoteEditorView(note: note, showsDoneButton: true)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            if note == nil {
                let fresh = Note(title: "", body: "")
                modelContext.insert(fresh)
                note = fresh
            }
        }
    }
}
