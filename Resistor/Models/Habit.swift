import Foundation
import SwiftData

@Model
final class Habit {
    @Attribute(.unique) var id: UUID
    var name: String
    var habitDescription: String?
    var colorHex: String?
    var iconName: String?
    var isArchived: Bool
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \TemptationEvent.habit)
    var events: [TemptationEvent] = []

    init(
        id: UUID = UUID(),
        name: String,
        habitDescription: String? = nil,
        colorHex: String? = nil,
        iconName: String? = nil,
        isArchived: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.habitDescription = habitDescription
        self.colorHex = colorHex
        self.iconName = iconName
        self.isArchived = isArchived
        self.createdAt = createdAt
    }
}

extension Habit {
    var activeEventsCount: Int {
        events.count
    }

    var todayEventsCount: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return events.filter { calendar.isDate($0.occurredAt, inSameDayAs: today) }.count
    }

    var thisWeekEventsCount: Int {
        let calendar = Calendar.current
        guard let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date()) else { return 0 }
        return events.filter { $0.occurredAt >= weekAgo }.count
    }
}
