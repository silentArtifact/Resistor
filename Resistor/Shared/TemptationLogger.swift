import Foundation
import SwiftData

/// Single source of truth for creating a "resisted" temptation event. Shared by
/// the app's `LogViewModel` and the widget's `LogResistedIntent` so both write
/// an identical event (occurredAt = now, intensity = nil, outcome = "resisted",
/// the given context tags) instead of duplicating the construction.
enum TemptationLogger {

    /// Builds, inserts, and saves a resisted `TemptationEvent` for `habit`.
    /// - Returns: the saved event on success, or `nil` if the save failed (the
    ///   failed insert is discarded so no stale, unsaved event lingers).
    @discardableResult
    static func logResisted(
        for habit: Habit,
        in context: ModelContext,
        contextTags: [String] = [],
        occurredAt: Date = Date()
    ) -> TemptationEvent? {
        let event = TemptationEvent(
            habit: habit,
            occurredAt: occurredAt,
            intensity: nil,
            outcome: TemptationEvent.Outcome.resisted.rawValue,
            contextTags: contextTags
        )
        context.insert(event)

        do {
            try context.save()
            return event
        } catch {
            print("Failed to save resisted temptation event: \(error)")
            context.delete(event)
            return nil
        }
    }
}
