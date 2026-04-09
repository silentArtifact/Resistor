import XCTest
import SwiftData
@testable import Resistor

@MainActor
final class TemptationEventTests: XCTestCase {

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

    // MARK: - Outcome Enum

    func testOutcomeEnumResistedRoundTrip() {
        let habit = TestHelpers.makeHabit()
        let event = TestHelpers.makeEvent(habit: habit, outcome: "resisted")
        XCTAssertEqual(event.outcomeEnum, .resisted)
    }

    func testOutcomeEnumGaveInRoundTrip() {
        let habit = TestHelpers.makeHabit()
        let event = TestHelpers.makeEvent(habit: habit, outcome: "gave_in")
        XCTAssertEqual(event.outcomeEnum, .gaveIn)
    }

    func testOutcomeEnumUnknownRoundTrip() {
        let habit = TestHelpers.makeHabit()
        let event = TestHelpers.makeEvent(habit: habit, outcome: "unknown")
        XCTAssertEqual(event.outcomeEnum, .unknown)
    }

    func testOutcomeEnumFallsBackToUnknownForInvalidString() {
        let habit = TestHelpers.makeHabit()
        let event = TestHelpers.makeEvent(habit: habit, outcome: "invalid_value")
        XCTAssertEqual(event.outcomeEnum, .unknown)
    }

    func testOutcomeEnumFallsBackForEmptyString() {
        let habit = TestHelpers.makeHabit()
        let event = TestHelpers.makeEvent(habit: habit, outcome: "")
        XCTAssertEqual(event.outcomeEnum, .unknown)
    }

    func testOutcomeEnumCaseSensitive() {
        let habit = TestHelpers.makeHabit()
        let event = TestHelpers.makeEvent(habit: habit, outcome: "Resisted")
        // Raw values are lowercase; capitalized should fall back to unknown
        XCTAssertEqual(event.outcomeEnum, .unknown)
    }

    // MARK: - Outcome Display Properties

    func testOutcomeDisplayNames() {
        XCTAssertEqual(TemptationEvent.Outcome.resisted.displayName, "Resisted")
        XCTAssertEqual(TemptationEvent.Outcome.gaveIn.displayName, "Gave In")
        XCTAssertEqual(TemptationEvent.Outcome.unknown.displayName, "Not recorded")
    }

    func testOutcomeIconNames() {
        XCTAssertEqual(TemptationEvent.Outcome.resisted.iconName, "checkmark.circle.fill")
        XCTAssertEqual(TemptationEvent.Outcome.gaveIn.iconName, "xmark.circle.fill")
        XCTAssertEqual(TemptationEvent.Outcome.unknown.iconName, "questionmark.circle.fill")
    }

    func testOutcomeAllCasesComplete() {
        XCTAssertEqual(TemptationEvent.Outcome.allCases.count, 3)
    }

    // MARK: - Context Tag

    func testContextTagDisplayNames() {
        XCTAssertEqual(TemptationEvent.ContextTag.atStore.displayName, "At Store")
        XCTAssertEqual(TemptationEvent.ContextTag.onPhone.displayName, "On Phone")
        XCTAssertEqual(TemptationEvent.ContextTag.withFriends.displayName, "With Friends")
        XCTAssertEqual(TemptationEvent.ContextTag.alone.displayName, "Alone")
        XCTAssertEqual(TemptationEvent.ContextTag.atWork.displayName, "At Work")
        XCTAssertEqual(TemptationEvent.ContextTag.atHome.displayName, "At Home")
        XCTAssertEqual(TemptationEvent.ContextTag.stressed.displayName, "Stressed")
        XCTAssertEqual(TemptationEvent.ContextTag.bored.displayName, "Bored")
    }

    func testContextTagAllCasesComplete() {
        XCTAssertEqual(TemptationEvent.ContextTag.allCases.count, 8)
    }

