import EventKit
import SwiftUI

extension View {
    /// Rounded, grouped-background card used across the app.
    func cardStyle(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct SectionHeader: View {
    let title: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.weight(.semibold))
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.medium))
            }
        }
    }
}

/// Wraps `EKEvent` so it can drive `.sheet(item:)`.
struct EventSelection: Identifiable {
    let event: EKEvent
    var id: String { event.eventIdentifier ?? event.calendarItemIdentifier }
}

struct EventRow: View {
    let event: EKEvent
    var showsDate = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .trailing, spacing: 2) {
                if event.isAllDay {
                    Text("All day")
                        .font(.subheadline.weight(.medium))
                } else {
                    Text(Formatters.time.string(from: event.startDate))
                        .font(.subheadline.weight(.medium))
                    Text(Formatters.time.string(from: event.endDate))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if showsDate {
                    Text(Formatters.compact(event.startDate, allDay: true))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 76, alignment: .trailing)

            RoundedRectangle(cornerRadius: 2)
                .fill(calendarColor)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 3) {
                Text(event.title ?? "Untitled")
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                if let location = event.location, !location.isEmpty {
                    Label(location, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if event.hasRecurrenceRules {
                    Label("Repeats", systemImage: "repeat")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
    }

    private var calendarColor: Color {
        if let cgColor = event.calendar?.cgColor {
            return Color(cgColor: cgColor)
        }
        return .accentColor
    }
}

/// Rotating examples of what to say.
struct VoiceTipCard: View {
    @Environment(VoiceAssistant.self) private var assistant
    @State private var index = 0
    private let timer = Timer.publish(every: 6, on: .main, in: .common).autoconnect()

    static let examples = [
        "add dentist tomorrow at 3 PM",
        "remind me to call Mom at 6",
        "schedule a meeting with Sam on Friday at 10 AM for an hour",
        "add buy groceries to my tasks",
        "take a note: gift ideas for Dad",
        "what's on my schedule tomorrow?",
        "add team standup every weekday at 9 AM",
        "what's next?"
    ]

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 34))
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 4) {
                Text("Try saying")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text("“\(assistant.wakePhraseDisplay), \(Self.examples[index])”")
                    .font(.subheadline.weight(.medium))
                    .contentTransition(.opacity)
                    .id(index)
            }
            Spacer(minLength: 0)
        }
        .cardStyle()
        .onReceive(timer) { _ in
            withAnimation(.easeInOut) {
                index = (index + 1) % Self.examples.count
            }
        }
        .onTapGesture {
            withAnimation(.easeInOut) {
                index = (index + 1) % Self.examples.count
            }
        }
    }
}

extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        dateInterval(of: .month, for: date)?.start ?? startOfDay(for: date)
    }
}
