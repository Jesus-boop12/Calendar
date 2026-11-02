import AVFoundation
import EventKit
import Foundation
import Observation
import Speech
import UserNotifications

/// Tracks and requests every system permission the app relies on.
@Observable
@MainActor
final class PermissionsManager {
    enum Status: Equatable {
        case notDetermined
        case granted
        case denied
        case restricted

        var label: String {
            switch self {
            case .notDetermined: return "Not requested"
            case .granted: return "Allowed"
            case .denied: return "Denied"
            case .restricted: return "Restricted"
            }
        }

        var isGranted: Bool { self == .granted }
    }

    private(set) var microphone: Status = .notDetermined
    private(set) var speechRecognition: Status = .notDetermined
    private(set) var calendar: Status = .notDetermined
    private(set) var reminders: Status = .notDetermined
    private(set) var notifications: Status = .notDetermined

    /// Everything the voice assistant needs to listen and act on the calendar.
    var voiceReady: Bool { microphone.isGranted && speechRecognition.isGranted }

    func refresh() async {
        microphone = Self.map(AVAudioApplication.shared.recordPermission)
        speechRecognition = Self.map(SFSpeechRecognizer.authorizationStatus())
        calendar = Self.map(EKEventStore.authorizationStatus(for: .event))
        reminders = Self.map(EKEventStore.authorizationStatus(for: .reminder))
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notifications = Self.map(settings.authorizationStatus)
    }

    /// Requests all permissions in sequence so the user sees one prompt at a time.
    func requestAll(using calendarService: CalendarService) async {
        _ = await requestMicrophone()
        _ = await requestSpeechRecognition()
        _ = await calendarService.requestEventAccess()
        _ = await calendarService.requestReminderAccess()
        _ = await NotificationService.shared.requestAuthorization()
        await refresh()
    }

    func requestMicrophone() async -> Bool {
        let granted = await AVAudioApplication.requestRecordPermission()
        microphone = granted ? .granted : .denied
        return granted
    }

    func requestSpeechRecognition() async -> Bool {
        let status: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        speechRecognition = Self.map(status)
        return status == .authorized
    }

    // MARK: - Mapping helpers

    private static func map(_ permission: AVAudioApplication.recordPermission) -> Status {
        switch permission {
        case .granted: return .granted
        case .denied: return .denied
        case .undetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }

    private static func map(_ status: SFSpeechRecognizerAuthorizationStatus) -> Status {
        switch status {
        case .authorized: return .granted
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }

    private static func map(_ status: EKAuthorizationStatus) -> Status {
        switch status {
        case .fullAccess: return .granted
        case .writeOnly: return .granted
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }

    private static func map(_ status: UNAuthorizationStatus) -> Status {
        switch status {
        case .authorized, .provisional, .ephemeral: return .granted
        case .denied: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }
}
