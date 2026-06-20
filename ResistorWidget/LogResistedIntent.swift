import AppIntents
import WidgetKit
import SwiftData
import Foundation

/// Interactive App Intent fired by tapping the widget card. Logs a single
/// "resisted" `TemptationEvent` for the bound habit WITHOUT launching the app,
/// then reloads widget timelines so the count refreshes.
///
/// Debounce: one physical tap can deliver the intent more than once; we store
/// the last-fire timestamp per habit id in App Group `UserDefaults` and ignore a
/// re-fire within `debounceInterval`. Two deliberate taps spaced further apart
/// still produce two events.
struct LogResistedIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Resisted Temptation"
    static var description = IntentDescription("Logs a resisted temptation for this habit.")

    /// No app launch — the write happens entirely in the extension process.
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Habit ID")
    var habitID: String

    init() {}

    init(habitID: UUID) {
        self.habitID = habitID.uuidString
    }

    private static let debounceInterval: TimeInterval = 0.8

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: habitID) else {
            return .result()
        }

        // Debounce duplicate deliveries of the same physical tap.
        if Self.isDebounced(habitID: habitID) {
            return .result()
        }
        Self.recordFire(habitID: habitID)

        guard let container = try? SharedModelContainer.makeContainer() else {
            // Store unavailable: nothing we can persist now. The at-rest UI's
            // store-unavailable state already tells the user the count updates
            // later; we simply can't enqueue here.
            print("LogResistedIntent: shared container unavailable")
            return .result()
        }

        let context = container.mainContext
        let descriptor = FetchDescriptor<Habit>(
            predicate: #Predicate { habit in
                habit.id == id && !habit.isArchived
            }
        )

        guard let habit = try? context.fetch(descriptor).first else {
            // Bound habit archived or deleted — needs-reconfiguration. Don't
            // write an orphan event.
            print("LogResistedIntent: habit \(habitID) unavailable")
            return .result()
        }

        TemptationLogger.logResisted(for: habit, in: context)

        WidgetCenter.shared.reloadTimelines(ofKind: ResistorWidget.kind)
        return .result()
    }

    // MARK: - Debounce storage (App Group UserDefaults)

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: SharedModelContainer.appGroupID)
    }

    private static func debounceKey(_ habitID: String) -> String {
        "widget.lastFire.\(habitID)"
    }

    private static func isDebounced(habitID: String) -> Bool {
        guard let last = defaults?.object(forKey: debounceKey(habitID)) as? Double else {
            return false
        }
        return Date().timeIntervalSince1970 - last < debounceInterval
    }

    private static func recordFire(habitID: String) {
        defaults?.set(Date().timeIntervalSince1970, forKey: debounceKey(habitID))
    }
}
