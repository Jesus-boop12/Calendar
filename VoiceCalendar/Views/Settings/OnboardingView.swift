import SwiftUI

@MainActor
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @Environment(PermissionsManager.self) private var permissions
    @Environment(CalendarService.self) private var calendarService

    @State private var isRequesting = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 12)
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 120, height: 120)
                Image(systemName: "waveform.and.mic")
                    .font(.system(size: 52, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
            VStack(spacing: 8) {
                Text("Welcome to Voice Calendar")
                    .font(.largeTitle.weight(.bold))
                    .multilineTextAlignment(.center)
                Text("Your schedule, hands-free.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 18) {
                FeatureRow(symbol: "mic.fill",
                           title: "Say “\(AppSettings.defaultWakePhrase)”",
                           detail: "Then speak naturally: “add dentist tomorrow at 3 PM”.")
                FeatureRow(symbol: "calendar",
                           title: "Syncs with your iPhone calendar",
                           detail: "Events go straight into the Calendar app and all your devices.")
                FeatureRow(symbol: "bell.badge.fill",
                           title: "Reminders & notifications",
                           detail: "Get alerted before events, reminders and tasks.")
                FeatureRow(symbol: "note.text",
                           title: "Notes & daily tasks",
                           detail: "Capture ideas and to-dos by voice or by hand.")
            }
            .padding(.horizontal, 8)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    Task {
                        isRequesting = true
                        await permissions.requestAll(using: calendarService)
                        settings.hasCompletedOnboarding = true
                        isRequesting = false
                        dismiss()
                    }
                } label: {
                    HStack {
                        if isRequesting { ProgressView().tint(.white) }
                        Text("Allow access & get started")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isRequesting)

                Button("Not now") {
                    settings.hasCompletedOnboarding = true
                    dismiss()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            Text("Voice Calendar asks for microphone, speech recognition, calendar, reminders and notification access. Nothing is uploaded to this app's servers; speech is processed by Apple on-device where available.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .interactiveDismissDisabled()
    }
}

private struct FeatureRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
