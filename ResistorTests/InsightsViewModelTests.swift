import XCTest
import SwiftData
@testable import Resistor

@MainActor
final class InsightsViewModelTests: XCTestCase {

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

    func testInitFetchesActiveHabitsOnly() throws {
        let active = TestHelpers.makeHabit(name: "Active")
        let archived = TestHelpers.makeHabit(name: "Archived", isArchived: true)
        context.insert(active)
        context.insert(archived)
        try context.save()

        let vm = InsightsViewModel(modelContext: context)

        XCTAssertEqual(vm.habits.count, 1)
        XCTAssertEqual(vm.habits.first?.name, "Active")
    }

    func testSelectedHabitNilWhenNoHabits() throws {
        let vm = InsightsViewModel(modelContext: context)
        XCTAssertNil(vm.selectedHabit)
    }

    func testHasDataFalseWhenNoEvents() throws {
        let habit = TestHelpers.makeHabit()
        context.insert(habit)
        try context.save()

        let vm = InsightsViewModel(modelContext: context)
        XCTAssertFalse(vm.hasData)
    }

    func testHasDataTrueWhenEventsExist() throws {
        let habit = TestHelpers.makeHabit()
        context.insert(habit)
        let event = TestHelpers.makeEvent(habit: habit)
        context.insert(event)
        try context.save()

        let vm = InsightsViewModel(modelContext: context)
        XCTAssertTrue(vm.hasData)
    }

    // MARK: - Events In Range

    func testEventsInRangeWeekFiltersCorrectly() throws {
        let habit = TestHelpers.makeHabit()
        context.insert(habit)

        let now = Date()
        let calendar = Calendar.current

        // Event today — should be in range
        let todayEvent = TestHelpers.makeEvent(habit: habit, occurredAt: now, outcome: "resisted")
        context.insert(todayEvent)

        // Event 3 days ago — should be in range
        let threeDaysAgo = calendar.date(byAdding: .day, value: -3, to: now)!
        let recentEvent = TestHelpers.makeEvent(habit: habit, occurredAt: threeDaysAgo, outcome: "resisted")
        context.insert(recentEvent)

        // Event 10 days ago — should NOT be in 7-day range
        let tenDaysAgo = calendar.date(byAdding: .day, value: -10, to: now)!
        let oldEvent = TestHelpers.makeEvent(habit: habit, occurredAt: tenDaysAgo, outcome: "resisted")
        context.insert(oldEvent)

        try context.save()

        let vm = InsightsViewModel(modelContext: context)
        vm.selectedTimeRange = .week

        let events = vm.eventsInRange()
        XCTAssertEqual(events.count, 2)
    }

    func testEventsInRangeMonthFiltersCorrectly() throws {
        let habit = TestHelpers.makeHabit()
        context.insert(habit)

        let now = Date()
        let calendar = Calendar.current

        // Event today
        let todayEvent = TestHelpers.makeEvent(habit: habit, occurredAt: now, outcome: "resisted")
        context.insert(todayEvent)

        // Event 20 days ago — in 30-day range
        let twentyDaysAgo = calendar.date(byAdding: .day, value: -20, to: now)!
        let midEvent = TestHelpers.makeEvent(habit: habit, occurredAt: twentyDaysAgo, outcome: "gave_in")
        context.insert(midEvent)

        // Event 35 days ago — NOT in 30-day range
        let thirtyFiveDaysAgo = calendar.date(byAdding: .day, value: -35, to: now)!
        let oldEvent = TestHelpers.makeEvent(habit: habit, occurredAt: thirtyFiveDaysAgo, outcome: "resisted")
        context.insert(oldEvent)

        try context.save()

        let vm = InsightsViewModel(modelContext: context)
        vm.selectedTimeRange = .month

        let events = vm.eventsInRange()
        XCTAssertEqual(events.count, 2)
    }

    func testEventsInRangeReturnsEmptyWhenNoHabit() throws {
        let vm = InsightsViewModel(modelContext: context)
        XCTAssertEqual(vm.eventsInRange().count, 0)
    }

