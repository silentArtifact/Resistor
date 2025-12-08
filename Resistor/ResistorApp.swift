import SwiftUI
import SwiftData

@main
struct ResistorApp: App {
    @StateObject private var notificationManager = NotificationManager.shared
    @Environment(\.scenePhase) private var scenePhase

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Habit.self,
            TemptationEvent.self,
            UserSettings.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    setupNotificationsIfNeeded()
                }
        }
        .modelContainer(sharedModelContainer)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                notificationManager.checkAuthorizationStatus()
            }
        }
    }

    private func setupNotificationsIfNeeded() {
        let context = sharedModelContainer.mainContext
        let descriptor = FetchDescriptor<UserSettings>()

        do {
            let settings = try context.fetch(descriptor)
            if let userSettings = settings.first,
               userSettings.dailyReminderEnabled,
               let hour = userSettings.dailyReminderHour,
               let minute = userSettings.dailyReminderMinute {
                Task {
                    await notificationManager.scheduleDailyReminder(hour: hour, minute: minute)
                }
            }
        } catch {
            print("Failed to fetch user settings for notifications: \(error)")
        }
    }
}
