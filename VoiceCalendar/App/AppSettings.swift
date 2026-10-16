import Foundation
import Observation

/// User preferences, persisted in `UserDefaults` and observable from SwiftUI.
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private enum Keys {
        static let wakeWordEnabled = "wakeWordEnabled"
        static let wakePhrase = "wakePhrase"
        static let spokenFeedback = "spokenFeedback"
        static let preferOnDeviceRecognition = "preferOnDeviceRecognition"
        static let listenInBackground = "listenInBackground"
        static let defaultEventDurationMinutes = "defaultEventDurationMinutes"
        static let eventAlertLeadMinutes = "eventAlertLeadMinutes"
        static let useSystemAlerts = "useSystemAlerts"
        static let dailyBriefingEnabled = "dailyBriefingEnabled"
        static let dailyBriefingHour = "dailyBriefingHour"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let accent = "themeAccent"
        static let appearance = "appearanceMode"
        static let useRoundedFont = "useRoundedFont"
        static let showWakeHint = "showWakeHint"
    }

    static let defaultWakePhrase = "Hey Calendar"

    private let defaults: UserDefaults

    /// Keep listening for the wake phrase while the app is open.
    var wakeWordEnabled: Bool { didSet { defaults.set(wakeWordEnabled, forKey: Keys.wakeWordEnabled) } }
    /// The phrase that activates the assistant, e.g. "Hey Calendar".
    var wakePhrase: String { didSet { defaults.set(wakePhrase, forKey: Keys.wakePhrase) } }
    /// Read responses out loud.
    var spokenFeedback: Bool { didSet { defaults.set(spokenFeedback, forKey: Keys.spokenFeedback) } }
    /// Use on-device speech recognition when the device supports it.
    var preferOnDeviceRecognition: Bool { didSet { defaults.set(preferOnDeviceRecognition, forKey: Keys.preferOnDeviceRecognition) } }
    /// Keep the microphone open when the app goes to the background.
    var listenInBackground: Bool { didSet { defaults.set(listenInBackground, forKey: Keys.listenInBackground) } }
    /// Length of an event when no duration is spoken.
    var defaultEventDurationMinutes: Int { didSet { defaults.set(defaultEventDurationMinutes, forKey: Keys.defaultEventDurationMinutes) } }
    /// How long before an event the alert fires.
    var eventAlertLeadMinutes: Int { didSet { defaults.set(eventAlertLeadMinutes, forKey: Keys.eventAlertLeadMinutes) } }
    /// When true, event and reminder alerts are attached to the Calendar/Reminders item itself
    /// (delivered by iOS). When false, the app schedules its own local notifications instead.
    var useSystemAlerts: Bool { didSet { defaults.set(useSystemAlerts, forKey: Keys.useSystemAlerts) } }
    /// Morning summary notification.
    var dailyBriefingEnabled: Bool { didSet { defaults.set(dailyBriefingEnabled, forKey: Keys.dailyBriefingEnabled) } }
    var dailyBriefingHour: Int { didSet { defaults.set(dailyBriefingHour, forKey: Keys.dailyBriefingHour) } }
    var hasCompletedOnboarding: Bool { didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding) } }

    // MARK: Appearance

    /// Accent colour used for buttons, highlights and the hero cards.
    var accent: ThemeAccent { didSet { defaults.set(accent.rawValue, forKey: Keys.accent) } }
    /// Light, dark or follow the system setting.
    var appearance: AppearanceMode { didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) } }
    /// Use the rounded system typeface for a softer look.
    var useRoundedFont: Bool { didSet { defaults.set(useRoundedFont, forKey: Keys.useRoundedFont) } }
    /// Show the “Say Hey Calendar” pill while passively listening.
    var showWakeHint: Bool { didSet { defaults.set(showWakeHint, forKey: Keys.showWakeHint) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Keys.wakeWordEnabled: true,
            Keys.wakePhrase: AppSettings.defaultWakePhrase,
            Keys.spokenFeedback: true,
            Keys.preferOnDeviceRecognition: true,
            Keys.listenInBackground: false,
            Keys.defaultEventDurationMinutes: 60,
            Keys.eventAlertLeadMinutes: 15,
            Keys.useSystemAlerts: true,
            Keys.dailyBriefingEnabled: true,
            Keys.dailyBriefingHour: 8,
            Keys.hasCompletedOnboarding: false,
            Keys.accent: ThemeAccent.indigo.rawValue,
            Keys.appearance: AppearanceMode.system.rawValue,
            Keys.useRoundedFont: false,
            Keys.showWakeHint: true
        ])
        wakeWordEnabled = defaults.bool(forKey: Keys.wakeWordEnabled)
        wakePhrase = defaults.string(forKey: Keys.wakePhrase) ?? AppSettings.defaultWakePhrase
        spokenFeedback = defaults.bool(forKey: Keys.spokenFeedback)
        preferOnDeviceRecognition = defaults.bool(forKey: Keys.preferOnDeviceRecognition)
        listenInBackground = defaults.bool(forKey: Keys.listenInBackground)
        defaultEventDurationMinutes = defaults.integer(forKey: Keys.defaultEventDurationMinutes)
        eventAlertLeadMinutes = defaults.integer(forKey: Keys.eventAlertLeadMinutes)
        useSystemAlerts = defaults.bool(forKey: Keys.useSystemAlerts)
        dailyBriefingEnabled = defaults.bool(forKey: Keys.dailyBriefingEnabled)
        dailyBriefingHour = defaults.integer(forKey: Keys.dailyBriefingHour)
        hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)
        accent = ThemeAccent(rawValue: defaults.string(forKey: Keys.accent) ?? "") ?? .indigo
        appearance = AppearanceMode(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system
        useRoundedFont = defaults.bool(forKey: Keys.useRoundedFont)
        showWakeHint = defaults.bool(forKey: Keys.showWakeHint)
    }

    /// The wake phrase, normalized for matching against transcripts.
    var normalizedWakePhrase: String {
        let trimmed = wakePhrase.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed.isEmpty ? AppSettings.defaultWakePhrase : trimmed).lowercased()
    }
}