    // MARK: - Period Comparison

    func testPreviousPeriodEventsCountsCorrectRange() throws {
        let habit = TestHelpers.makeHabit()
        context.insert(habit)

        let calendar = Calendar.current
        let now = Date()

        // Event 10 days ago — in previous 7-day period (days 7-13 ago)
        let tenDaysAgo = calendar.date(byAdding: .day, value: -10, to: now)!
        let prevEvent = TestHelpers.makeEvent(habit: habit, occurredAt: tenDaysAgo, outcome: "resisted")
        context.insert(prevEvent)

        // Event today — in current period
        let todayEvent = TestHelpers.makeEvent(habit: habit, occurredAt: now, outcome: "resisted")
        context.insert(todayEvent)

        try context.save()

        let vm = InsightsViewModel(modelContext: context)
        vm.selectedTimeRange = .week

        XCTAssertEqual(vm.totalEventsInRange, 1)
        XCTAssertEqual(vm.previousPeriodEvents, 1)
        XCTAssertEqual(vm.changeFromPreviousPeriod, 0)
    }

    func testChangePercentageNilWhenNoPreviousPeriod() throws {
        let habit = TestHelpers.makeHabit()
        context.insert(habit)

        let todayEvent = TestHelpers.makeEvent(habit: habit, occurredAt: Date(), outcome: "resisted")
        context.insert(todayEvent)
        try context.save()

        let vm = InsightsViewModel(modelContext: context)
        vm.selectedTimeRange = .week

        XCTAssertNil(vm.changePercentage)
    }

    func testChangePercentageCalculatesCorrectly() throws {
        let habit = TestHelpers.makeHabit()
        context.insert(habit)

        let calendar = Calendar.current
        let now = Date()

        // 2 events in current period
        for i in 0..<2 {
            let date = calendar.date(byAdding: .hour, value: -i, to: now)!
            let event = TestHelpers.makeEvent(habit: habit, occurredAt: date, outcome: "resisted")
            context.insert(event)
        }

        // 4 events in previous period
        for i in 0..<4 {
            let date = calendar.date(byAdding: .day, value: -(7 + i), to: now)!
            let event = TestHelpers.makeEvent(habit: habit, occurredAt: date, outcome: "resisted")
            context.insert(event)
        }

        try context.save()

        let vm = InsightsViewModel(modelContext: context)
        vm.selectedTimeRange = .week

        XCTAssertEqual(vm.totalEventsInRange, 2)
        XCTAssertEqual(vm.previousPeriodEvents, 4)
        XCTAssertEqual(vm.changeFromPreviousPeriod, -2)
        XCTAssertEqual(vm.changePercentage!, -50.0, accuracy: 0.01)
    }

    // MARK: - Daily Distribution

    func testDailyDistributionHasCorrectDayCount() throws {
        let habit = TestHelpers.makeHabit()
        context.insert(habit)
        try context.save()

        let vm = InsightsViewModel(modelContext: context)

        vm.selectedTimeRange = .week
        XCTAssertEqual(vm.dailyDistribution().count, 7)

        vm.selectedTimeRange = .month
        XCTAssertEqual(vm.dailyDistribution().count, 30)
    }

    func testDailyDistributionCountsEventsPerDay() throws {
        let habit = TestHelpers.makeHabit()
        context.insert(habit)

        let now = Date()
        // 3 events today
        for _ in 0..<3 {
            let event = TestHelpers.makeEvent(habit: habit, occurredAt: now, outcome: "resisted")
            context.insert(event)
        }
        try context.save()

        let vm = InsightsViewModel(modelContext: context)
        vm.selectedTimeRange = .week

        let dist = vm.dailyDistribution()
        let todayEntry = dist.last
        XCTAssertNotNil(todayEntry)
        XCTAssertEqual(todayEntry?.count, 3)
    }

