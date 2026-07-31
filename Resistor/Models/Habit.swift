import Foundation
import SwiftData

@Model
final class Habit {
    var id: UUID = UUID()
    var name: String = ""
    var habitDescription: String?
    var colorHex: String?
    var iconName: String?
    var isArchived: Bool = false
    var createdAt: Date = Date()
    /// User-chosen display position. Additive with a default of 0 so existing
    /// CloudKit records migrate cleanly — until something is dragged, every
    /// habit is 0 and `displayOrder` falls through to `createdAt`, which is the
    /// ordering the app had before.
    var sortOrder: Int = 0

    @Relationship(inverse: \TemptationEvent.habit)
    var events: [TemptationEvent]? = []

    init(
        id: UUID = UUID(),
        name: String = "",
        habitDescription: String? = nil,
        colorHex: String? = nil,
        iconName: String? = nil,
        isArchived: Bool = false,
        createdAt: Date = Date(),
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.habitDescription = habitDescription
        self.colorHex = colorHex
        self.iconName = iconName
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.sortOrder = sortOrder
    }
}

extension Habit {
    /// The one habit ordering in the product. Every list the user sees — the Log
    /// carousel, the Habits screen, the widget's picker, the watch — sorts by
    /// this, so dragging a habit on the phone moves it everywhere. `createdAt`
    /// and `id` are the tiebreaks that keep the order stable and deterministic
    /// when `sortOrder` ties (which it does for every habit until a first drag).
    static let displayOrder: [SortDescriptor<Habit>] = [
        SortDescriptor(\Habit.sortOrder, order: .forward),
        SortDescriptor(\Habit.createdAt, order: .forward),
        SortDescriptor(\Habit.id, order: .forward)
    ]

    /// The `sortOrder` a newly created habit should take so it lands at the end
    /// of the list rather than jumping to the top of a reordered one.
    static func nextSortOrder(in context: ModelContext) -> Int {
        var descriptor = FetchDescriptor<Habit>(
            sortBy: [SortDescriptor(\Habit.sortOrder, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return ((try? context.fetch(descriptor))?.first?.sortOrder ?? -1) + 1
    }

    var safeEvents: [TemptationEvent] {
        events ?? []
    }

    var activeEventsCount: Int {
        safeEvents.count
    }

    var todayEventsCount: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return safeEvents.filter { calendar.isDate($0.occurredAt, inSameDayAs: today) }.count
    }

    var thisWeekEventsCount: Int {
        let calendar = Calendar.current
        guard let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date()) else { return 0 }
        return safeEvents.filter { $0.occurredAt >= weekAgo }.count
    }
}
