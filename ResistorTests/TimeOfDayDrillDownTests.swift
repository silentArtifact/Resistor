import XCTest
import SwiftData
@testable import Resistor

/// Tests for the Time-of-Day drill-down logic added to InsightsViewModel:
/// `TimeOfDayPeriod` (hours / displayName / init?(periodString:)) and
/// `hourlyDistribution(for:)`.
@MainActor
final class TimeOfDayDrillDownTests: XCTestCase {

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

    // MARK: - TimeOfDayPeriod.hours

    func testMorningHours() {
        XCTAssertEqual(TimeOfDayPeriod.morning.hours, [5, 6, 7, 8, 9, 10, 11])
    }

    func testAfternoonHours() {
        XCTAssertEqual(TimeOfDayPeriod.afternoon.hours, [12, 13, 14, 15, 16])
    }

    func testEveningHours() {
        XCTAssertEqual(TimeOfDayPeriod.evening.hours, [17, 18, 19, 20])
    }

    /// AC-5: Night must wrap midnight in display order, NOT be numerically sorted.
    func testNightHoursWrapMidnightInDisplayOrder() {
        XCTAssertEqual(TimeOfDayPeriod.night.hours, [21, 22, 23, 0, 1, 2, 3, 4])
        // Explicitly assert it is NOT numeric-sorted.
        XCTAssertNotEqual(TimeOfDayPeriod.night.hours, TimeOfDayPeriod.night.hours.sorted())
    }

    /// Every hour 0...23 belongs to exactly one period, with no overlaps —
    /// guarantees the drill-down windows partition the day so per-hour counts
    /// can sum back to the overview without double-counting (AC-1).
    func testAllHoursPartitionedExactlyOnce() {
        let all = TimeOfDayPeriod.allCases.flatMap { $0.hours }
        XCTAssertEqual(all.count, 24, "Periods must cover exactly 24 hour-slots with no overlap")
        XCTAssertEqual(Set(all), Set(0..<24), "Periods must cover every hour 0...23 exactly once")
    }

    /// The enum's hour windows must agree with TemptationEvent.timeOfDayPeriod
    /// (the classifier the overview bar uses). If these drift, drill-down sums
    /// won't match the overview.
    func testHoursAgreeWithEventTimeOfDayClassifier() {
        let habit = TestHelpers.makeHabit()
        let today = Calendar.current.startOfDay(for: Date())
        for hour in 0..<24 {
            let date = Calendar.current.date(byAdding: .hour, value: hour, to: today)!
            let event = TestHelpers.makeEvent(habit: habit, occurredAt: date)
            let classifierPeriod = event.timeOfDayPeriod
            let owningPeriod = TimeOfDayPeriod.allCases.first { $0.hours.contains(hour) }
            XCTAssertEqual(owningPeriod?.displayName, classifierPeriod,
                           "Hour \(hour): enum owner \(String(describing: owningPeriod?.displayName)) != classifier \(classifierPeriod)")
        }
    }

    // MARK: - init?(periodString:)

    func testInitPeriodStringRoundTrips() {
        XCTAssertEqual(TimeOfDayPeriod(periodString: "Morning"), .morning)
        XCTAssertEqual(TimeOfDayPeriod(periodString: "Afternoon"), .afternoon)
        XCTAssertEqual(TimeOfDayPeriod(periodString: "Evening"), .evening)
        XCTAssertEqual(TimeOfDayPeriod(periodString: "Night"), .night)
    }

    func testInitPeriodStringRoundTripsThroughDisplayName() {
        for period in TimeOfDayPeriod.allCases {
            XCTAssertEqual(TimeOfDayPeriod(periodString: period.displayName), period)
        }
    }

    /// init? must accept exactly the strings emitted by timeOfDayDistribution()/
    /// TemptationEvent.timeOfDayPeriod.
    func testInitPeriodStringAcceptsDistributionStrings() {
        let habit = TestHelpers.makeHabit()
        context.insert(habit)
        let vm = InsightsViewModel(modelContext: context)
        for (period, _) in vm.timeOfDayDistribution() {
            XCTAssertNotNil(TimeOfDayPeriod(periodString: period),
                            "Distribution emitted '\(period)' that init?(periodString:) rejects")
        }
    }

