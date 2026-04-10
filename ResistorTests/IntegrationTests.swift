import XCTest
import SwiftData
@testable import Resistor

@MainActor
final class IntegrationTests: XCTestCase {

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

    // MARK: - Archive Habit Hides From LogViewModel

    func testArchivingHabitRemovesItFromLogViewModel() throws {
        let habit = TestHelpers.makeHabit(name: "Smoking")
        context.insert(habit)
        try context.save()

        let logVM = LogViewModel(modelContext: context)
        XCTAssertEqual(logVM.habits.count, 1)

        // Archive via HabitsViewModel
        let habitsVM = HabitsViewModel(modelContext: context)
        habitsVM.archiveHabit(habit)

        // LogViewModel should no longer see it after refresh
        logVM.fetchHabits()
        XCTAssertTrue(logVM.habits.isEmpty)
    }

    // MARK: - Archive Habit Hides From InsightsViewModel

    func testArchivingHabitRemovesItFromInsightsViewModel() throws {
        let habit = TestHelpers.makeHabit(name: "Smoking")
        context.insert(habit)
        try context.save()

        let insightsVM = InsightsViewModel(modelContext: context)
        XCTAssertEqual(insightsVM.habits.count, 1)

        let habitsVM = HabitsViewModel(modelContext: context)
        habitsVM.archiveHabit(habit)

        insightsVM.fetchHabits()
        XCTAssertTrue(insightsVM.habits.isEmpty)
    }

    // MARK: - Delete Habit Preserves Other Habits' Events

    func testDeletingHabitDoesNotAffectOtherHabitsEvents() throws {
        let habit1 = TestHelpers.makeHabit(name: "Smoking")
        let habit2 = TestHelpers.makeHabit(name: "Drinking")
        context.insert(habit1)
        context.insert(habit2)

        let event1 = TestHelpers.makeEvent(habit: habit1, outcome: "resisted")
        let event2 = TestHelpers.makeEvent(habit: habit2, outcome: "gave_in")
        let event3 = TestHelpers.makeEvent(habit: habit2, outcome: "resisted")
        context.insert(event1)
        context.insert(event2)
        context.insert(event3)
        try context.save()

        // Delete habit1 via HabitsViewModel
        let habitsVM = HabitsViewModel(modelContext: context)
        habitsVM.confirmDelete(habit1)
        habitsVM.deleteHabit()

        // habit2's events should be untouched
        let remainingEvents = try context.fetch(FetchDescriptor<TemptationEvent>())
        XCTAssertEqual(remainingEvents.count, 2)
        for event in remainingEvents {
            XCTAssertEqual(event.habit?.name, "Drinking")
        }
    }

    // MARK: - Full Logging Flow

    func testFullLoggingFlow() throws {
        // Step 1: Create a habit via onboarding
        let onboardingVM = OnboardingViewModel(modelContext: context)
        onboardingVM.habitName = "Smoking"
        onboardingVM.habitDescription = "Quit smoking"
        onboardingVM.selectedColorHex = "#FF3B30"
        onboardingVM.selectedIconName = "cigarette.fill"

        let created = onboardingVM.createFirstHabit()
        XCTAssertTrue(created)

        // Step 2: Fetch the default habit ID from settings
        let settings = try context.fetch(FetchDescriptor<UserSettings>())
        let defaultHabitId = settings.first?.defaultHabitId
        XCTAssertNotNil(defaultHabitId)

        // Step 3: Log a temptation via LogViewModel
        let logVM = LogViewModel(modelContext: context, defaultHabitId: defaultHabitId)
        XCTAssertEqual(logVM.habits.count, 1)
        XCTAssertEqual(logVM.selectedHabit?.name, "Smoking")

        logVM.logTemptation()
        XCTAssertNotNil(logVM.lastLoggedEvent)

        // Step 4: Update context
        logVM.updateEventContext(contextTags: ["stressed", "at_work"], note: "After meeting")
        XCTAssertEqual(logVM.lastLoggedEvent?.contextTags, ["stressed", "at_work"])
        XCTAssertEqual(logVM.lastLoggedEvent?.note, "After meeting")

        // Step 5: Verify everything persisted correctly
        let events = try context.fetch(FetchDescriptor<TemptationEvent>())
        XCTAssertEqual(events.count, 1)
        let event = events.first!
        XCTAssertEqual(event.contextTags, ["stressed", "at_work"])
        XCTAssertEqual(event.note, "After meeting")
        XCTAssertEqual(event.habit?.name, "Smoking")

        // Step 8: Verify InsightsViewModel can see the event
        let insightsVM = InsightsViewModel(modelContext: context)
        XCTAssertTrue(insightsVM.hasData)
        XCTAssertEqual(insightsVM.totalEventsInRange, 1)
        XCTAssertEqual(insightsVM.resistedCount, 1)
        XCTAssertEqual(insightsVM.resistedPercentage, 100)
    }

