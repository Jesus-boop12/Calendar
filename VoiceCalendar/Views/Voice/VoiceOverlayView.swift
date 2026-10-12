import SwiftUI

/// Bottom card showing the live transcript and the assistant's response.
@MainActor
struct VoiceOverlayView: View {
    @Environment(VoiceAssistant.self) private var assistant

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(title, systemImage: titleSymbol)
                    .font(.headline)
                    .foregroundStyle(titleColor)
                Spacer()
                Button {
                    assistant.dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }

            if assistant.isCapturing {
                WaveformView(level: assistant.speech.audioLevel)
                    .frame(height: 40)
            }

            if !assistant.liveTranscript.isEmpty {
                Text("“\(assistant.liveTranscript)”")
                    .font(assistant.isCapturing ? .title3.weight(.medium) : .subheadline)
                    .foregroundStyle(assistant.isCapturing ? .primary : .secondary)
                    .animation(.default, value: assistant.liveTranscript)
            } else if assistant.isCapturing {
                Text("Say something like “add dentist tomorrow at 3 PM”")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if case .error(let message) = assistant.phase {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }

            if let response = assistant.lastResponse, !assistant.isCapturing {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: response.symbolName)
                        .font(.title3)
                        .foregroundStyle(color(for: response.kind))
                    Text(response.text)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if case .event(let identifier) = response.createdItem {
                    Button {
                        assistant.eventToEdit = EventEditTarget(id: identifier)
                    } label: {
                        Label("Edit event", systemImage: "pencil")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            if assistant.phase == .thinking {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Working on it…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06))
        )
        .shadow(color: .black.opacity(0.14), radius: 22, y: 8)
    }

    private var title: String {
        switch assistant.phase {
        case .listening: return "Listening…"
        case .thinking: return "Thinking…"
        case .speaking: return "Done"
        case .error: return "Couldn't listen"
        case .waitingForWakeWord, .off:
            if let response = assistant.lastResponse {
                switch response.kind {
                case .success: return "Done"
                case .info: return "Here's what I found"
                case .error: return "Hmm"
                }
            }
            return "Voice Calendar"
        }
    }

    private var titleSymbol: String {
        switch assistant.phase {
        case .listening: return "waveform"
        case .thinking: return "sparkles"
        case .speaking: return "speaker.wave.2"
        case .error: return "exclamationmark.triangle"
        default: return "checkmark.seal"
        }
    }

    private var titleColor: Color {
        if case .error = assistant.phase { return .red }
        return .primary
    }

    private func color(for kind: AssistantResponse.Kind) -> Color {
        switch kind {
        case .success: return .green
        case .info: return .accentColor
        case .error: return .red
        }
    }
}

/// Simple animated bars driven by the microphone level.
struct WaveformView: View {
    var level: Float
    private let barCount = 26

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule()
                    .fill(Color.accentColor.gradient)
                    .frame(width: 4, height: height(for: index))
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.easeOut(duration: 0.12), value: level)
        .accessibilityHidden(true)
    }

    private func height(for index: Int) -> CGFloat {
        let center = Double(barCount - 1) / 2
        let distance = abs(Double(index) - center) / center
        let envelope = 1 - distance * 0.75
        let wobble = (sin(Double(index) * 1.9 + Double(level) * 25) + 1) / 2 * 0.5 + 0.5
        let base = 6.0
        return CGFloat(base + Double(level) * 34 * envelope * wobble)
    }
}
