import SwiftUI

struct RootView: View {
    enum Tab: Hashable {
        case today, calendar, tasks, notes, settings
    }

    @Environment(VoiceAssistant.self) private var assistant
    @Environment(AppSettings.self) private var settings
    @Environment(PermissionsManager.self) private var permissions
    @Environment(CalendarService.self) private var calendarService
    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedTab: Tab = .today
    @State private var showOnboarding = false

    var body: some View {
        @Bindable var assistant = assistant

        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                TodayView()
                    .tabItem { Label("Today", systemImage: "sun.max.fill") }
                    .tag(Tab.today)
                CalendarView()
                    .tabItem { Label("Calendar", systemImage: "calendar") }
                    .tag(Tab.calendar)
                TasksView()
                    .tabItem { Label("Tasks", systemImage: "checklist") }
                    .tag(Tab.tasks)
                NotesView()
                    .tabItem { Label("Notes", systemImage: "note.text") }
                    .tag(Tab.notes)
                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                    .tag(Tab.settings)
            }

            VStack(spacing: 12) {
                if assistant.isOverlayVisible {
                    VoiceOverlayView()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                HStack(alignment: .bottom) {
                    if assistant.isListeningForWakeWord && !assistant.isOverlayVisible {
                        WakeWordPill(phrase: assistant.wakePhraseDisplay)
                            .transition(.opacity)
                    }
                    Spacer()
                    MicButton()
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 64)
            .animation(.spring(duration: 0.35), value: assistant.isOverlayVisible)
            .animation(.easeInOut(duration: 0.2), value: assistant.isListeningForWakeWord)
        }
        .sheet(isPresented: $showOnboarding, onDismiss: { assistant.activateIfPossible() }) {
            OnboardingView()
        }
        .sheet(item: $assistant.eventToEdit) { target in
            if let event = calendarService.event(withIdentifier: target.id) {
                EventEditorView(mode: .edit(event))
            } else {
                ContentUnavailableView("Event not found", systemImage: "calendar.badge.exclamationmark")
            }
        }
        .task {
            await permissions.refresh()
            if settings.hasCompletedOnboarding {
                assistant.activateIfPossible()
            } else {
                showOnboarding = true
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            assistant.handleScenePhase(newPhase)
            if newPhase == .active {
                Task { await permissions.refresh() }
            }
        }
    }
}

/// Small hint shown while the assistant is passively listening.
private struct WakeWordPill: View {
    let phrase: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "ear")
                .font(.caption.weight(.semibold))
            Text("Say “\(phrase)”")
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .padding(.bottom, 10)
    }
}
