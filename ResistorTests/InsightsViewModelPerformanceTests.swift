import XCTest
import SwiftData
@testable import Resistor

@MainActor
final class InsightsViewModelPerformanceTests: XCTestCase {

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

    // MARK: - Performance Tests

    func testEventsInRangePerformanceWith500Events() throws {
        let habit = TestHelpers.makeHabit()
        context.insert(habit)

        let calendar = Calendar.current
        let now = Date()

        // Insert 500 events spread over the last 30 days
        for i in 0..<500 {
            let dayOffset = -(i % 30)
            let hourOffset = i % 24
            var date = calendar.date(byAdding: .day, value: dayOffset, to: now)!
            date = calendar.date(byAdding: .hour, value: hourOffset, to: calendar.startOfDay(for: date))!
            let outcomes = ["resisted", "gave_in", "unknown"]
            let event = TestHelpers.makeEvent(
                habit: habit,
                occurredAt: date,
                intensity: (i % 5) + 1,
                outcome: outcomes[i % 3]
            )
            context.insert(event)
        }
        try context.save()

        let vm = InsightsViewModel(modelContext: context)
        vm.selectedTimeRange = .month

        measure {
            _ = vm.eventsInRange()
            _ = vm.dailyDistribution()
            _ = vm.timeOfDayDistribution()
            _ = vm.dayOfWeekDistribution()
            _ = vm.hourlyDistribution()
            _ = vm.outcomeBreakdown()
            _ = vm.resistedCount
            _ = vm.resistedPercentage
            _ = vm.peakTimeOfDay
            _ = vm.peakDayOfWeek
            _ = vm.changePercentage
        }
    }

    func testDailyDistributionPerformanceWith1000Events() throws {
        let habit = TestHelpers.makeHabit()
        context.insert(habit)

        let calendar = Calendar.current
        let now = Date()

        for i in 0..<1000 {
            let dayOffset = -(i % 7)
            let date = calendar.date(byAdding: .day, value: dayOffset, to: now)!
            let event = TestHelpers.makeEvent(habit: habit, occurredAt: date, outcome: "resisted")
            context.insert(event)
        }
        try context.save()

        let vm = InsightsViewModel(modelContext: context)
        vm.selectedTimeRange = .week

        measure {
            _ = vm.dailyDistribution()
        }
    }
}