    func testContextTagRawValues() {
        XCTAssertEqual(TemptationEvent.ContextTag.atStore.rawValue, "at_store")
        XCTAssertEqual(TemptationEvent.ContextTag.onPhone.rawValue, "on_phone")
        XCTAssertEqual(TemptationEvent.ContextTag.withFriends.rawValue, "with_friends")
        XCTAssertEqual(TemptationEvent.ContextTag.alone.rawValue, "alone")
        XCTAssertEqual(TemptationEvent.ContextTag.atWork.rawValue, "at_work")
        XCTAssertEqual(TemptationEvent.ContextTag.atHome.rawValue, "at_home")
        XCTAssertEqual(TemptationEvent.ContextTag.stressed.rawValue, "stressed")
        XCTAssertEqual(TemptationEvent.ContextTag.bored.rawValue, "bored")
    }

    // MARK: - Time of Day Period (all 24 hours)

    func testTimeOfDayPeriodMorning() {
        let habit = TestHelpers.makeHabit()
        let today = Calendar.current.startOfDay(for: Date())

        for hour in 5..<12 {
            let date = Calendar.current.date(byAdding: .hour, value: hour, to: today)!
            let event = TestHelpers.makeEvent(habit: habit, occurredAt: date)
            XCTAssertEqual(event.timeOfDayPeriod, "Morning", "Hour \(hour) should be Morning")
        }
    }

    func testTimeOfDayPeriodAfternoon() {
        let habit = TestHelpers.makeHabit()
        let today = Calendar.current.startOfDay(for: Date())

        for hour in 12..<17 {
            let date = Calendar.current.date(byAdding: .hour, value: hour, to: today)!
            let event = TestHelpers.makeEvent(habit: habit, occurredAt: date)
            XCTAssertEqual(event.timeOfDayPeriod, "Afternoon", "Hour \(hour) should be Afternoon")
        }
    }

    func testTimeOfDayPeriodEvening() {
        let habit = TestHelpers.makeHabit()
        let today = Calendar.current.startOfDay(for: Date())

        for hour in 17..<21 {
            let date = Calendar.current.date(byAdding: .hour, value: hour, to: today)!
            let event = TestHelpers.makeEvent(habit: habit, occurredAt: date)
            XCTAssertEqual(event.timeOfDayPeriod, "Evening", "Hour \(hour) should be Evening")
        }
    }

    func testTimeOfDayPeriodNight() {
        let habit = TestHelpers.makeHabit()
        let today = Calendar.current.startOfDay(for: Date())

        // Night covers 21-23 and 0-4
        let nightHours = [0, 1, 2, 3, 4, 21, 22, 23]
        for hour in nightHours {
            let date = Calendar.current.date(byAdding: .hour, value: hour, to: today)!
            let event = TestHelpers.makeEvent(habit: habit, occurredAt: date)
            XCTAssertEqual(event.timeOfDayPeriod, "Night", "Hour \(hour) should be Night")
        }
    }

