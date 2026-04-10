import XCTest
import SwiftData
@testable import Resistor

@MainActor
final class DataExporterTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        container = try TestHelpers.makeModelContainer()
        context = container.mainContext
    }

    override func tearDown() async throws {
        container = nil
        context = nil
    }

    // MARK: - Empty Data

    func testExportEmptyDataProducesValidJSON() throws {
        let data = try DataExporter.exportJSON(habits: [], events: [])
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertNotNil(json["exported_at"])
        XCTAssertEqual((json["habits"] as? [[String: Any]])?.count, 0)
        XCTAssertEqual((json["events"] as? [[String: Any]])?.count, 0)
    }

    // MARK: - Habit Export

    func testExportHabitIncludesAllFields() throws {
        let habit = TestHelpers.makeHabit(
            name: "Sugar",
            habitDescription: "Avoid sweets",
            colorHex: "#FF3B30",
            iconName: "flame.fill"
        )
        context.insert(habit)
        try context.save()

        let data = try DataExporter.exportJSON(habits: [habit], events: [])
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let habits = json["habits"] as! [[String: Any]]

        XCTAssertEqual(habits.count, 1)
        let h = habits[0]
        XCTAssertEqual(h["name"] as? String, "Sugar")
        XCTAssertEqual(h["description"] as? String, "Avoid sweets")
        XCTAssertEqual(h["color_hex"] as? String, "#FF3B30")
        XCTAssertEqual(h["icon_name"] as? String, "flame.fill")
        XCTAssertEqual(h["is_archived"] as? Bool, false)
        XCTAssertNotNil(h["id"])
        XCTAssertNotNil(h["created_at"])
    }

    func testExportHabitWithNilOptionalFields() throws {
        let habit = TestHelpers.makeHabit(
            name: "Minimal",
            habitDescription: nil,
            colorHex: nil,
            iconName: nil
        )
        context.insert(habit)
        try context.save()

        let data = try DataExporter.exportJSON(habits: [habit], events: [])
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let habits = json["habits"] as! [[String: Any]]
        let h = habits[0]

        XCTAssertEqual(h["name"] as? String, "Minimal")
        XCTAssertTrue(h["description"] is NSNull)
        XCTAssertTrue(h["color_hex"] is NSNull)
        XCTAssertTrue(h["icon_name"] is NSNull)
    }

    func testExportArchivedHabit() throws {
        let habit = TestHelpers.makeHabit(name: "Old", isArchived: true)
        context.insert(habit)
        try context.save()

        let data = try DataExporter.exportJSON(habits: [habit], events: [])
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let habits = json["habits"] as! [[String: Any]]

        XCTAssertEqual(habits[0]["is_archived"] as? Bool, true)
    }

    // MARK: - Event Export

    func testExportEventIncludesAllFields() throws {
        let habit = TestHelpers.makeHabit(name: "Test")
        context.insert(habit)
        try context.save()

        let event = TestHelpers.makeEvent(
            habit: habit,
            intensity: 4,
            outcome: "resisted",
            contextTags: ["stressed", "at_home"],
            note: "Felt strong"
        )
        context.insert(event)
        try context.save()

        let data = try DataExporter.exportJSON(habits: [habit], events: [event])
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let events = json["events"] as! [[String: Any]]

        XCTAssertEqual(events.count, 1)
        let e = events[0]
        XCTAssertEqual(e["outcome"] as? String, "resisted")
        XCTAssertEqual(e["intensity"] as? Int, 4)
        XCTAssertEqual(e["note"] as? String, "Felt strong")
        XCTAssertEqual(e["context_tags"] as? [String], ["stressed", "at_home"])
        XCTAssertEqual(e["habit_id"] as? String, habit.id.uuidString)
        XCTAssertNotNil(e["id"])
        XCTAssertNotNil(e["occurred_at"])
    }

    func testExportEventWithNilOptionalFields() throws {
        let habit = TestHelpers.makeHabit(name: "Test")
        context.insert(habit)
        try context.save()

        let event = TestHelpers.makeEvent(habit: habit)
        context.insert(event)
        try context.save()

        let data = try DataExporter.exportJSON(habits: [habit], events: [event])
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let events = json["events"] as! [[String: Any]]
        let e = events[0]

        XCTAssertTrue(e["intensity"] is NSNull)
        XCTAssertTrue(e["note"] is NSNull)
        XCTAssertEqual(e["outcome"] as? String, "unknown")
        XCTAssertEqual(e["context_tags"] as? [String], [])
    }

    // MARK: - Multiple Items

    func testExportMultipleHabitsAndEvents() throws {
        let habit1 = TestHelpers.makeHabit(name: "Sugar")
        let habit2 = TestHelpers.makeHabit(name: "Smoking")
        context.insert(habit1)
        context.insert(habit2)
        try context.save()

        let event1 = TestHelpers.makeEvent(habit: habit1, outcome: "resisted")
        let event2 = TestHelpers.makeEvent(habit: habit1, outcome: "gave_in")
        let event3 = TestHelpers.makeEvent(habit: habit2, outcome: "unknown")
        context.insert(event1)
        context.insert(event2)
        context.insert(event3)
        try context.save()

        let data = try DataExporter.exportJSON(
            habits: [habit1, habit2],
            events: [event1, event2, event3]
        )
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual((json["habits"] as? [[String: Any]])?.count, 2)
        XCTAssertEqual((json["events"] as? [[String: Any]])?.count, 3)
    }

    // MARK: - Export Date

    func testExportDateIsISO8601() throws {
        let fixedDate = TestHelpers.dateFromComponents(year: 2026, month: 4, day: 10, hour: 12)
        let data = try DataExporter.exportJSON(habits: [], events: [], exportDate: fixedDate)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let exportedAt = json["exported_at"] as! String

        XCTAssertTrue(exportedAt.contains("2026-04-10"))
    }

    // MARK: - Special Characters

    func testExportHandlesSpecialCharactersInNote() throws {
        let habit = TestHelpers.makeHabit(name: "Test \"Quotes\"")
        context.insert(habit)
        try context.save()

        let event = TestHelpers.makeEvent(
            habit: habit,
            note: "Line1\nLine2\tTabbed \"quoted\" emoji: 🎉"
        )
        context.insert(event)
        try context.save()

        let data = try DataExporter.exportJSON(habits: [habit], events: [event])

        // Should produce valid JSON
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let events = json["events"] as! [[String: Any]]
        XCTAssertEqual(events[0]["note"] as? String, "Line1\nLine2\tTabbed \"quoted\" emoji: 🎉")

        let habits = json["habits"] as! [[String: Any]]
        XCTAssertEqual(habits[0]["name"] as? String, "Test \"Quotes\"")
    }

    // MARK: - File Write

    func testWriteToTempFileCreatesFile() throws {
        let data = try DataExporter.exportJSON(habits: [], events: [])
        let url = try DataExporter.writeToTempFile(data)

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        let readBack = try Data(contentsOf: url)
        XCTAssertEqual(readBack, data)

        // Clean up
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - UUID Stability

    func testExportedHabitIdMatchesModel() throws {
        let habit = TestHelpers.makeHabit(name: "Test")
        context.insert(habit)
        try context.save()

        let data = try DataExporter.exportJSON(habits: [habit], events: [])
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let habits = json["habits"] as! [[String: Any]]

        XCTAssertEqual(habits[0]["id"] as? String, habit.id.uuidString)
    }

    // MARK: - Location Export

    func testExportEventWithLocationIncludesCoordinates() throws {
        let habit = TestHelpers.makeHabit(name: "Test")
        context.insert(habit)
        try context.save()

        let event = TestHelpers.makeEvent(
            habit: habit,
            outcome: "resisted",
            latitude: 40.7128,
            longitude: -74.0060,
            locationName: "Downtown, New York"
        )
        context.insert(event)
        try context.save()

        let data = try DataExporter.exportJSON(habits: [habit], events: [event])
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let events = json["events"] as! [[String: Any]]
        let e = events[0]

        XCTAssertEqual(e["latitude"] as? Double, 40.7128, accuracy: 0.0001)
        XCTAssertEqual(e["longitude"] as? Double, -74.0060, accuracy: 0.0001)
        XCTAssertEqual(e["location_name"] as? String, "Downtown, New York")
    }

    func testExportEventWithNilLocationHasNulls() throws {
        let habit = TestHelpers.makeHabit(name: "Test")
        context.insert(habit)
        try context.save()

        let event = TestHelpers.makeEvent(habit: habit)
        context.insert(event)
        try context.save()

        let data = try DataExporter.exportJSON(habits: [habit], events: [event])
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let events = json["events"] as! [[String: Any]]
        let e = events[0]

        XCTAssertTrue(e["latitude"] is NSNull)
        XCTAssertTrue(e["longitude"] is NSNull)
        XCTAssertTrue(e["location_name"] is NSNull)
    }
}
