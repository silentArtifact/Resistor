import Foundation
import SwiftData

/// Builds the watch-side SwiftData `ModelContainer`.
///
/// App Groups do NOT bridge iPhone and Apple Watch (they are separate devices),
/// so the watch CANNOT open the phone's app-group store. Instead the watch keeps
/// its OWN local store inside its own container directory, configured against the
/// SAME CloudKit container (`iCloud.com.resistor.app`). CloudKit — not
/// WatchConnectivity, not App Groups — is what makes a watch log appear on the
/// phone and vice versa: each device writes locally and the private database
/// syncs whenever it can.
///
/// The schema MUST include all four models so the watch store matches the phone's
/// CloudKit schema exactly.
enum WatchModelContainer {

    /// CloudKit container identifier shared with the phone app. Must match the
    /// `com.apple.developer.icloud-container-identifiers` entitlement.
    static let cloudKitContainerID = "iCloud.com.resistor.app"

    /// The schema shared with the phone. Keep in sync with the app's models.
    static var schema: Schema {
        Schema([
            Habit.self,
            TemptationEvent.self,
            UserSettings.self,
            ContextTag.self
        ])
    }

    /// Builds the production CloudKit-backed container. The store lives at the
    /// default Application Support location inside the watch app's own container
    /// directory (a normal, non-app-group URL). Throws if the container cannot
    /// be created so the caller can fall back to the count-unavailable state.
    static func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private(cloudKitContainerID)
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
