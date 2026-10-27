import SwiftData
import SwiftUI
import UserNotifications

@main
struct VoiceCalendarApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// Single SwiftData container shared by the UI, the voice assistant and notification actions.
    static let sharedContainer: ModelContainer = {
        let schema = Schema([Note.self, TaskItem.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create the SwiftData container: \(error)")
        }
    }()

    @State private var settings: AppSettings
    @State private var permissions: PermissionsManager
    @State private var calendarService: CalendarService
    @State private var assistant: VoiceAssistant

    init() {
        let settings = AppSettings.shared
        let calendarService = CalendarService()
        _settings = State(initialValue: settings)
        _permissions = State(initialValue: PermissionsManager())
        _calendarService = State(initialValue: calendarService)
        _assistant = State(initialValue: VoiceAssistant(calendarService: calendarService,
                                                        settings: settings,
                                                        modelContainer: VoiceCalendarApp.sharedContainer))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(permissions)
                .environment(calendarService)
                .environment(assistant)
        }
        .modelContainer(VoiceCalendarApp.sharedContainer)
    }
}

/// Handles notification presentation while the app is in the foreground and the "Mark Done" action.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == "COMPLETE_TASK",
              let idString = response.notification.request.content.userInfo["taskID"] as? String,
              let id = UUID(uuidString: idString) else { return }
        await MainActor.run {
            let context = VoiceCalendarApp.sharedContainer.mainContext
            let descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })
            if let task = try? context.fetch(descriptor).first {
                task.markCompleted(true)
                try? context.save()
            }
        }
    }
}
