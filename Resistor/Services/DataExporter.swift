import Foundation

enum DataExporter {

    /// Build export JSON from habits and events. Pure function for testability.
    static func exportJSON(habits: [Habit], events: [TemptationEvent], exportDate: Date = Date()) throws -> Data {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let habitsJSON: [[String: Any]] = habits.map { habit in
            var dict: [String: Any] = [
                "id": habit.id.uuidString,
                "name": habit.name,
                "is_archived": habit.isArchived,
                "created_at": formatter.string(from: habit.createdAt)
            ]
            dict["description"] = habit.habitDescription ?? NSNull()
            dict["color_hex"] = habit.colorHex ?? NSNull()
            dict["icon_name"] = habit.iconName ?? NSNull()
            return dict
        }

        let eventsJSON: [[String: Any]] = events.map { event in
            var dict: [String: Any] = [
                "id": event.id.uuidString,
                "occurred_at": formatter.string(from: event.occurredAt),
                "outcome": event.outcome,
                "context_tags": event.contextTags
            ]
            dict["habit_id"] = event.habit?.id.uuidString ?? NSNull()
            dict["intensity"] = event.intensity ?? NSNull()
            dict["note"] = event.note ?? NSNull()
            dict["latitude"] = event.latitude ?? NSNull()
            dict["longitude"] = event.longitude ?? NSNull()
            dict["location_name"] = event.locationName ?? NSNull()
            return dict
        }

        let exportData: [String: Any] = [
            "exported_at": formatter.string(from: exportDate),
            "habits": habitsJSON,
            "events": eventsJSON
        ]

        return try JSONSerialization.data(withJSONObject: exportData, options: [.prettyPrinted, .sortedKeys])
    }

    /// Write export data to a temporary file and return the URL.
    static func writeToTempFile(_ data: Data) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("resistor-export.json")
        try data.write(to: fileURL)
        return fileURL
    }
}