    // MARK: - Unarchive Makes Habit Visible Again

    func testUnarchiveHabitRestoresVisibilityInLogViewModel() throws {
        let habit = TestHelpers.makeHabit(name: "Smoking", isArchived: true)
        context.insert(habit)
        try context.save()

        let logVM = LogViewModel(modelContext: context)
        XCTAssertTrue(logVM.habits.isEmpty)

        // Unarchive
        let habitsVM = HabitsViewModel(modelContext: context)
        habitsVM.unarchiveHabit(habit)

        logVM.fetchHabits()
        XCTAssertEqual(logVM.habits.count, 1)
        XCTAssertEqual(logVM.habits.first?.name, "Smoking")
    }

    // MARK: - Delete Habit With Events Then Check Insights

    func testDeleteHabitThenInsightsHandlesGracefully() throws {
        let habit1 = TestHelpers.makeHabit(name: "Smoking", createdAt: Date.distantPast)
        let habit2 = TestHelpers.makeHabit(name: "Drinking", createdAt: Date())
        context.insert(habit1)
        context.insert(habit2)

        let event = TestHelpers.makeEvent(habit: habit1, outcome: "resisted")
        context.insert(event)
        try context.save()

        // Delete habit1
        let habitsVM = HabitsViewModel(modelContext: context)
        habitsVM.confirmDelete(habit1)
        habitsVM.deleteHabit()

        // InsightsViewModel should still work with remaining habits
        let insightsVM = InsightsViewModel(modelContext: context)
        XCTAssertEqual(insightsVM.habits.count, 1)
        XCTAssertEqual(insightsVM.selectedHabit?.name, "Drinking")
        XCTAssertFalse(insightsVM.hasData) // Drinking has no events
    }

    // MARK: - Create Multiple Habits Then Log To Specific One

    func testLogToSpecificHabitAmongMultiple() throws {
        let habit1 = TestHelpers.makeHabit(name: "Smoking", createdAt: Date.distantPast)
        let habit2 = TestHelpers.makeHabit(name: "Drinking", createdAt: Date())
        let habit3 = TestHelpers.makeHabit(name: "Snacking", createdAt: Date.distantFuture)
        context.insert(habit1)
        context.insert(habit2)
        context.insert(habit3)
        try context.save()

        let logVM = LogViewModel(modelContext: context, defaultHabitId: habit2.id)
        XCTAssertEqual(logVM.selectedHabit?.name, "Drinking")

        logVM.logTemptation()

        // Event should be linked to Drinking, not to the other habits
        XCTAssertEqual(logVM.lastLoggedEvent?.habit?.name, "Drinking")
        XCTAssertEqual(habit2.safeEvents.count, 1)
        XCTAssertTrue(habit1.safeEvents.isEmpty)
        XCTAssertTrue(habit3.safeEvents.isEmpty)
    }
}
