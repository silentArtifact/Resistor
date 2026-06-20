import Foundation
import SwiftData

/// Builds the SwiftData `ModelContainer` shared between the app and the widget
/// extension. Both targets include this file, so they open the SAME on-disk
/// store, located inside the App Group container so the widget process can read
/// and write the user's events.
///
/// CloudKit sync is preserved: the configuration keeps `cloudKitDatabase:
/// .automatic`, and the store URL lives in the App Group container (a location
/// CloudKit-backed SwiftData stores support).
///
/// NOTE (migration): before this feature the app stored its data at the default
/// Application Support location. Pointing the store at the App Group URL changes
/// the on-disk location, so existing *local* data does not move automatically.
/// CloudKit-synced data re-downloads on first launch; the app is pre-release
/// (TestFlight), so a fresh local store on first run after this change is
/// acceptable. This is the deliberate trade-off for sharing the store with the
/// widget.
enum SharedModelContainer {

    /// App Group identifier shared by the app target and the widget extension.
    /// Must match the `com.apple.security.application-groups` entitlement on
    /// both targets.
    static let appGroupID = "group.com.resistor.app"

    /// File name of the SwiftData store inside the App Group container.
    private static let storeFileName = "Resistor.store"

    /// The schema shared by app and widget. Keep in sync with the app's models.
    static var schema: Schema {
        Schema([
            Habit.self,
            TemptationEvent.self,
            UserSettings.self,
            ContextTag.self
        ])
    }

    /// URL of the shared store inside the App Group container, or `nil` if the
    /// container cannot be resolved (e.g. the App Group entitlement is missing
    /// at runtime). Callers fall back gracefully when this is `nil`.
    static var storeURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(storeFileName)
    }

    /// Builds the production CloudKit-backed container from the App Group store
    /// URL. Throws if the container cannot be created so the caller can decide
    /// how to handle failure (the app fatal-errors as before; the widget treats
    /// it as the store-unavailable state).
    static func makeContainer() throws -> ModelContainer {
        let configuration: ModelConfiguration
        if let url = storeURL {
            configuration = ModelConfiguration(
                schema: schema,
                url: url,
                cloudKitDatabase: .automatic
            )
        } else {
            // App Group container unavailable — fall back to the default
            // location so the app still functions (the widget will report
            // store-unavailable when it can't see this store).
            configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .automatic
            )
        }
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
