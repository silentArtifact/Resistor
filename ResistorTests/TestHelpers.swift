import XCTest
import SwiftData
import Foundation
@testable import Resistor

enum TestHelpers {
    @MainActor
    static func makeModelContainer() throws -> ModelContainer {
        let schema = Schema([Habit.self, TemptationEvent.self, UserSettings.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    static func makeHabit(
        name: String = "Test Habit",
        habitDescription: String? = nil,
        colorHex: String? = "#007AFF",
        iconName: String? = "circle.fill",
        isArchived: Bool = false,
        createdAt: Date = Date()
    ) -> Habit {
        Habit(
            name: name,
            habitDescription: habitDescription,
            colorHex: colorHex,
            iconName: iconName,
            isArchived: isArchived,
            createdAt: createdAt
        )
    }

    static func makeEvent(
        habit: Habit,
        occurredAt: Date = Date(),
        intensity: Int? = nil,
        outcome: String = "unknown",
        contextTags: [String] = [],
        note: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        locationName: String? = nil
    ) -> TemptationEvent {
        TemptationEvent(
            habit: habit,
            occurredAt: occurredAt,
            intensity: intensity,
            outcome: outcome,
            contextTags: contextTags,
            note: note,
            latitude: latitude,
            longitude: longitude,
            locationName: locationName
        )
    }

    static func dateFromComponents(
        year: Int = 2025,
        month: Int = 1,
        day: Int = 15,
        hour: Int = 12,
        minute: Int = 0,
        second: Int = 0
    ) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        return Calendar.current.date(from: components)!
    }
}
