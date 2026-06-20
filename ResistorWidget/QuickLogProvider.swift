import WidgetKit
import SwiftData
import Foundation

/// The four mutually-exclusive states the widget can render. Mirrors the UX
/// spec: configured (loggable), unconfigured, needs-reconfiguration, and
/// store-unavailable.
enum QuickLogState {
    /// Configured and at rest. Habit identity resolved and today's count read.
    case configured(habitID: UUID, name: String, colorHex: String?, iconName: String?, count: Int)
    /// No habit chosen in Edit Widget yet.
    case unconfigured
    /// A habit was chosen but is now archived or deleted.
    case needsReconfiguration
    /// Habit identity is known but the count read failed (store unavailable).
    /// Keeps the Button so a tap still enqueues a write that persists later.
    case storeUnavailable(habitID: UUID, name: String, colorHex: String?, iconName: String?)
}

/// Timeline entry carrying the resolved render state.
struct QuickLogEntry: TimelineEntry {
    let date: Date
    let state: QuickLogState
}

struct QuickLogProvider: AppIntentTimelineProvider {
    typealias Intent = SelectHabitIntent
    typealias Entry = QuickLogEntry

    func placeholder(in context: Context) -> QuickLogEntry {
        QuickLogEntry(date: Date(), state: .unconfigured)
    }

    func snapshot(for configuration: SelectHabitIntent, in context: Context) async -> QuickLogEntry {
        await entry(for: configuration)
    }

    func timeline(for configuration: SelectHabitIntent, in context: Context) async -> Timeline<QuickLogEntry> {
        let entry = await entry(for: configuration)
        // Refresh at the next calendar-day boundary so "today's count" resets,
        // plus interactive taps reload via WidgetCenter on each log.
        let nextMidnight = Calendar.current.nextDate(
            after: Date(),
            matching: DateComponents(hour: 0, minute: 0, second: 5),
            matchingPolicy: .nextTime
        ) ?? Date().addingTimeInterval(3600)
        return Timeline(entries: [entry], policy: .after(nextMidnight))
    }

    @MainActor
    private func entry(for configuration: SelectHabitIntent) -> QuickLogEntry {
        let now = Date()

        // (b) Unconfigured — no habit chosen.
        guard let selected = configuration.habit else {
            return QuickLogEntry(date: now, state: .unconfigured)
        }

        // Try to open the shared store.
        guard let container = try? SharedModelContainer.makeContainer() else {
            // Identity is known but we can't read the store. (d) store-unavailable.
            return QuickLogEntry(
                date: now,
                state: .storeUnavailable(
                    habitID: selected.id,
                    name: selected.name,
                    colorHex: selected.colorHex,
                    iconName: selected.iconName
                )
            )
        }

        let context = container.mainContext
        let id = selected.id
        let descriptor = FetchDescriptor<Habit>(
            predicate: #Predicate { habit in
                habit.id == id && !habit.isArchived
            }
        )

        do {
            guard let habit = try context.fetch(descriptor).first else {
                // (c) Bound habit archived or deleted.
                return QuickLogEntry(date: now, state: .needsReconfiguration)
            }
            // (a) Configured/at-rest. Count today's events the same way the app
            // does (Habit.todayEventsCount: events in the current calendar day).
            return QuickLogEntry(
                date: now,
                state: .configured(
                    habitID: habit.id,
                    name: habit.name,
                    colorHex: habit.colorHex,
                    iconName: habit.iconName,
                    count: habit.todayEventsCount
                )
            )
        } catch {
            // Read failed but identity is known → (d) store-unavailable.
            return QuickLogEntry(
                date: now,
                state: .storeUnavailable(
                    habitID: selected.id,
                    name: selected.name,
                    colorHex: selected.colorHex,
                    iconName: selected.iconName
                )
            )
        }
    }
}
