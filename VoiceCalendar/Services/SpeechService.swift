import AVFoundation
import Foundation
import Observation
import Speech

enum SpeechServiceError: LocalizedError {
    case recognizerUnavailable
    case notAuthorized
    case microphoneUnavailable

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            return "Speech recognition isn't available right now. Check your internet connection or try again later."
        case .notAuthorized:
            return "Microphone or speech recognition access hasn't been granted."
        case .microphoneUnavailable:
            return "No microphone input is available on this device."
        }
    }
}

/// Streams microphone audio into `SFSpeechRecognizer` and reports live transcripts.
/// One instance runs a single recognition session at a time; `VoiceAssistant` decides when to restart it.
@Observable
final class SpeechService {
    private(set) var isRunning = false
    private(set) var transcript = ""
    /// Normalized microphone level (0...1) for the waveform UI.
    private(set) var audioLevel: Float = 0

    /// Called on the main thread with every partial or final transcript.
    @ObservationIgnored var onResult: ((String, Bool) -> Void)?
    /// Called on the main thread when the recognition session ends (final result, timeout or error).
    @ObservationIgnored var onSessionEnded: ((Error?) -> Void)?

    private let audioEngine = AVAudioEngine()
    @ObservationIgnored private var recognizer: SFSpeechRecognizer?
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var levelSampleCounter = 0

    init(locale: Locale = .current) {
        recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer()
    }

    var isAvailable: Bool { recognizer?.isAvailable ?? false }
    var supportsOnDeviceRecognition: Bool { recognizer?.supportsOnDeviceRecognition ?? false }

    // MARK: - Session control

    func start(preferOnDevice: Bool) throws {
        guard !isRunning else { return }
        guard SFSpeechRecognizer.authorizationStatus() == .authorized,
              AVAudioApplication.shared.recordPermission == .granted else {
            throw SpeechServiceError.notAuthorized
        }
        guard let recognizer, recognizer.isAvailable else {
            throw SpeechServiceError.recognizerUnavailable
        }

        task?.cancel()
        task = nil

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.addsPunctuation = true
        request.requiresOnDeviceRecognition = preferOnDevice && recognizer.supportsOnDeviceRecognition
        self.request = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw SpeechServiceError.microphoneUnavailable
        }
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.request?.append(buffer)
            self.sampleLevel(from: buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            throw error
        }

        isRunning = true
        transcript = ""

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            DispatchQueue.main.async {
                if let text {
                    self.transcript = text
                    self.onResult?(text, isFinal)
                }
                if error != nil || isFinal {
                    self.finishSession(error: error)
                }
            }
        }
    }

    func stop() {
        isRunning = false
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        audioLevel = 0
        // The audio session stays active so spoken feedback can play; the assistant deactivates it when idle.
    }

    func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func finishSession(error: Error?) {
        guard isRunning else { return }
        stop()
        onSessionEnded?(error)
    }

    // MARK: - Metering

    private func sampleLevel(from buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }
        var sum: Float = 0
        for index in 0..<frameLength {
            let sample = channelData[index]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frameLength))
        let decibels = 20 * log10(max(rms, 0.000_000_1))
        let normalized = max(0, min(1, (decibels + 50) / 50))

        levelSampleCounter += 1
        guard levelSampleCounter % 2 == 0 else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isRunning else { return }
            // Smooth so the waveform doesn't flicker.
            self.audioLevel = self.audioLevel * 0.6 + normalized * 0.4
        }
    }
}