    func testInitPeriodStringRejectsGarbage() {
        XCTAssertNil(TimeOfDayPeriod(periodString: "garbage"))
        XCTAssertNil(TimeOfDayPeriod(periodString: ""))
        XCTAssertNil(TimeOfDayPeriod(periodString: "morning"))   // wrong case
        XCTAssertNil(TimeOfDayPeriod(periodString: "Mid-day"))
    }

    // MARK: - hourlyDistribution(for:) — shape & order

    func testHourlyDistributionReturnsOneEntryPerHourInOrder() {
        let habit = TestHelpers.makeHabit()
        context.insert(habit)
        try? context.save()
        let vm = InsightsViewModel(modelContext: context)

        for period in TimeOfDayPeriod.allCases {
            let dist = vm.hourlyDistribution(for: period)
            XCTAssertEqual(dist.map(\.hour), period.hours,
                           "\(period.displayName) bars not one-per-hour in period order")
        }
    }

    /// AC-5: a zero-event period still expands to all-zero hourly bars, one per hour.
    func testZeroEventPeriodYieldsAllZeroBars() {
        let habit = TestHelpers.makeHabit()
        context.insert(habit)
        try? context.save()
        let vm = InsightsViewModel(modelContext: context)
        vm.selectedTimeRange = .week

        let dist = vm.hourlyDistribution(for: .night)
        XCTAssertEqual(dist.map(\.hour), TimeOfDayPeriod.night.hours)
        XCTAssertTrue(dist.allSatisfy { $0.count == 0 })
        XCTAssertEqual(dist.count, TimeOfDayPeriod.night.hours.count)
    }

    // MARK: - hourlyDistribution(for:) — bucketing

    func testEventsAssignedToCorrectHourBucket() {
        let habit = TestHelpers.makeHabit()
        context.insert(habit)
        let today = Calendar.current.startOfDay(for: Date())

        // 2 events at 08:00, 1 event at 10:00 (both Morning)
        for _ in 0..<2 {
            let d = Calendar.current.date(byAdding: .hour, value: 8, to: today)!
            context.insert(TestHelpers.makeEvent(habit: habit, occurredAt: d))
        }
        let tenAM = Calendar.current.date(byAdding: .hour, value: 10, to: today)!
        context.insert(TestHelpers.makeEvent(habit: habit, occurredAt: tenAM))
        try? context.save()

        let vm = InsightsViewModel(modelContext: context)
        vm.selectedTimeRange = .week
        let dist = vm.hourlyDistribution(for: .morning)

        XCTAssertEqual(dist.first(where: { $0.hour == 8 })?.count, 2)
        XCTAssertEqual(dist.first(where: { $0.hour == 10 })?.count, 1)
        // Other morning hours stay zero
        XCTAssertEqual(dist.first(where: { $0.hour == 5 })?.count, 0)
        XCTAssertEqual(dist.first(where: { $0.hour == 11 })?.count, 0)
    }

    /// AC-5 ordering with real data: a 23:00 event and a 01:00 event both land in
    /// Night, appearing in wrap order (21…23 before 0…4).
    func testNightBucketingAcrossMidnight() {
        let habit = TestHelpers.makeHabit()
        context.insert(habit)
        let today = Calendar.current.startOfDay(for: Date())

        let elevenPM = Calendar.current.date(byAdding: .hour, value: 23, to: today)!
        context.insert(TestHelpers.makeEvent(habit: habit, occurredAt: elevenPM))
        let oneAM = Calendar.current.date(byAdding: .hour, value: 1, to: today)!
        context.insert(TestHelpers.makeEvent(habit: habit, occurredAt: oneAM))
        try? context.save()

        let vm = InsightsViewModel(modelContext: context)
        vm.selectedTimeRange = .week
        let dist = vm.hourlyDistribution(for: .night)

        XCTAssertEqual(dist.first(where: { $0.hour == 23 })?.count, 1)
        XCTAssertEqual(dist.first(where: { $0.hour == 1 })?.count, 1)
        // Index of 23 must come before index of 1 (wrap order, not numeric).
        let idx23 = dist.firstIndex(where: { $0.hour == 23 })!
        let idx1 = dist.firstIndex(where: { $0.hour == 1 })!
        XCTAssertLessThan(idx23, idx1)
    }

