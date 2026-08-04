import XCTest
import SwiftData
@testable import Resistor

/// Covers user-named places: distance matching, the display-name precedence
/// chain, and the payoff — two spots that reverse-geocode to the same coarse
/// string separating in Insights once named.
@MainActor
final class PlaceTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    /// ~111 m per 0.001° of latitude, so these offsets sit either side of the
    /// 150 m match radius without depending on longitude convergence.
    private let base = (lat: 40.7128, lon: -74.0060)
    private var within: Double { base.lat + 0.001 }   // ~111 m
    private var beyond: Double { base.lat + 0.003 }   // ~333 m

    override func setUp() async throws {
        container = try TestHelpers.makeModelContainer()
        context = container.mainContext
    }

    override func tearDown() async throws {
        container = nil
        context = nil
    }

    // MARK: - Matching

    func testMatchesEventInsideRadius() {
        let home = Place(name: "Home", latitude: base.lat, longitude: base.lon)
        let habit = TestHelpers.makeHabit()
        let event = TestHelpers.makeEvent(habit: habit, latitude: within, longitude: base.lon)

        XCTAssertEqual([home].match(event)?.name, "Home")
    }

    func testDoesNotMatchEventOutsideRadius() {
        let home = Place(name: "Home", latitude: base.lat, longitude: base.lon)
        let habit = TestHelpers.makeHabit()
        let event = TestHelpers.makeEvent(habit: habit, latitude: beyond, longitude: base.lon)

        XCTAssertNil([home].match(event))
    }

    func testNearestPlaceWinsWhenTwoOverlap() {
        let far = Place(name: "Far", latitude: base.lat + 0.0012, longitude: base.lon)
        let near = Place(name: "Near", latitude: base.lat + 0.0001, longitude: base.lon)
        let habit = TestHelpers.makeHabit()
        let event = TestHelpers.makeEvent(habit: habit, latitude: base.lat, longitude: base.lon)

        XCTAssertEqual([far, near].match(event)?.name, "Near")
    }

    func testNoMatchWhenEventHasNoCoordinates() {
        let home = Place(name: "Home", latitude: base.lat, longitude: base.lon)
        let habit = TestHelpers.makeHabit()
        let event = TestHelpers.makeEvent(habit: habit, locationName: "Midtown, New York")

        XCTAssertNil([home].match(event))
    }

    // MARK: - Display name precedence

    func testPlaceNameBeatsGeocodedName() {
        let home = Place(name: "Home", latitude: base.lat, longitude: base.lon)
        let habit = TestHelpers.makeHabit()
        let event = TestHelpers.makeEvent(
            habit: habit,
            latitude: within,
            longitude: base.lon,
            locationName: "Midtown, New York"
        )

        XCTAssertEqual([home].displayName(for: event), "Home")
    }

    func testFallsBackToGeocodedNameWithoutAPlace() {
        let habit = TestHelpers.makeHabit()
        let event = TestHelpers.makeEvent(
            habit: habit,
            latitude: base.lat,
            longitude: base.lon,
            locationName: "Midtown, New York"
        )

        XCTAssertEqual([Place]().displayName(for: event), "Midtown, New York")
    }

    func testGroupingNameSkipsRawCoordinates() {
        let habit = TestHelpers.makeHabit()
        let event = TestHelpers.makeEvent(habit: habit, latitude: base.lat, longitude: base.lon)

        // displayName degrades to coordinates for the detail screen; the chart
        // grouping key must not, or Top Locations fills with lat/lon strings.
        XCTAssertEqual([Place]().displayName(for: event), "40.7128, -74.0060")
        XCTAssertNil([Place]().groupingName(for: event))
    }

    // MARK: - In transit

    func testTransitBeatsASavedPlaceTheEventDrovePast() {
        let home = Place(name: "Home", latitude: base.lat, longitude: base.lon)
        let habit = TestHelpers.makeHabit()
        let event = TestHelpers.makeEvent(
            habit: habit,
            latitude: within,
            longitude: base.lon,
            locationName: "Midtown, New York",
            speedMps: 20   // ~45 mph
        )

        // Driving past the house is not being at the house — the whole point of
        // the field. It has to win over both the saved place and the geocode.
        XCTAssertEqual([home].displayName(for: event), "In transit")
        XCTAssertEqual([home].groupingName(for: event), "In transit")
    }

    func testTransitGroupsEvenWithoutAGeocodedName() {
        let habit = TestHelpers.makeHabit()
        let event = TestHelpers.makeEvent(
            habit: habit,
            latitude: base.lat,
            longitude: base.lon,
            speedMps: 20
        )

        // Raw coordinates are excluded from the grouping key; "In transit" is a
        // name, so it must not be dropped alongside them.
        XCTAssertEqual([Place]().groupingName(for: event), "In transit")
    }

    func testWalkingPaceAndUnknownSpeedBothStayAtThePlace() {
        let home = Place(name: "Home", latitude: base.lat, longitude: base.lon)
        let habit = TestHelpers.makeHabit()
        let strolling = TestHelpers.makeEvent(
            habit: habit,
            latitude: within,
            longitude: base.lon,
            speedMps: 1.5   // walking
        )
        // nil is what a wifi or cell fix stores, and what every event logged
        // before the field existed has. It must read as stationary, not as
        // transit, or the whole back catalogue relabels itself.
        let unknown = TestHelpers.makeEvent(
            habit: habit,
            latitude: within,
            longitude: base.lon
        )

        XCTAssertEqual([home].displayName(for: strolling), "Home")
        XCTAssertEqual([home].displayName(for: unknown), "Home")
    }

    // MARK: - Insights grouping

    func testNamedPlacesSplitAnIdenticalGeocodedString() throws {
        let habit = TestHelpers.makeHabit()
        context.insert(habit)

        // Two spots ~1 km apart that both reverse-geocode to the same string —
        // exactly the case that makes name-based aliasing wrong.
        let homeCoord = (lat: base.lat, lon: base.lon)
        let storeCoord = (lat: base.lat + 0.009, lon: base.lon)

        for coord in [homeCoord, homeCoord, storeCoord] {
            context.insert(TestHelpers.makeEvent(
                habit: habit,
                latitude: coord.lat,
                longitude: coord.lon,
                locationName: "Midtown, New York"
            ))
        }
        context.insert(Place(name: "Home", latitude: homeCoord.lat, longitude: homeCoord.lon))
        context.insert(Place(name: "Grocery Store", latitude: storeCoord.lat, longitude: storeCoord.lon))
        try context.save()

        let vm = InsightsViewModel(modelContext: context)
        let distribution = vm.locationDistribution()

        XCTAssertEqual(distribution.count, 2)
        XCTAssertEqual(distribution.first?.location, "Home")
        XCTAssertEqual(distribution.first?.count, 2)
        XCTAssertEqual(distribution.last?.location, "Grocery Store")
        XCTAssertEqual(distribution.last?.count, 1)
    }

    func testUnnamedEventsStillGroupByGeocodedName() throws {
        let habit = TestHelpers.makeHabit()
        context.insert(habit)
        for _ in 0..<2 {
            context.insert(TestHelpers.makeEvent(
                habit: habit,
                latitude: base.lat,
                longitude: base.lon,
                locationName: "Midtown, New York"
            ))
        }
        try context.save()

        let vm = InsightsViewModel(modelContext: context)

        XCTAssertEqual(vm.topLocation, "Midtown, New York")
    }

    // MARK: - 12-hour axis labels

    func testTwelveHourClockConvertsMidnightAndNoon() {
        XCTAssertEqual(InsightsView.twelveHourClock(0), "12 AM")
        XCTAssertEqual(InsightsView.twelveHourClock(12), "12 PM")
        XCTAssertEqual(InsightsView.twelveHourClock(13), "1 PM")
        XCTAssertEqual(InsightsView.twelveHourClock(13, meridiem: false), "1")
    }

    func testAxisLabelsCarryMeridiemOnlyAtBoundaries() {
        // Night wraps midnight, so it flips twice: at the first tick and at 12 AM.
        XCTAssertEqual(
            TimeOfDayPeriod.night.hours.map { InsightsView.axisHourLabel($0, in: .night) },
            ["9 PM", "10", "11", "12 AM", "1", "2", "3", "4"]
        )
        XCTAssertEqual(
            TimeOfDayPeriod.morning.hours.map { InsightsView.axisHourLabel($0, in: .morning) },
            ["5 AM", "6", "7", "8", "9", "10", "11"]
        )
        XCTAssertEqual(
            TimeOfDayPeriod.afternoon.hours.map { InsightsView.axisHourLabel($0, in: .afternoon) },
            ["12 PM", "1", "2", "3", "4"]
        )
    }

    // MARK: - Nearby name suggestions

    func testNearbyNamesDropNilsAndDuplicatesAndCap() {
        let raw: [String?] = ["Blue Bottle", nil, "Blue Bottle", "", "Safeway", "Gym", "Bank", "Park", "Deli", "Bar"]
        // First-seen order kept, so the closest result stays at the top.
        XCTAssertEqual(
            PlaceNameSheet.nearbyNames(from: raw),
            ["Blue Bottle", "Safeway", "Gym", "Bank", "Park", "Deli"]
        )
        XCTAssertEqual(PlaceNameSheet.nearbyNames(from: raw, limit: 2), ["Blue Bottle", "Safeway"])
    }
}
