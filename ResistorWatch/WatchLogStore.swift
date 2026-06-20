import Foundation
import SwiftData
import Observation

/// The resolved render state for the watch Quick-Log screen. Mirrors the UX
/// spec's states (a)/(d)/(e)/(f) — a loggable target with a known count, a
/// loggable target whose count read failed, no habit at all, or a configured
/// default that is no longer valid with no fallback.
enum WatchLogState: Equatable {
    /// (a)/(f) Loggable. A valid target habit is resolved and named. `count` is
    /// `nil` when the count read failed (render "Count unavailable", never a
    /// false 0); the button stays loggable either way.
    case loggable(habitID: UUID, name: String, colorHex: String?, iconName: String?, count: Int?)
    /// (d) No habit exists to log against.
    case noHabit
    /// (e) A default was set but is now archived/deleted and no other
    /// non-archived habit exists to fall back to.
    case habitUnavailable
}

/// The single data path for the watch Quick-Log screen. Owns the watch-side
/// `ModelContext`, resolves the target habit (default → else sole/first
/// non-archived habit, deterministic order), reads today's resisted count, and
/// performs the log via the shared `TemptationLogger`.
///
/// Kept as a small reusable provider (not inlined in the View) so a future
/// complication is just a new presentation over the same `state` /
/// `todayResistedCount(for:)` data path.
@Observable
final class WatchLogStore {

    /// The current render state. The View observes this.
    private(set) var state: WatchLogState = .noHabit

    /// `nil` when the watch store could not be opened (CloudKit/container
    /// failure). The View renders the count-unavailable branch when a target is
    /// otherwise known.
    private let modelContext: ModelContext?

    init() {
        if let container = try? WatchModelContainer.makeContainer() {
            self.modelContext = ModelContext(container)
        } else {
            self.modelContext = nil
        }
        refresh()
    }

    /// Recomputes `state` from the store: resolves the target habit and reads
    /// today's count.
    func refresh() {
        guard let context = modelContext else {
            // Store unavailable entirely — we can't even resolve a habit. Treat
            // as no-habit rather than inventing a target.
            state = .noHabit
            return
        }

        guard let habit = resolveTargetHabit(in: context) else {
            // Distinguish (e) from (d): if a default was configured but is gone
            // and there's truly nothing to fall back to, it's "habit
            // unavailable"; otherwise there simply is no habit yet.
            if hasConfiguredButMissingDefault(in: context) {
                state = .habitUnavailable
            } else {
                state = .noHabit
            }
            return
        }

        let count = todayResistedCount(for: habit, in: context)
        state = .loggable(
            habitID: habit.id,
            name: habit.name,
            colorHex: habit.colorHex,
            iconName: habit.iconName,
            count: count
        )
    }

    /// Logs one resisted temptation against the currently-resolved target habit,
    /// then refreshes the count. Returns `true` on a successful save.
    ///
    /// Writes to the local watch store immediately; CloudKit syncs to the phone
    /// whenever it can. Does NOT depend on WatchConnectivity reachability.
    @discardableResult
    func logResisted() -> Bool {
        guard let context = modelContext,
              case let .loggable(habitID, _, _, _, _) = state else {
            return false
        }
        let descriptor = FetchDescriptor<Habit>(
            predicate: #Predicate { $0.id == habitID }
        )
        guard let habit = try? context.fetch(descriptor).first else {
            return false
        }
        let event = TemptationLogger.logResisted(for: habit, in: context)
        refresh()
        return event != nil
    }

    // MARK: - Target resolution

    /// Resolves the target habit: `UserSettings.defaultHabitId` if it points at a
    /// live non-archived habit, else the sole/first non-archived habit in a
    /// deterministic order (by `createdAt`, then `id`). Returns `nil` only when
    /// no non-archived habit exists at all.
    private func resolveTargetHabit(in context: ModelContext) -> Habit? {
        let active = activeHabits(in: context)
        guard !active.isEmpty else { return nil }

        if let defaultID = defaultHabitId(in: context),
           let match = active.first(where: { $0.id == defaultID }) {
            return match
        }
        // Deterministic fallback so the watch always names a stable target.
        return active.first
    }

    /// All non-archived habits in a deterministic order.
    private func activeHabits(in context: ModelContext) -> [Habit] {
        let descriptor = FetchDescriptor<Habit>(
            predicate: #Predicate { !$0.isArchived },
            sortBy: [
                SortDescriptor(\Habit.createdAt, order: .forward),
                SortDescriptor(\Habit.id, order: .forward)
            ]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private func defaultHabitId(in context: ModelContext) -> UUID? {
        let descriptor = FetchDescriptor<UserSettings>()
        return (try? context.fetch(descriptor))?.first?.defaultHabitId
    }

    /// True when a default habit id was configured but no longer resolves to a
    /// live non-archived habit. Used to choose state (e) over (d).
    private func hasConfiguredButMissingDefault(in context: ModelContext) -> Bool {
        guard let defaultID = defaultHabitId(in: context) else { return false }
        return !activeHabits(in: context).contains { $0.id == defaultID }
    }

    // MARK: - Count

    /// Today's *resisted* event count for `habit`, using the same calendar-day
    /// definition as `Habit.todayEventsCount` (events in the current calendar
    /// day) but filtered to the resisted outcome only.
    func todayResistedCount(for habit: Habit, in context: ModelContext) -> Int? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        // Habit.safeEvents is the same source the phone counts from.
        return habit.safeEvents.filter { event in
            event.outcomeEnum == .resisted &&
            calendar.isDate(event.occurredAt, inSameDayAs: today)
        }.count
    }
}
