import SwiftUI

/// watchOS Quick-Log companion app entry point. A single-window, single-screen
/// app: one tap logs a resisted temptation against the resolved target habit and
/// CloudKit syncs it to the phone.
@main
struct ResistorWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchLogView()
        }
    }
}
