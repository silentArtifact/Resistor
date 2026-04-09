import XCTest
import SwiftData
@testable import Resistor

@MainActor
final class LogViewModelTests: XCTestCase {

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

        let vm = LogViewModel(modelContext: context)

        XCTAssertEqual(vm.habits.count, 1)
        XCTAssertEqual(vm.habits.first?.name, "Active")
    }

    func testInitWithDefaultHabitIdSelectsCorrectHabit() throws {
        let habit1 = TestHelpers.makeHabit(name: "First", createdAt: Date.distantPast)
        let habit2 = TestHelpers.makeHabit(name: "Second", createdAt: Date())
        context.insert(habit1)
        context.insert(habit2)
        try context.save()

        let vm = LogViewModel(modelContext: context, defaultHabitId: habit2.id)

        XCTAssertEqual(vm.selectedHabit?.name, "Second")
    }

    func testInitWithInvalidDefaultHabitIdDefaultsToFirst() throws {
        let habit = TestHelpers.makeHabit(name: "Only")
        context.insert(habit)
        try context.save()

        let vm = LogViewModel(modelContext: context, defaultHabitId: UUID())

        XCTAssertEqual(vm.selectedHabitIndex, 0)
        XCTAssertEqual(vm.selectedHabit?.name, "Only")
    }

    func testInitWithNoHabits() throws {
        let vm = LogViewModel(modelContext: context)

        XCTAssertTrue(vm.habits.isEmpty)
        XCTAssertFalse(vm.hasHabits)
        XCTAssertNil(vm.selectedHabit)
    }

    // MARK: - Habit Selection

    func testSelectedHabitBoundsChecking() throws {
        let habit = TestHelpers.makeHabit()
        context.insert(habit)
        try context.save()

        let vm = LogViewModel(modelContext: context)

        vm.selectedHabitIndex = -1
        XCTAssertNil(vm.selectedHabit)

        vm.selectedHabitIndex = 99
        XCTAssertNil(vm.selectedHabit)

        vm.selectedHabitIndex = 0
        XCTAssertNotNil(vm.selectedHabit)
    }

    func testSelectHabitAtIndex() throws {
        let habit1 = TestHelpers.makeHabit(name: "First", createdAt: Date.distantPast)
        let habit2 = TestHelpers.makeHabit(name: "Second", createdAt: Date())
        context.insert(habit1)
        context.insert(habit2)
        try context.save()

        let vm = LogViewModel(modelContext: context)

        vm.selectHabit(at: 1)
        XCTAssertEqual(vm.selectedHabit?.name, "Second")

        vm.selectHabit(at: 0)
        XCTAssertEqual(vm.selectedHabit?.name, "First")
    }

    func testSelectHabitAtInvalidIndexDoesNothing() throws {
        let habit = TestHelpers.makeHabit()
        context.insert(habit)
        try context.save()

        let vm = LogViewModel(modelContext: context)
        vm.selectHabit(at: 0)

        vm.selectHabit(at: -1)
        XCTAssertEqual(vm.selectedHabitIndex, 0)

        vm.selectHabit(at: 99)
        XCTAssertEqual(vm.selectedHabitIndex, 0)
    }

    // MARK: - Circular Navigation

    func testSelectNextHabitWrapsAround() throws {
        let habit1 = TestHelpers.makeHabit(name: "First", createdAt: Date.distantPast)
        let habit2 = TestHelpers.makeHabit(name: "Second", createdAt: Date())
        let habit3 = TestHelpers.makeHabit(name: "Third", createdAt: Date.distantFuture)
        context.insert(habit1)
        context.insert(habit2)
        context.insert(habit3)
        try context.save()

        let vm = LogViewModel(modelContext: context)
        XCTAssertEqual(vm.selectedHabitIndex, 0)

        vm.selectNextHabit()
        XCTAssertEqual(vm.selectedHabitIndex, 1)

        vm.selectNextHabit()
        XCTAssertEqual(vm.selectedHabitIndex, 2)

        // Wrap around
        vm.selectNextHabit()
        XCTAssertEqual(vm.selectedHabitIndex, 0)
    }

    func testSelectPreviousHabitWrapsAround() throws {
        let habit1 = TestHelpers.makeHabit(name: "First", createdAt: Date.distantPast)
        let habit2 = TestHelpers.makeHabit(name: "Second", createdAt: Date())
        let habit3 = TestHelpers.makeHabit(name: "Third", createdAt: Date.distantFuture)
        context.insert(habit1)
        context.insert(habit2)
        context.insert(habit3)
        try context.save()

        let vm = LogViewModel(modelContext: context)
        XCTAssertEqual(vm.selectedHabitIndex, 0)

        // Wrap backwards
        vm.selectPreviousHabit()
        XCTAssertEqual(vm.selectedHabitIndex, 2)

        vm.selectPreviousHabit()
        XCTAssertEqual(vm.selectedHabitIndex, 1)

        vm.selectPreviousHabit()
        XCTAssertEqual(vm.selectedHabitIndex, 0)
    }

    func testSelectNextHabitDoesNothingWithSingleHabit() throws {
        let habit = TestHelpers.makeHabit()
        context.insert(habit)
        try context.save()

        let vm = LogViewModel(modelContext: context)
        vm.selectNextHabit()
        XCTAssertEqual(vm.selectedHabitIndex, 0)
    }

    func testSelectPreviousHabitDoesNothingWithSingleHabit() throws {
        let habit = TestHelpers.makeHabit()
        context.insert(habit)
        try context.save()

        let vm = LogViewModel(modelContext: context)
        vm.selectPreviousHabit()
        XCTAssertEqual(vm.selectedHabitIndex, 0)
    }

    // MARK: - Log Temptation

    func testLogTemptationCreatesEvent() throws {
        let habit = TestHelpers.makeHabit()
        context.insert(habit)
        try context.save()

        let vm = LogViewModel(modelContext: context)
        vm.logTemptation()

        XCTAssertNotNil(vm.lastLoggedEvent)
        XCTAssertEqual(vm.lastLoggedEvent?.outcome, "unknown")
        XCTAssertNil(vm.lastLoggedEvent?.intensity)

        let events = try context.fetch(FetchDescriptor<TemptationEvent>())
        XCTAssertEqual(events.count, 1)
    }

    func testLogTemptationDoesNothingWithoutHabit() throws {
        let vm = LogViewModel(modelContext: context)
        vm.logTemptation()

        XCTAssertNil(vm.lastLoggedEvent)

        let events = try context.fetch(FetchDescriptor<TemptationEvent>())
        XCTAssertTrue(events.isEmpty)
    }

    func testLogMultipleTemptations() throws {
        let habit = TestHelpers.makeHabit()
        context.insert(habit)
        try context.save()

        let vm = LogViewModel(modelContext: context)
        vm.logTemptation()
        vm.logTemptation()
        vm.logTemptation()

        let events = try context.fetch(FetchDescriptor<TemptationEvent>())
        XCTAssertEqual(events.count, 3)
    }

    // MARK: - Update Event

    func testUpdateEventOutcome() throws {
        let habit = TestHelpers.makeHabit()
        context.insert(habit)
        try context.save()

        let vm = LogViewModel(modelContext: context)
        vm.logTemptation()
        vm.updateEventOutcome(.resisted)

        XCTAssertEqual(vm.lastLoggedEvent?.outcome, "resisted")
        XCTAssertEqual(vm.lastLoggedEvent?.outcomeEnum, .resisted)
    }

    func testUpdateEventOutcomeDoesNothingWithoutEvent() throws {
        let vm = LogViewModel(modelContext: context)
        // Should not crash
        vm.updateEventOutcome(.resisted)
    }

    func testUpdateEventIntensity() throws {
        let habit = TestHelpers.makeHabit()
        context.insert(habit)
        try context.save()

        let vm = LogViewModel(modelContext: context)
        vm.logTemptation()
        vm.updateEventIntensity(4)

        XCTAssertEqual(vm.lastLoggedEvent?.intensity, 4)
    }

    func testUpdateEventIntensityDoesNothingWithoutEvent() throws {
        let vm = LogViewModel(modelContext: context)
        // Should not crash
        vm.updateEventIntensity(3)
    }

    func testUpdateEventContext() throws {
        let habit = TestHelpers.makeHabit()
        context.insert(habit)
        try context.save()

        let vm = LogViewModel(modelContext: context)
        vm.logTemptation()
        vm.updateEventContext(contextTags: ["stressed", "alone"], note: "Feeling anxious")

        XCTAssertEqual(vm.lastLoggedEvent?.contextTags, ["stressed", "alone"])
        XCTAssertEqual(vm.lastLoggedEvent?.note, "Feeling anxious")
    }

    func testUpdateEventContextConvertsEmptyNoteToNil() throws {
        let habit = TestHelpers.makeHabit()
        context.insert(habit)
        try context.save()

        let vm = LogViewModel(modelContext: context)
        vm.logTemptation()
        vm.updateEventContext(contextTags: [], note: "")

        XCTAssertNil(vm.lastLoggedEvent?.note)
    }

    func testUpdateEventContextDoesNothingWithoutEvent() throws {
        let vm = LogViewModel(modelContext: context)
        // Should not crash
        vm.updateEventContext(contextTags: ["stressed"], note: "test")
    }

    // MARK: - Confirmation

    func testTriggerConfirmationSetsFlag() throws {
        let vm = LogViewModel(modelContext: context)
        vm.triggerConfirmation()
        XCTAssertTrue(vm.showConfirmation)
    }
}