    func testTimeOfDayPeriodBoundaries() {
        let habit = TestHelpers.makeHabit()
        let today = Calendar.current.startOfDay(for: Date())

        // 4:59 AM should be Night
        let earlyMorning = Calendar.current.date(byAdding: .minute, value: 4 * 60 + 59, to: today)!
        let earlyEvent = TestHelpers.makeEvent(habit: habit, occurredAt: earlyMorning)
        XCTAssertEqual(earlyEvent.timeOfDayPeriod, "Night")

        // 5:00 AM should be Morning
        let morningStart = Calendar.current.date(byAdding: .hour, value: 5, to: today)!
        let morningEvent = TestHelpers.makeEvent(habit: habit, occurredAt: morningStart)
        XCTAssertEqual(morningEvent.timeOfDayPeriod, "Morning")

        // 11:59 AM should be Morning
        let lateMorning = Calendar.current.date(byAdding: .minute, value: 11 * 60 + 59, to: today)!
        let lateMorningEvent = TestHelpers.makeEvent(habit: habit, occurredAt: lateMorning)
        XCTAssertEqual(lateMorningEvent.timeOfDayPeriod, "Morning")

        // 12:00 PM should be Afternoon
        let noon = Calendar.current.date(byAdding: .hour, value: 12, to: today)!
        let noonEvent = TestHelpers.makeEvent(habit: habit, occurredAt: noon)
        XCTAssertEqual(noonEvent.timeOfDayPeriod, "Afternoon")

        // 4:59 PM should be Afternoon
        let lateAfternoon = Calendar.current.date(byAdding: .minute, value: 16 * 60 + 59, to: today)!
        let lateAfternoonEvent = TestHelpers.makeEvent(habit: habit, occurredAt: lateAfternoon)
        XCTAssertEqual(lateAfternoonEvent.timeOfDayPeriod, "Afternoon")

        // 5:00 PM should be Evening
        let eveningStart = Calendar.current.date(byAdding: .hour, value: 17, to: today)!
        let eveningEvent = TestHelpers.makeEvent(habit: habit, occurredAt: eveningStart)
        XCTAssertEqual(eveningEvent.timeOfDayPeriod, "Evening")

        // 8:59 PM should be Evening
        let lateEvening = Calendar.current.date(byAdding: .minute, value: 20 * 60 + 59, to: today)!
        let lateEveningEvent = TestHelpers.makeEvent(habit: habit, occurredAt: lateEvening)
        XCTAssertEqual(lateEveningEvent.timeOfDayPeriod, "Evening")

        // 9:00 PM should be Night
        let nightStart = Calendar.current.date(byAdding: .hour, value: 21, to: today)!
        let nightEvent = TestHelpers.makeEvent(habit: habit, occurredAt: nightStart)
        XCTAssertEqual(nightEvent.timeOfDayPeriod, "Night")
    }

    func testAllTwentyFourHoursCovered() {
        let habit = TestHelpers.makeHabit()
        let today = Calendar.current.startOfDay(for: Date())
        let validPeriods: Set<String> = ["Morning", "Afternoon", "Evening", "Night"]

        for hour in 0..<24 {
            let date = Calendar.current.date(byAdding: .hour, value: hour, to: today)!
            let event = TestHelpers.makeEvent(habit: habit, occurredAt: date)
            XCTAssertTrue(validPeriods.contains(event.timeOfDayPeriod),
                         "Hour \(hour) returned invalid period: \(event.timeOfDayPeriod)")
        }
    }

    // MARK: - Hour and Day Extraction

    func testHourOfDayExtraction() {
        let habit = TestHelpers.makeHabit()
        let today = Calendar.current.startOfDay(for: Date())

        for hour in 0..<24 {
            let date = Calendar.current.date(byAdding: .hour, value: hour, to: today)!
            let event = TestHelpers.makeEvent(habit: habit, occurredAt: date)
            XCTAssertEqual(event.hourOfDay, hour, "Expected hour \(hour)")
        }
    }

    func testDayOfWeekRange() {
        let habit = TestHelpers.makeHabit()
        let event = TestHelpers.makeEvent(habit: habit, occurredAt: Date())
        let dayOfWeek = event.dayOfWeek
        XCTAssertTrue((1...7).contains(dayOfWeek), "Day of week \(dayOfWeek) should be 1-7")
    }

    // MARK: - Event Initialization

    func testEventDefaultValues() {
        let habit = TestHelpers.makeHabit()
        let event = TemptationEvent(habit: habit)

        XCTAssertNotNil(event.id)
        XCTAssertEqual(event.outcome, "unknown")
        XCTAssertNil(event.intensity)
        XCTAssertTrue(event.contextTags.isEmpty)
        XCTAssertNil(event.note)
        XCTAssertNotNil(event.habit)
    }

    func testEventCustomValues() {
        let habit = TestHelpers.makeHabit()
        let date = TestHelpers.dateFromComponents(year: 2025, month: 6, day: 15, hour: 10)
        let event = TemptationEvent(
            habit: habit,
            occurredAt: date,
            intensity: 3,
            outcome: "resisted",
            contextTags: ["stressed", "alone"],
            note: "Test note"
        )

        XCTAssertEqual(event.intensity, 3)
        XCTAssertEqual(event.outcome, "resisted")
        XCTAssertEqual(event.contextTags, ["stressed", "alone"])
        XCTAssertEqual(event.note, "Test note")
    }
}
