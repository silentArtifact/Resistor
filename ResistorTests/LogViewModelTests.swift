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
        // UC-O1: a single-tap log now defaults to "resisted" (was "unknown").
        XCTAssertEqual(vm.lastLoggedEvent?.outcome, TemptationEvent.Outcome.resisted.rawValue)
        XCTAssertNil(vm.lastLoggedEvent?.intensity)

        let events = try context.fetch(FetchDescriptor<TemptationEvent>())
        XCTAssertEqual(events.count, 1)
    }

    func testLogTemptationLinksEventToSelectedHabit() throws {
        let habit1 = TestHelpers.makeHabit(name: "Smoking", createdAt: Date.distantPast)
        let habit2 = TestHelpers.makeHabit(name: "Drinking", createdAt: Date())
        context.insert(habit1)
        context.insert(habit2)
        try context.save()

        let vm = LogViewModel(modelContext: context)
        vm.selectHabit(at: 1) // Select Drinking
        vm.logTemptation()

        XCTAssertEqual(vm.lastLoggedEvent?.habit?.name, "Drinking")
        XCTAssertEqual(vm.lastLoggedEvent?.habit?.id, habit2.id)
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

    func testTriggerConfirmationResetsAfterDelay() throws {
        let vm = LogViewModel(modelContext: context)
        vm.triggerConfirmation()
        XCTAssertTrue(vm.showConfirmation)

        // The banner auto-hides after 5s (the dwell window for an in-the-moment
        // correction; raised from 4s per the Outcome Capture spec).
        // Still showing just before the 5s deadline.
        let stillShowing = expectation(description: "Still showing at 4.5s")
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) {
            stillShowing.fulfill()
        }
        wait(for: [stillShowing], timeout: 5.0)
        XCTAssertTrue(vm.showConfirmation, "Banner should still be visible at 4.5s (5s dwell)")

        // Dismissed after the 5s deadline.
        let dismissed = expectation(description: "Confirmation dismissed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            dismissed.fulfill()
        }
        wait(for: [dismissed], timeout: 2.0)
        XCTAssertFalse(vm.showConfirmation)
    }

    func testTriggerConfirmationRapidCallsDoNotDismissPrematurely() throws {
        let vm = LogViewModel(modelContext: context)

        // First trigger
        vm.triggerConfirmation()
        XCTAssertTrue(vm.showConfirmation)

        // Wait a short time, then trigger again (should cancel the first timer)
        let midExpectation = expectation(description: "Mid-wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            midExpectation.fulfill()
        }
        wait(for: [midExpectation], timeout: 1.0)

        // Second trigger resets the timer
        vm.triggerConfirmation()
        XCTAssertTrue(vm.showConfirmation)

        // Wait past when the first timer would have fired (5s from the first
        // call ≈ 4.5s from here) but before the second timer fires.
        let firstTimerExpectation = expectation(description: "Past first timer")
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.7) {
            firstTimerExpectation.fulfill()
        }
        wait(for: [firstTimerExpectation], timeout: 5.5)

        // Should still be showing because the second timer hasn't fired yet
        // (~5.2s from the first call; the second timer fires at ~5.5s).
        XCTAssertTrue(vm.showConfirmation)

        // Wait for the second timer (5s from the second call) to fire.
        let finalExpectation = expectation(description: "Second timer fired")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            finalExpectation.fulfill()
        }
        wait(for: [finalExpectation], timeout: 2.0)
        XCTAssertFalse(vm.showConfirmation)
    }

    // MARK: - Outcome Capture: UC-O1 (default resisted)

    func testLogTemptationDefaultsToResisted() throws {
        let habit = TestHelpers.makeHabit()
        context.insert(habit)
        try context.save()

        let vm = LogViewModel(modelContext: context)
        vm.logTemptation()

        XCTAssertEqual(vm.lastLoggedEvent?.outcomeEnum, .resisted)
        XCTAssertEqual(vm.lastLoggedEvent?.outcome, "resisted")
    }

    func testModelDefaultOutcomeStaysUnknownForUnsetEvents() throws {
        // UC-O1: pre-existing events that don't set outcome stay "unknown".
        // The stored-property default on the model must remain "unknown" even
        // though the Log flow now writes "resisted".
        let habit = TestHelpers.makeHabit()
        let legacy = TemptationEvent(habit: habit)
        context.insert(habit)
        context.insert(legacy)
        try context.save()

        XCTAssertEqual(legacy.outcome, "unknown")
        XCTAssertEqual(legacy.outcomeEnum, .unknown)
    }

    // MARK: - Outcome Capture: UC-O2 (gave-in is a pure flip)

    func testMarkLastLogGaveInFlipsOutcome() throws {
        let habit = TestHelpers.makeHabit()
        context.insert(habit)
        try context.save()

        let vm = LogViewModel(modelContext: context)
        vm.logTemptation()
        XCTAssertEqual(vm.lastLoggedEvent?.outcomeEnum, .resisted)

        vm.markLastLogGaveIn()

        XCTAssertEqual(vm.lastLoggedEvent?.outcomeEnum, .gaveIn)
        XCTAssertEqual(vm.lastLoggedEvent?.outcome, "gave_in")
    }

    func testMarkLastLogGaveInPersists() throws {
        let habit = TestHelpers.makeHabit()
        context.insert(habit)
        try context.save()

        let vm = LogViewModel(modelContext: context)
        vm.logTemptation()
        let eventId = vm.lastLoggedEvent!.id
        vm.markLastLogGaveIn()

        // Re-fetch from the store to confirm the flip was saved, not just held in memory.
        let fetched = try context.fetch(FetchDescriptor<TemptationEvent>())
        let match = fetched.first { $0.id == eventId }
        XCTAssertEqual(match?.outcome, "gave_in")
    }

    func testMarkLastLogGaveInIsPureFlip_PreservesAllOtherFields() throws {
        let habit = TestHelpers.makeHabit(name: "Smoking")
        context.insert(habit)
        try context.save()

        let vm = LogViewModel(modelContext: context)
        vm.logTemptation(contextTags: ["stressed", "alone"])
        // Set the remaining mutable fields on the just-logged event to known values.
        let event = vm.lastLoggedEvent!
        event.intensity = 4
        event.note = "anxious"
        event.latitude = 37.3349
        event.longitude = -122.0090
        event.locationName = "Cupertino"
        let originalOccurredAt = event.occurredAt
        let originalHabitId = event.habit?.id
        try context.save()

        vm.markLastLogGaveIn()

        // Only outcome changed.
        XCTAssertEqual(event.outcomeEnum, .gaveIn)
        XCTAssertEqual(event.intensity, 4)
        XCTAssertEqual(event.contextTags, ["stressed", "alone"])
        XCTAssertEqual(event.note, "anxious")
        XCTAssertEqual(event.occurredAt, originalOccurredAt)
        XCTAssertEqual(event.habit?.id, originalHabitId)
        XCTAssertEqual(event.latitude, 37.3349)
        XCTAssertEqual(event.longitude, -122.0090)
        XCTAssertEqual(event.locationName, "Cupertino")
    }

    func testMarkLastLogGaveInDoesNotCreateSecondEvent() throws {
        let habit = TestHelpers.makeHabit()
        context.insert(habit)
        try context.save()

        let vm = LogViewModel(modelContext: context)
        vm.logTemptation()
        vm.markLastLogGaveIn()

        let events = try context.fetch(FetchDescriptor<TemptationEvent>())
        XCTAssertEqual(events.count, 1, "Gave in must edit the existing event, not create a new one")
    }

    func testMarkLastLogGaveInDoesNothingWithoutEvent() throws {
        let vm = LogViewModel(modelContext: context)
        // Should not crash and should create nothing.
        vm.markLastLogGaveIn()

        let events = try context.fetch(FetchDescriptor<TemptationEvent>())
        XCTAssertTrue(events.isEmpty)
        XCTAssertNil(vm.lastLoggedEvent)
    }

    // MARK: - Outcome Capture: UC-O3 (Undo vs Gave in are distinct)

    func testUndoLastLogDeletesEvent() throws {
        let habit = TestHelpers.makeHabit()
        context.insert(habit)
        try context.save()

        let vm = LogViewModel(modelContext: context)
        vm.logTemptation()
        XCTAssertEqual(try context.fetch(FetchDescriptor<TemptationEvent>()).count, 1)

        vm.undoLastLog()

        XCTAssertNil(vm.lastLoggedEvent)
        XCTAssertTrue(try context.fetch(FetchDescriptor<TemptationEvent>()).isEmpty)
    }

    func testGaveInLeavesEventInStoreWhereasUndoRemovesIt() throws {
        let habit = TestHelpers.makeHabit()
        context.insert(habit)
        try context.save()

        // Gave in path: event remains.
        let vm1 = LogViewModel(modelContext: context)
        vm1.logTemptation()
        vm1.markLastLogGaveIn()
        XCTAssertNotNil(vm1.lastLoggedEvent, "Gave in keeps lastLoggedEvent")
        XCTAssertEqual(try context.fetch(FetchDescriptor<TemptationEvent>()).count, 1)

        // Undo path on a fresh log: event removed.
        let vm2 = LogViewModel(modelContext: context)
        vm2.logTemptation()
        XCTAssertEqual(try context.fetch(FetchDescriptor<TemptationEvent>()).count, 2)
        vm2.undoLastLog()
        XCTAssertNil(vm2.lastLoggedEvent, "Undo clears lastLoggedEvent")
        XCTAssertEqual(try context.fetch(FetchDescriptor<TemptationEvent>()).count, 1)
    }

    // MARK: - Outcome Correction: UC-O4 (History picker options rule)
    //
    // NOTE: The picker's available-options computation and binding setter live
    // inside EventDetailSheet (a private `let` in `body` and a private
    // `outcomeBinding`), so they are NOT directly reachable from a unit test.
    // Below:
    //  - `availableOutcomeOptions(for:)` REPLICATES the exact rule from
    //    HistoryView.swift to verify the documented behavior. This tests the
    //    rule as inferred from the spec/source, not the View code itself.
    //  - The binding *setter* behavior (write rawValue + persist) is exercised
    //    at the reachable model seam, which is identical to what the setter does.

    /// Mirror of the options rule in `EventDetailSheet.body` (HistoryView.swift):
    /// "Not recorded"/.unknown is offered only when the event is currently unknown.
    private func availableOutcomeOptions(for event: TemptationEvent) -> [TemptationEvent.Outcome] {
        event.outcomeEnum == .unknown
            ? [.resisted, .gaveIn, .unknown]
            : [.resisted, .gaveIn]
    }

    func testHistoryPickerOffersUnknownOnlyForUnknownEvent() throws {
        let habit = TestHelpers.makeHabit()
        context.insert(habit)

        let unknownEvent = TestHelpers.makeEvent(habit: habit, outcome: "unknown")
        let resistedEvent = TestHelpers.makeEvent(habit: habit, outcome: "resisted")
        let gaveInEvent = TestHelpers.makeEvent(habit: habit, outcome: "gave_in")
        context.insert(unknownEvent)
        context.insert(resistedEvent)
        context.insert(gaveInEvent)
        try context.save()

        // Legacy/unknown event: all three offered, including .unknown.
        XCTAssertEqual(availableOutcomeOptions(for: unknownEvent), [.resisted, .gaveIn, .unknown])

        // Recorded events: .unknown must NOT be offered (no downgrade to "Not recorded").
        XCTAssertEqual(availableOutcomeOptions(for: resistedEvent), [.resisted, .gaveIn])
        XCTAssertFalse(availableOutcomeOptions(for: resistedEvent).contains(.unknown))
        XCTAssertEqual(availableOutcomeOptions(for: gaveInEvent), [.resisted, .gaveIn])
        XCTAssertFalse(availableOutcomeOptions(for: gaveInEvent).contains(.unknown))
    }

    func testHistoryPickerUnknownDropsAfterEventBecomesRecorded() throws {
        let habit = TestHelpers.makeHabit()
        context.insert(habit)
        let event = TestHelpers.makeEvent(habit: habit, outcome: "unknown")
        context.insert(event)
        try context.save()

        XCTAssertTrue(availableOutcomeOptions(for: event).contains(.unknown))

        // Simulate the binding setter: write the new rawValue + persist.
        event.outcome = TemptationEvent.Outcome.resisted.rawValue
        try context.save()

        // Once recorded, .unknown is no longer offered for that event.
        XCTAssertFalse(availableOutcomeOptions(for: event).contains(.unknown))
        XCTAssertEqual(availableOutcomeOptions(for: event), [.resisted, .gaveIn])
    }

    func testOutcomeBindingSetterWritesRawValueAndPersists() throws {
        // Exercises the same mutation the EventDetailSheet outcomeBinding setter performs:
        //   event.outcome = newValue.rawValue; try? modelContext.save()
        let habit = TestHelpers.makeHabit()
        context.insert(habit)
        let event = TestHelpers.makeEvent(habit: habit, outcome: "resisted")
        context.insert(event)
        try context.save()
        let eventId = event.id

        event.outcome = TemptationEvent.Outcome.gaveIn.rawValue
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<TemptationEvent>())
        XCTAssertEqual(fetched.first { $0.id == eventId }?.outcome, "gave_in")
    }

    // MARK: - Fetch Habits Refresh

    func testFetchHabitsRefreshesAfterNewHabitAdded() throws {
        let vm = LogViewModel(modelContext: context)
        XCTAssertTrue(vm.habits.isEmpty)

        // Add a habit externally
        let habit = TestHelpers.makeHabit(name: "Smoking")
        context.insert(habit)
        try context.save()

        vm.fetchHabits()
        XCTAssertEqual(vm.habits.count, 1)
        XCTAssertEqual(vm.habits.first?.name, "Smoking")
    }
}
