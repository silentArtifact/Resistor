import Foundation
import CoreData
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

    /// Every non-archived habit, in the phone's display order — the options the
    /// picker offers. Empty when the store couldn't be opened.
    private(set) var habitOptions: [Habit] = []

    /// The habit picked on the watch this session, if any. Deliberately in
    /// memory only: the phone's Log screen also opens on the default habit
    /// every launch, so persisting a watch-local override would make the two
    /// devices disagree about what "the" habit is. Cleared on relaunch.
    private var selectedHabitID: UUID?

    /// `nil` when the watch store could not be opened (CloudKit/container
    /// failure). The View renders the count-unavailable branch when a target is
    /// otherwise known.
    private let modelContext: ModelContext?

    /// Owned rather than injected: the watch has exactly one caller and no test
    /// target on this checkout. Same `LocationProviding` the phone uses.
    private let locationManager = LocationManager()

    private var remoteChangeObserver: NSObjectProtocol?

    init() {
        if let container = try? WatchModelContainer.makeContainer() {
            self.modelContext = ModelContext(container)
        } else {
            self.modelContext = nil
        }
        refresh()

        // A drag on the phone's Habits screen rewrites every `sortOrder` and
        // reaches the watch as a CloudKit import, which lands in the store
        // silently. Without this the pager keeps rendering the order it fetched
        // at launch until the next resume — the user reorders on the phone,
        // looks at the wrist, and sees the old order.
        remoteChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
    }

    deinit {
        if let remoteChangeObserver {
            NotificationCenter.default.removeObserver(remoteChangeObserver)
        }
    }

    /// Asks for when-in-use location once, so a wrist log can carry a fix like a
    /// phone log does. No-op after the user has answered either way.
    func requestLocationPermissionIfNeeded() {
        guard locationManager.authorizationStatus == .notDetermined else { return }
        locationManager.requestPermission()
    }

    /// Switches which habit the button logs against. The choice sticks until the
    /// app is relaunched or the habit stops being loggable.
    func select(habitID: UUID) {
        selectedHabitID = habitID
        refresh()
    }

    /// Recomputes `state` from the store: resolves the target habit and reads
    /// today's count.
    func refresh() {
        guard let context = modelContext else {
            // Store unavailable entirely — we can't even resolve a habit. Treat
            // as no-habit rather than inventing a target.
            habitOptions = []
            state = .noHabit
            return
        }

        let active = activeHabits(in: context)
        habitOptions = active

        guard let habit = resolveTargetHabit(among: active, in: context) else {
            // Distinguish (e) from (d): if a default was configured but is gone
            // and there's truly nothing to fall back to, it's "habit
            // unavailable"; otherwise there simply is no habit yet.
            if let defaultID = defaultHabitId(in: context), !active.contains(where: { $0.id == defaultID }) {
                state = .habitUnavailable
            } else {
                state = .noHabit
            }
            return
        }

        let count = todayResistedCount(for: habit)
        state = .loggable(
            habitID: habit.id,
            name: habit.name,
            colorHex: habit.colorHex,
            iconName: habit.iconName,
            count: count
        )
    }

    /// The most recent event this store logged, retained so shake-to-undo has
    /// something to delete. Cleared once undone. Mirrors the phone
    /// `LogViewModel.lastLoggedEvent`/`undoLastLog` pair.
    private(set) var lastLoggedEvent: TemptationEvent?

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
        // Only a genuinely saved event is undoable — `logResisted` discards its
        // insert on failure, so a nil here must not leave a stale target behind.
        lastLoggedEvent = event

        // Same fire-and-forget stamp the phone applies, so a wrist log shows up
        // on the map and in Top Locations too. `attachLocation` drops the write
        // if a shake undid the event while the fix was in flight.
        if let event {
            Task { @MainActor in
                await locationManager.attachLocation(to: event, in: context)
            }
        }

        refresh()
        return event != nil
    }

    /// Deletes the event most recently logged from this watch, then refreshes the
    /// count. Returns `true` only if something was actually removed, so the
    /// caller doesn't acknowledge an undo that didn't happen.
    ///
    /// The delete propagates to the phone the same way the insert does — via
    /// CloudKit — so an undone log doesn't reappear there.
    @discardableResult
    func undoLast() -> Bool {
        guard let context = modelContext, let event = lastLoggedEvent else {
            return false
        }
        context.delete(event)
        do {
            try context.save()
        } catch {
            print("Failed to undo watch temptation event: \(error)")
            return false
        }
        lastLoggedEvent = nil
        refresh()
        return true
    }

    // MARK: - Target resolution

    /// Resolves the target habit: whatever was picked on the watch this session
    /// if it's still live, else `UserSettings.defaultHabitId` if that points at a
    /// live non-archived habit, else the first non-archived habit in display
    /// order. Returns `nil` only when no non-archived habit exists at all.
    private func resolveTargetHabit(among active: [Habit], in context: ModelContext) -> Habit? {
        guard !active.isEmpty else { return nil }

        if let selectedHabitID,
           let picked = active.first(where: { $0.id == selectedHabitID }) {
            return picked
        }

        if let defaultID = defaultHabitId(in: context),
           let match = active.first(where: { $0.id == defaultID }) {
            return match
        }
        // Deterministic fallback so the watch always names a stable target.
        return active.first
    }

    /// All non-archived habits in the phone's display order, so the picker and
    /// the fallback target agree with the Log carousel.
    private func activeHabits(in context: ModelContext) -> [Habit] {
        let descriptor = FetchDescriptor<Habit>(
            predicate: #Predicate { !$0.isArchived },
            sortBy: Habit.displayOrder
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private func defaultHabitId(in context: ModelContext) -> UUID? {
        let descriptor = FetchDescriptor<UserSettings>()
        return (try? context.fetch(descriptor))?.first?.defaultHabitId
    }

    // MARK: - Count

    /// Today's *resisted* event count for `habit`, using the same calendar-day
    /// definition as `Habit.todayEventsCount` (events in the current calendar
    /// day) but filtered to the resisted outcome only.
    func todayResistedCount(for habit: Habit) -> Int? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        // Habit.safeEvents is the same source the phone counts from.
        return habit.safeEvents.filter { event in
            event.outcomeEnum == .resisted &&
            calendar.isDate(event.occurredAt, inSameDayAs: today)
        }.count
    }
}
