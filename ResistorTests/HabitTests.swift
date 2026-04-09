import XCTest
import SwiftData
@testable import Resistor

@MainActor
final class HabitTests: XCTestCase {

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

    // MARK: - Initialization

    func testHabitDefaultValues() {
        let habit = Habit()
        XCTAssertNotNil(habit.id)
        XCTAssertEqual(habit.name, "")
        XCTAssertNil(habit.habitDescription)
        XCTAssertNil(habit.colorHex)
        XCTAssertNil(habit.iconName)
        XCTAssertFalse(habit.isArchived)
        XCTAssertNotNil(habit.createdAt)
    }

    func testHabitCustomValues() {
        let date = Date.distantPast
        let habit = Habit(
            name: "Smoking",
            habitDescription: "Quit smoking",
            colorHex: "#FF3B30",
            iconName: "cigarette.fill",
            isArchived: true,
            createdAt: date
        )

        XCTAssertEqual(habit.name, "Smoking")
        XCTAssertEqual(habit.habitDescription, "Quit smoking")
        XCTAssertEqual(habit.colorHex, "#FF3B30")
        XCTAssertEqual(habit.iconName, "cigarette.fill")
        XCTAssertTrue(habit.isArchived)
        XCTAssertEqual(habit.createdAt, date)
    }

    // MARK: - Active Events Count

    func testActiveEventsCountWithNoEvents() throws {
        let habit = TestHelpers.makeHabit()
        context.insert(habit)
        try context.save()

        XCTAssertEqual(habit.activeEventsCount, 0)
    }

    func testActiveEventsCountWithEvents() throws {
        let habit = TestHelpers.makeHabit()
        context.insert(habit)

        let event1 = TestHelpers.makeEvent(habit: habit)
        let event2 = TestHelpers.makeEvent(habit: habit)
        context.insert(event1)
        context.insert(event2)
        try context.save()

        XCTAssertEqual(habit.activeEventsCount, 2)
    }

    // MARK: - Today Events Count

    func testTodayEventsCountIncludesTodayOnly() throws {
        let habit = TestHelpers.makeHabit()
        context.insert(habit)

        // Today event
        let todayEvent = TestHelpers.makeEvent(habit: habit, occurredAt: Date())
        context.insert(todayEvent)

        // Yesterday event
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let yesterdayEvent = TestHelpers.makeEvent(habit: habit, occurredAt: yesterday)
        context.insert(yesterdayEvent)

        try context.save()

        XCTAssertEqual(habit.todayEventsCount, 1)
    }

    func testTodayEventsCountZeroWhenNoTodayEvents() throws {
        let habit = TestHelpers.makeHabit()
        context.insert(habit)

        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let event = TestHelpers.makeEvent(habit: habit, occurredAt: yesterday)
        context.insert(event)
        try context.save()

        XCTAssertEqual(habit.todayEventsCount, 0)
    }

    // MARK: - This Week Events Count

    func testThisWeekEventsCountIncludesLast7Days() throws {
        let habit = TestHelpers.makeHabit()
        context.insert(habit)

        // Today
        let todayEvent = TestHelpers.makeEvent(habit: habit, occurredAt: Date())
        context.insert(todayEvent)

        // 5 days ago
        let fiveDaysAgo = Calendar.current.date(byAdding: .day, value: -5, to: Date())!
        let recentEvent = TestHelpers.makeEvent(habit: habit, occurredAt: fiveDaysAgo)
        context.insert(recentEvent)

        // 10 days ago — should NOT be included
        let tenDaysAgo = Calendar.current.date(byAdding: .day, value: -10, to: Date())!
        let oldEvent = TestHelpers.makeEvent(habit: habit, occurredAt: tenDaysAgo)
        context.insert(oldEvent)

        try context.save()

        XCTAssertEqual(habit.thisWeekEventsCount, 2)
    }

    func testThisWeekEventsCountZeroWhenNoRecentEvents() throws {
        let habit = TestHelpers.makeHabit()
        context.insert(habit)

        let longAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let event = TestHelpers.makeEvent(habit: habit, occurredAt: longAgo)
        context.insert(event)
        try context.save()

        XCTAssertEqual(habit.thisWeekEventsCount, 0)
    }

    // MARK: - Events Relationship

    func testEventsRelationshipInitiallyEmpty() throws {
        let habit = TestHelpers.makeHabit()
        context.insert(habit)
        try context.save()

        XCTAssertTrue(habit.events.isEmpty)
    }

    func testEventsRelationshipLinksCorrectly() throws {
        let habit1 = TestHelpers.makeHabit(name: "Habit1")
        let habit2 = TestHelpers.makeHabit(name: "Habit2")
        context.insert(habit1)
        context.insert(habit2)

        let event1 = TestHelpers.makeEvent(habit: habit1)
        let event2 = TestHelpers.makeEvent(habit: habit1)
        let event3 = TestHelpers.makeEvent(habit: habit2)
        context.insert(event1)
        context.insert(event2)
        context.insert(event3)
        try context.save()

        XCTAssertEqual(habit1.events.count, 2)
        XCTAssertEqual(habit2.events.count, 1)
    }
}
