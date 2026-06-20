import SwiftUI
import SwiftData

@main
struct ResistorApp: App {
    var sharedModelContainer: ModelContainer = {
        #if DEBUG
        // UI-test screenshot runs use a clean in-memory store seeded with
        // deterministic sample data, bypassing onboarding and CloudKit.
        if UITestSeed.isActive {
            let testConfiguration = ModelConfiguration(
                schema: SharedModelContainer.schema,
                isStoredInMemoryOnly: true
            )
            do {
                let container = try ModelContainer(
                    for: SharedModelContainer.schema,
                    configurations: [testConfiguration]
                )
                UITestSeed.populate(container.mainContext)
                return container
            } catch {
                fatalError("Could not create UI-test ModelContainer: \(error)")
            }
        }
        #endif

        // Production store lives in the App Group container so the Home Screen
        // widget extension shares the same SwiftData store (CloudKit-backed).
        do {
            return try SharedModelContainer.makeContainer()
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(forcedColorScheme)
        }
        .modelContainer(sharedModelContainer)
    }

    /// Forces a color scheme only during UI-test screenshot runs (see
    /// `UITestSeed.forcedColorScheme`). `nil` in normal builds, so production
    /// behavior — following the system appearance — is unchanged.
    private var forcedColorScheme: ColorScheme? {
        #if DEBUG
        return UITestSeed.forcedColorScheme
        #else
        return nil
        #endif
    }
}
