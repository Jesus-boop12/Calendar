import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(PermissionsManager.self) private var permissions
    @Environment(VoiceAssistant.self) private var assistant
    @Environment(CalendarService.self) private var calendarService
    @Environment(\.openURL) private var openURL

    private let durations = [15, 30, 45, 60, 90, 120]
    private let leadTimes = [0, 5, 10, 15, 30, 60]

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            Form {
                Section {
                    Toggle("Listen for wake phrase", isOn: $settings.wakeWordEnabled)
                    HStack {
                        Text("Wake phrase")
                        Spacer()
                        TextField(AppSettings.defaultWakePhrase, text: $settings.wakePhrase)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .foregroundStyle(.secondary)
                    }
                    Toggle("Speak responses", isOn: $settings.spokenFeedback)
                    Toggle("Prefer on-device recognition", isOn: $settings.preferOnDeviceRecognition)
                    Toggle("Keep listening in background", isOn: $settings.listenInBackground)
                } header: {
                    Text("Voice")
                } footer: {
                    Text("While the app is open it listens for “\(assistant.wakePhraseDisplay)”. Background listening keeps the microphone on after you leave the app, which uses more battery and shows the orange microphone indicator. On-device recognition is more private and works offline, but may be slightly less accurate.")
                }

                Section {
                    Picker("Default event length", selection: $settings.defaultEventDurationMinutes) {
                        ForEach(durations, id: \.self) { minutes in
                            Text(durationLabel(minutes)).tag(minutes)
                        }
                    }
                    Picker("Alert before events", selection: $settings.eventAlertLeadMinutes) {
                        ForEach(leadTimes, id: \.self) { minutes in
                            Text(leadLabel(minutes)).tag(minutes)
                        }
                    }
                    Toggle("Deliver alerts via Calendar & Reminders", isOn: $settings.useSystemAlerts)
                } header: {
                    Text("Events & reminders")
                } footer: {
                    Text("When on, alerts are attached to the event or reminder itself so iOS delivers them even if this app is closed. When off, Voice Calendar sends its own notifications instead.")
                }

                Section {
                    Toggle("Morning briefing", isOn: $settings.dailyBriefingEnabled)
                    if settings.dailyBriefingEnabled {
                        Picker("Time", selection: $settings.dailyBriefingHour) {
                            ForEach(5..<12, id: \.self) { hour in
                                Text(hourLabel(hour)).tag(hour)
                            }
                        }
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("A summary of tomorrow's events and tasks, refreshed whenever your schedule changes.")
                }

                Section {
                    PermissionRow(title: "Microphone", symbol: "mic.fill", status: permissions.microphone)
                    PermissionRow(title: "Speech recognition", symbol: "waveform", status: permissions.speechRecognition)
                    PermissionRow(title: "Calendar", symbol: "calendar", status: permissions.calendar)
                    PermissionRow(title: "Reminders", symbol: "bell.fill", status: permissions.reminders)
                    PermissionRow(title: "Notifications", symbol: "app.badge.fill", status: permissions.notifications)
                    if needsRequest {
                        Button("Request missing permissions") {
                            Task {
                                await permissions.requestAll(using: calendarService)
                                assistant.activateIfPossible()
                            }
                        }
                    }
                    Button("Open iOS Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                } header: {
                    Text("Permissions")
                }

                Section("Try saying") {
                    ForEach(VoiceTipCard.examples, id: \.self) { example in
                        Text("“\(assistant.wakePhraseDisplay), \(example)”")
                            .font(.subheadline)
                    }
                }

                Section("About") {
                    LabeledContent("Version", value: appVersion)
                    LabeledContent("Speech engine", value: assistant.speech.supportsOnDeviceRecognition ? "On-device available" : "Server-based")
                }
            }
            .navigationTitle("Settings")
            .onChange(of: settings.wakeWordEnabled) { assistant.settingsChanged() }
            .onChange(of: settings.listenInBackground) { assistant.settingsChanged() }
            .onChange(of: settings.dailyBriefingEnabled) { assistant.agendaDidChange() }
            .onChange(of: settings.dailyBriefingHour) { assistant.agendaDidChange() }
            .task { await permissions.refresh() }
        }
    }

    private var needsRequest: Bool {
        [permissions.microphone, permissions.speechRecognition, permissions.calendar, permissions.reminders, permissions.notifications]
            .contains(.notDetermined)
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }

    private func durationLabel(_ minutes: Int) -> String {
        switch minutes {
        case ..<60: return "\(minutes) min"
        case 60: return "1 hour"
        case 90: return "1.5 hours"
        default: return "\(minutes / 60) hours"
        }
    }

    private func leadLabel(_ minutes: Int) -> String {
        switch minutes {
        case 0: return "At time of event"
        case 60: return "1 hour before"
        default: return "\(minutes) min before"
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        let date = Calendar.current.date(from: components) ?? Date()
        return Formatters.time.string(from: date)
    }
}

private struct PermissionRow: View {
    let title: String
    let symbol: String
    let status: PermissionsManager.Status

    var body: some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer()
            Text(status.label)
                .font(.subheadline)
                .foregroundStyle(color)
        }
    }

    private var color: Color {
        switch status {
        case .granted: return .green
        case .denied, .restricted: return .red
        case .notDetermined: return .secondary
        }
    }
}