    func testDailyDistributionZeroFillsEmptyDays() throws {
        let habit = TestHelpers.makeHabit()
        context.insert(habit)

        let event = TestHelpers.makeEvent(habit: habit, occurredAt: Date(), outcome: "resisted")
        context.insert(event)
        try context.save()

        let vm = InsightsViewModel(modelContext: context)
        vm.selectedTimeRange = .week

        let dist = vm.dailyDistribution()
        let zeroDays = dist.filter { $0.count == 0 }
        XCTAssertEqual(zeroDays.count, 6)
    }

    func testDailyDistributionSortedByDate() throws {
        let habit = TestHelpers.makeHabit()
        context.insert(habit)
        try context.save()

        let vm = InsightsViewModel(modelContext: context)
        let dist = vm.dailyDistribution()

        for i in 1..<dist.count {
            XCTAssertTrue(dist[i - 1].date <= dist[i].date)
        }
    }

    // MARK: - Time of Day Distribution

    func testTimeOfDayDistributionAllPeriodsPresent() throws {
        let habit = TestHelpers.makeHabit()
        context.insert(habit)
        try context.save()

        let vm = InsightsViewModel(modelContext: context)
        let dist = vm.timeOfDayDistribution()

        XCTAssertEqual(dist.count, 4)
        XCTAssertEqual(dist[0].period, "Morning")
        XCTAssertEqual(dist[1].period, "Afternoon")
        XCTAssertEqual(dist[2].period, "Evening")
        XCTAssertEqual(dist[3].period, "Night")
    }

    func testTimeOfDayDistributionClassifiesCorrectly() throws {
        let habit = TestHelpers.makeHabit()
        context.insert(habit)

        let today = Calendar.current.startOfDay(for: Date())

        // Morning event (8 AM)
        let morningDate = Calendar.current.date(byAdding: .hour, value: 8, to: today)!
        let morningEvent = TestHelpers.makeEvent(habit: habit, occurredAt: morningDate, outcome: "resisted")
        context.insert(morningEvent)

        // Afternoon event (14:00)
        let afternoonDate = Calendar.current.date(byAdding: .hour, value: 14, to: today)!
        let afternoonEvent = TestHelpers.makeEvent(habit: habit, occurredAt: afternoonDate, outcome: "resisted")
        context.insert(afternoonEvent)

        // Evening event (19:00)
        let eveningDate = Calendar.current.date(byAdding: .hour, value: 19, to: today)!
        let eveningEvent = TestHelpers.makeEvent(habit: habit, occurredAt: eveningDate, outcome: "resisted")
        context.insert(eveningEvent)

        // Night event (2 AM)
        let nightDate = Calendar.current.date(byAdding: .hour, value: 2, to: today)!
        let nightEvent = TestHelpers.makeEvent(habit: habit, occurredAt: nightDate, outcome: "resisted")
        context.insert(nightEvent)

        try context.save()

        let vm = InsightsViewModel(modelContext: context)
        vm.selectedTimeRange = .week
        let dist = vm.timeOfDayDistribution()

        XCTAssertEqual(dist.first(where: { $0.period == "Morning" })?.count, 1)
        XCTAssertEqual(dist.first(where: { $0.period == "Afternoon" })?.count, 1)
        XCTAssertEqual(dist.first(where: { $0.period == "Evening" })?.count, 1)
        XCTAssertEqual(dist.first(where: { $0.period == "Night" })?.count, 1)
    }

    // MARK: - Day of Week Distribution

    func testDayOfWeekDistributionHasSevenDays() throws {
        let habit = TestHelpers.makeHabit()
        context.insert(habit)
        try context.save()

        let vm = InsightsViewModel(modelContext: context)
        let dist = vm.dayOfWeekDistribution()

        XCTAssertEqual(dist.count, 7)
    }

    // MARK: - Hourly Distribution

