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

    // MARK: - Today Events Count Edge Cases

    func testTodayEventsCountWithMultipleEventsAtDifferentTimes() throws {
        let habit = TestHelpers.makeHabit()
        context.insert(habit)

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Early morning
        let morningDate = calendar.date(byAdding: .hour, value: 6, to: today)!
        let morningEvent = TestHelpers.makeEvent(habit: habit, occurredAt: morningDate)
        context.insert(morningEvent)

        // Midday
        let middayDate = calendar.date(byAdding: .hour, value: 12, to: today)!
        let middayEvent = TestHelpers.makeEvent(habit: habit, occurredAt: middayDate)
        context.insert(middayEvent)

        // Late evening
        let eveningDate = calendar.date(byAdding: .hour, value: 23, to: today)!
        let eveningEvent = TestHelpers.makeEvent(habit: habit, occurredAt: eveningDate)
        context.insert(eveningEvent)

        try context.save()

        XCTAssertEqual(habit.todayEventsCount, 3)
    }

    // MARK: - This Week Events Boundary

    func testThisWeekEventsCountBoundaryAtExactly7DaysAgo() throws {
        let habit = TestHelpers.makeHabit()
        context.insert(habit)

        let calendar = Calendar.current
        let now = Date()

        // Event exactly 7 days ago from `now`. The implementation uses >= with
        // its own Date() call, so tiny timing differences make inclusion non-deterministic.
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: now)!
        let boundaryEvent = TestHelpers.makeEvent(habit: habit, occurredAt: sevenDaysAgo)
        context.insert(boundaryEvent)

        // Event 6 days and 23 hours ago (well within range, always included)
        let almostSevenDaysAgo = calendar.date(byAdding: .hour, value: -(7 * 24 - 1), to: now)!
        let recentEvent = TestHelpers.makeEvent(habit: habit, occurredAt: almostSevenDaysAgo)
        context.insert(recentEvent)

        try context.save()

        // The boundary event may or may not be included due to the race between
        // `now` captured above and `Date()` inside thisWeekEventsCount.
        // This test documents the behavior rather than enforcing a specific count.
        let count = habit.thisWeekEventsCount
        XCTAssertTrue(count >= 1 && count <= 2,
                      "Expected 1 or 2 events at the 7-day boundary, got \(count)")
    }

    func testTodayEventsCountAtMidnightBoundary() throws {
        let habit = TestHelpers.makeHabit()
        context.insert(habit)

        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())

        // Event at exact start of today (midnight)
        let midnightEvent = TestHelpers.makeEvent(habit: habit, occurredAt: startOfToday)
        context.insert(midnightEvent)

        // Event 1 second before midnight (yesterday)
        let justBeforeMidnight = startOfToday.addingTimeInterval(-1)
        let yesterdayEvent = TestHelpers.makeEvent(habit: habit, occurredAt: justBeforeMidnight)
        context.insert(yesterdayEvent)

        try context.save()

        XCTAssertEqual(habit.todayEventsCount, 1)
    }

    // MARK: - Events Relationship

    func testEventsRelationshipInitiallyEmpty() throws {
        let habit = TestHelpers.makeHabit()
        context.insert(habit)
        try context.save()

        XCTAssertTrue(habit.safeEvents.isEmpty)
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

        XCTAssertEqual(habit1.safeEvents.count, 2)
        XCTAssertEqual(habit2.safeEvents.count, 1)
    }
}