    // MARK: - AC-1: hourly counts sum to the overview period count

    func testHourlyCountsSumToOverviewPeriodCount() {
        let habit = TestHelpers.makeHabit()
        context.insert(habit)
        let today = Calendar.current.startOfDay(for: Date())

        // Spread events across all four windows, including a midnight-wrap night event.
        let hours = [6, 8, 8, 13, 16, 18, 20, 23, 2, 4]
        for h in hours {
            let d = Calendar.current.date(byAdding: .hour, value: h, to: today)!
            context.insert(TestHelpers.makeEvent(habit: habit, occurredAt: d))
        }
        try? context.save()

        let vm = InsightsViewModel(modelContext: context)
        vm.selectedTimeRange = .week

        let overview = vm.timeOfDayDistribution()
        for period in TimeOfDayPeriod.allCases {
            let overviewCount = overview.first { $0.period == period.displayName }?.count ?? -1
            let hourlySum = vm.hourlyDistribution(for: period).reduce(0) { $0 + $1.count }
            XCTAssertEqual(hourlySum, overviewCount,
                           "\(period.displayName): hourly sum \(hourlySum) != overview \(overviewCount)")
        }
    }

    // MARK: - AC-4: respects active range, recomputes (never stale)

    func testHourlyDistributionRespectsActiveRange() {
        let habit = TestHelpers.makeHabit()
        context.insert(habit)
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)

        // Morning event today (in week + month range)
        let todayMorning = calendar.date(byAdding: .hour, value: 8, to: today)!
        context.insert(TestHelpers.makeEvent(habit: habit, occurredAt: todayMorning))

        // Morning event 15 days ago (only in month range)
        let oldDay = calendar.date(byAdding: .day, value: -15, to: today)!
        let oldMorning = calendar.date(byAdding: .hour, value: 8, to: oldDay)!
        context.insert(TestHelpers.makeEvent(habit: habit, occurredAt: oldMorning))
        try? context.save()

        let vm = InsightsViewModel(modelContext: context)

        vm.selectedTimeRange = .week
        XCTAssertEqual(vm.hourlyDistribution(for: .morning).first(where: { $0.hour == 8 })?.count, 1,
                       "Week range should only see today's morning event")

        // Switching range must recompute, not serve stale data.
        vm.selectedTimeRange = .month
        XCTAssertEqual(vm.hourlyDistribution(for: .morning).first(where: { $0.hour == 8 })?.count, 2,
                       "Month range should see both morning events")
    }

    func testHourlyDistributionRespectsSelectedHabit() {
        let habitA = TestHelpers.makeHabit(name: "A", createdAt: Date(timeIntervalSince1970: 1))
        let habitB = TestHelpers.makeHabit(name: "B", createdAt: Date(timeIntervalSince1970: 2))
        context.insert(habitA)
        context.insert(habitB)
        let today = Calendar.current.startOfDay(for: Date())
        let eightAM = Calendar.current.date(byAdding: .hour, value: 8, to: today)!

        // 1 morning event on A, 3 morning events on B
        context.insert(TestHelpers.makeEvent(habit: habitA, occurredAt: eightAM))
        for _ in 0..<3 {
            context.insert(TestHelpers.makeEvent(habit: habitB, occurredAt: eightAM))
        }
        try? context.save()

        let vm = InsightsViewModel(modelContext: context)
        vm.selectedTimeRange = .week

        // habits sorted by createdAt: index 0 = A, index 1 = B
        vm.selectedHabitIndex = 0
        XCTAssertEqual(vm.hourlyDistribution(for: .morning).first(where: { $0.hour == 8 })?.count, 1)

        vm.selectedHabitIndex = 1
        XCTAssertEqual(vm.hourlyDistribution(for: .morning).first(where: { $0.hour == 8 })?.count, 3,
                       "Switching habit must recompute hourly bars for the new habit")
    }
}