    func testHourlyDistributionHas24Hours() throws {
        let habit = TestHelpers.makeHabit()
        context.insert(habit)
        try context.save()

        let vm = InsightsViewModel(modelContext: context)
        let dist = vm.hourlyDistribution()

        XCTAssertEqual(dist.count, 24)
        XCTAssertEqual(dist.first?.hour, 0)
        XCTAssertEqual(dist.last?.hour, 23)
    }

    // MARK: - Outcome Breakdown

    func testOutcomeBreakdownCountsCorrectly() throws {
        let habit = TestHelpers.makeHabit()
        context.insert(habit)

        let now = Date()

        // 3 resisted
        for _ in 0..<3 {
            let event = TestHelpers.makeEvent(habit: habit, occurredAt: now, outcome: "resisted")
            context.insert(event)
        }
        // 2 gave_in
        for _ in 0..<2 {
            let event = TestHelpers.makeEvent(habit: habit, occurredAt: now, outcome: "gave_in")
            context.insert(event)
        }
        // 1 unknown
        let unknownEvent = TestHelpers.makeEvent(habit: habit, occurredAt: now, outcome: "unknown")
        context.insert(unknownEvent)

        try context.save()

        let vm = InsightsViewModel(modelContext: context)
        vm.selectedTimeRange = .week
        let breakdown = vm.outcomeBreakdown()

        XCTAssertEqual(breakdown.first(where: { $0.outcome == .resisted })?.count, 3)
        XCTAssertEqual(breakdown.first(where: { $0.outcome == .gaveIn })?.count, 2)
        XCTAssertEqual(breakdown.first(where: { $0.outcome == .unknown })?.count, 1)
    }

    func testResistedCountAndPercentage() throws {
        let habit = TestHelpers.makeHabit()
        context.insert(habit)

        let now = Date()

        // 3 resisted, 1 gave_in = 75% resisted
        for _ in 0..<3 {
            let event = TestHelpers.makeEvent(habit: habit, occurredAt: now, outcome: "resisted")
            context.insert(event)
        }
        let gaveInEvent = TestHelpers.makeEvent(habit: habit, occurredAt: now, outcome: "gave_in")
        context.insert(gaveInEvent)

        try context.save()

        let vm = InsightsViewModel(modelContext: context)
        vm.selectedTimeRange = .week

        XCTAssertEqual(vm.resistedCount, 3)
        XCTAssertEqual(vm.resistedPercentage, 75)
    }

    func testResistedPercentageNilWhenNoEvents() throws {
        let habit = TestHelpers.makeHabit()
        context.insert(habit)
        try context.save()

        let vm = InsightsViewModel(modelContext: context)
        XCTAssertNil(vm.resistedPercentage)
    }

    // MARK: - Peak Time

    func testPeakTimeOfDayReturnsHighestPeriod() throws {
        let habit = TestHelpers.makeHabit()
        context.insert(habit)

        let today = Calendar.current.startOfDay(for: Date())

        // 3 evening events
        for i in 0..<3 {
            let date = Calendar.current.date(byAdding: .hour, value: 19, to: today)!
            let dateWithMinute = Calendar.current.date(byAdding: .minute, value: i, to: date)!
            let event = TestHelpers.makeEvent(habit: habit, occurredAt: dateWithMinute, outcome: "resisted")
            context.insert(event)
        }

        // 1 morning event
        let morningDate = Calendar.current.date(byAdding: .hour, value: 8, to: today)!
        let morningEvent = TestHelpers.makeEvent(habit: habit, occurredAt: morningDate, outcome: "resisted")
        context.insert(morningEvent)

        try context.save()

        let vm = InsightsViewModel(modelContext: context)
        vm.selectedTimeRange = .week

        XCTAssertEqual(vm.peakTimeOfDay, "Evening")
    }

    func testPeakTimeOfDayNilWhenNoEvents() throws {
        let habit = TestHelpers.makeHabit()
        context.insert(habit)
        try context.save()

        let vm = InsightsViewModel(modelContext: context)
        XCTAssertNil(vm.peakTimeOfDay)
    }

