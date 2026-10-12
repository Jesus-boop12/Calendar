import SwiftUI

@MainActor
struct MicButton: View {
    @Environment(VoiceAssistant.self) private var assistant
    @State private var pulse = false

    var body: some View {
        Button(action: tap) {
            ZStack {
                if assistant.isListeningForWakeWord {
                    Circle()
                        .stroke(Color.accentColor.opacity(0.35), lineWidth: 2)
                        .scaleEffect(pulse ? 1.6 : 1)
                        .opacity(pulse ? 0 : 1)
                        .animation(.easeOut(duration: 1.8).repeatForever(autoreverses: false), value: pulse)
                }
                Circle()
                    .fill(
                        LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                                       startPoint: .topLeading,
                                       endPoint: .bottomTrailing)
                    )
                    .shadow(color: Color.accentColor.opacity(0.45), radius: 14, y: 6)
                Image(systemName: iconName)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .symbolEffect(.pulse, isActive: assistant.isCapturing)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 64, height: 64)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .onAppear { pulse = true }
    }

    private var iconName: String {
        switch assistant.phase {
        case .listening: return "waveform"
        case .thinking: return "ellipsis"
        case .speaking: return "speaker.wave.2.fill"
        default: return "mic.fill"
        }
    }

    private var accessibilityLabel: String {
        switch assistant.phase {
        case .listening: return "Finish voice command"
        case .thinking, .speaking: return "Dismiss"
        default: return "Start voice command"
        }
    }

    private func tap() {
        switch assistant.phase {
        case .listening:
            assistant.finishCommandNow()
        case .thinking, .speaking:
            assistant.dismiss()
        default:
            assistant.startManualCommand()
        }
    }
}
