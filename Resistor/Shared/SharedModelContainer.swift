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
/// the on-disk location, so existing *local* data does not move automatically —
/// `resolvedStoreURL` copies it across on first launch.
///
/// This used to read "a fresh local store on first run is acceptable, the app is
/// pre-release and CloudKit re-downloads anyway." Both halves were wrong. The
/// App Groups capability was never actually enabled on the device (issue #47),
/// so `storeURL` returned nil and the relocation never happened — the assumption
/// went untested for six weeks. And CloudKit only re-downloads what it holds:
/// Production had no `CD_*` record types at all until 2026-07-31, so for a
/// TestFlight user the cloud copy did not exist and "it re-syncs" would have
/// meant an empty app.
enum SharedModelContainer {

    /// App Group identifier shared by the app target and the widget extension.
    /// Must match the `com.apple.security.application-groups` entitlement on
    /// both targets.
    static let appGroupID = "group.com.resistor.app"

    /// File name of the SwiftData store inside the App Group container.
    private static let storeFileName = "Resistor.store"

    /// File name of the device-local store — see `localSchema`.
    private static let localStoreFileName = "ContactPlaces.store"

    /// The synced models: the user's own data, mirrored to CloudKit.
    static var cloudSchema: Schema {
        Schema([
            Habit.self,
            TemptationEvent.self,
            UserSettings.self,
            ContextTag.self,
            Place.self
        ])
    }

    /// The device-local models, in their own store with `cloudKitDatabase:
    /// .none`.
    ///
    /// `ContactPlace` is a derived cache of the address book — geocoded from
    /// Contacts, which the user's devices already sync themselves. Keeping it
    /// out of CloudKit means no postal address ever leaves the phone, and no
    /// `CD_ContactPlace` record type has to be created by hand and deployed to
    /// Production before the feature works for a TestFlight user (see CLAUDE.md
    /// → "The Production schema is a separate thing you must deploy by hand").
    /// It costs a rebuild per device, which is the Settings button that made it.
    static var localSchema: Schema {
        Schema([ContactPlace.self])
    }

    /// Every model in the container, across both configurations. Keep in sync
    /// with the app's models.
    static var schema: Schema {
        Schema([
            Habit.self,
            TemptationEvent.self,
            UserSettings.self,
            ContextTag.self,
            Place.self,
            ContactPlace.self
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
        let cloudConfiguration: ModelConfiguration
        let localConfiguration: ModelConfiguration
        if let url = storeURL {
            cloudConfiguration = ModelConfiguration(
                schema: cloudSchema,
                url: resolvedStoreURL(groupStore: url),
                cloudKitDatabase: .automatic
            )
            localConfiguration = ModelConfiguration(
                "ContactPlaces",
                schema: localSchema,
                url: url.deletingLastPathComponent().appendingPathComponent(localStoreFileName),
                cloudKitDatabase: .none
            )
        } else {
            // App Group container unavailable — fall back to the default
            // location so the app still functions (the widget will report
            // store-unavailable when it can't see this store).
            cloudConfiguration = ModelConfiguration(
                schema: cloudSchema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .automatic
            )
            localConfiguration = ModelConfiguration(
                "ContactPlaces",
                schema: localSchema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .none
            )
        }
        // No migration for the local store, deliberately: it has never existed
        // anywhere else, and it is a cache — an empty one costs a tap on the
        // Settings button, not data.
        return try ModelContainer(
            for: schema,
            configurations: [cloudConfiguration, localConfiguration]
        )
    }

    // MARK: - Legacy Store Migration

    /// Where the store lived before it moved into the App Group: SwiftData's
    /// default location, `Library/Application Support/default.store`.
    static var legacyStoreURL: URL? {
        try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            .appendingPathComponent("default.store")
    }

    /// The sidecar files SQLite keeps beside a store in WAL mode. The `-wal` is
    /// not optional bookkeeping — it holds every transaction since the last
    /// checkpoint, which on a real device was 1.8 MB against a 508 KB store.
    /// Copying the `.store` alone silently rewinds the app to its last
    /// checkpoint, which for this app's write pattern can be weeks.
    private static let storeFileSuffixes = ["", "-shm", "-wal"]

    /// The store URL to actually open, migrating a stranded pre-App-Group store
    /// into the shared container first if one is found.
    ///
    /// Pointing the configuration at the App Group URL does **not** move the
    /// existing file. Without this, the first launch after the App Groups
    /// capability goes live opens a brand-new empty store while every habit and
    /// event the user ever logged sits at the old path, visible to nobody and
    /// still on disk — the app looks wiped. That hasn't fired yet only because
    /// the entitlement isn't active on device (issue #47); it fires the moment
    /// the checkbox is ticked.
    ///
    /// Falls back to opening the **legacy** store in place if the copy fails.
    /// An app running on last month's data is a bug; an app that looks empty
    /// because a file copy threw is indistinguishable from data loss.
    static func resolvedStoreURL(groupStore: URL) -> URL {
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: groupStore.path),
              let legacy = legacyStoreURL,
              fileManager.fileExists(atPath: legacy.path) else { return groupStore }

        do {
            try migrateStore(from: legacy, to: groupStore)
            return groupStore
        } catch {
            print("Legacy store migration failed, opening the legacy store in place: \(error)")
            return legacy
        }
    }

    /// Copies a store and its WAL sidecars to a new location.
    ///
    /// Copies rather than moves, deliberately. The original stays where it is,
    /// so a migration that goes wrong costs disk space instead of the user's
    /// history, and the old file remains available to recover by hand. Only the
    /// copy is ever opened, so the leftover is inert.
    ///
    /// ponytail: a plain file copy, not the sqlite3 backup API. Correct because
    /// this runs before the container opens the store, so nothing on this device
    /// holds a write lock. The widget extension is the one process that could
    /// race it; if that ever becomes real, this needs the backup API.
    ///
    /// ponytail: does not move the `.<name>_SUPPORT` or `<name>_ckAssets`
    /// sidecar directories, which hold external binary data and CloudKit assets.
    /// No model here has a `Data` property, so both are empty in practice — on
    /// the device they were 96 and 64 bytes. Move them too, renamed to match the
    /// new store's basename, if a model ever gains one.
    static func migrateStore(from legacy: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        do {
            for suffix in storeFileSuffixes {
                let source = URL(fileURLWithPath: legacy.path + suffix)
                guard fileManager.fileExists(atPath: source.path) else { continue }
                try fileManager.copyItem(at: source, to: URL(fileURLWithPath: destination.path + suffix))
            }
        } catch {
            // Clear a half-written destination so the next launch retries the
            // migration instead of opening a store missing its own WAL.
            for suffix in storeFileSuffixes {
                try? fileManager.removeItem(at: URL(fileURLWithPath: destination.path + suffix))
            }
            throw error
        }
    }
}