    func testPeakDayOfWeekNilWhenNoEvents() throws {
        let habit = TestHelpers.makeHabit()
        context.insert(habit)
        try context.save()

        let vm = InsightsViewModel(modelContext: context)
        XCTAssertNil(vm.peakDayOfWeek)
    }

    // MARK: - Peak Day of Week

    func testPeakDayOfWeekReturnsHighestDay() throws {
        let habit = TestHelpers.makeHabit()
        context.insert(habit)

        let calendar = Calendar.current
        let now = Date()

        // Create 3 events on the same weekday (today) and 1 event on a different day
        for i in 0..<3 {
            let date = calendar.date(byAdding: .minute, value: i, to: now)!
            let event = TestHelpers.makeEvent(habit: habit, occurredAt: date, outcome: "resisted")
            context.insert(event)
        }

        // 1 event 2 days ago (different weekday)
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: now)!
        let otherEvent = TestHelpers.makeEvent(habit: habit, occurredAt: twoDaysAgo, outcome: "resisted")
        context.insert(otherEvent)

        try context.save()

        let vm = InsightsViewModel(modelContext: context)
        vm.selectedTimeRange = .week

        let todayWeekday = calendar.component(.weekday, from: now)
        let expectedDay = calendar.shortWeekdaySymbols[todayWeekday - 1]
        XCTAssertEqual(vm.peakDayOfWeek, expectedDay)
    }

    // MARK: - Change Percentage Edge Cases

    func testChangePercentageNegative100WhenCurrentPeriodEmpty() throws {
        let habit = TestHelpers.makeHabit()
        context.insert(habit)

        let calendar = Calendar.current
        let now = Date()

        // Events only in previous period (8-13 days ago for week range)
        for i in 0..<3 {
            let date = calendar.date(byAdding: .day, value: -(8 + i), to: now)!
            let event = TestHelpers.makeEvent(habit: habit, occurredAt: date, outcome: "resisted")
            context.insert(event)
        }

        try context.save()

        let vm = InsightsViewModel(modelContext: context)
        vm.selectedTimeRange = .week

        XCTAssertEqual(vm.totalEventsInRange, 0)
        XCTAssertEqual(vm.previousPeriodEvents, 3)
        XCTAssertEqual(vm.changeFromPreviousPeriod, -3)
        XCTAssertEqual(vm.changePercentage!, -100.0, accuracy: 0.01)
    }

    // MARK: - Time Range Switching

    func testSwitchingTimeRangeChangesEventsInRange() throws {
        let habit = TestHelpers.makeHabit()
        context.insert(habit)

        let calendar = Calendar.current
        let now = Date()

        // Event today (in both week and month)
        let todayEvent = TestHelpers.makeEvent(habit: habit, occurredAt: now, outcome: "resisted")
        context.insert(todayEvent)

        // Event 15 days ago (only in month range)
        let fifteenDaysAgo = calendar.date(byAdding: .day, value: -15, to: now)!
        let olderEvent = TestHelpers.makeEvent(habit: habit, occurredAt: fifteenDaysAgo, outcome: "gave_in")
        context.insert(olderEvent)

        try context.save()

        let vm = InsightsViewModel(modelContext: context)

        vm.selectedTimeRange = .week
        XCTAssertEqual(vm.eventsInRange().count, 1)

        vm.selectedTimeRange = .month
        XCTAssertEqual(vm.eventsInRange().count, 2)
    }

    // MARK: - Habit Selection

    func testSelectedHabitIndexBoundsChecking() throws {
        let habit = TestHelpers.makeHabit()
        context.insert(habit)
        try context.save()

        let vm = InsightsViewModel(modelContext: context)
        vm.selectedHabitIndex = 99
        XCTAssertNil(vm.selectedHabit)

        vm.selectedHabitIndex = -1
        XCTAssertNil(vm.selectedHabit)

        vm.selectedHabitIndex = 0
        XCTAssertNotNil(vm.selectedHabit)
    }
}
