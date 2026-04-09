import XCTest
import SwiftData
@testable import Resistor

@MainActor
final class HabitsViewModelTests: XCTestCase {

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

    // MARK: - Fetch & Sorting

    func testFetchHabitsSortsActiveBeforeArchived() throws {
        let archived = TestHelpers.makeHabit(name: "Archived", isArchived: true, createdAt: Date.distantPast)
        let active = TestHelpers.makeHabit(name: "Active", isArchived: false, createdAt: Date())
        context.insert(archived)
        context.insert(active)
        try context.save()

        let vm = HabitsViewModel(modelContext: context)

        XCTAssertEqual(vm.habits.count, 2)
        XCTAssertEqual(vm.habits[0].name, "Active")
        XCTAssertEqual(vm.habits[1].name, "Archived")
    }

    func testActiveHabitsFilter() throws {
        let active1 = TestHelpers.makeHabit(name: "Active1")
        let active2 = TestHelpers.makeHabit(name: "Active2")
        let archived = TestHelpers.makeHabit(name: "Archived", isArchived: true)
        context.insert(active1)
        context.insert(active2)
        context.insert(archived)
        try context.save()

        let vm = HabitsViewModel(modelContext: context)

        XCTAssertEqual(vm.activeHabits.count, 2)
        XCTAssertEqual(vm.archivedHabits.count, 1)
    }

    func testFetchHabitsHandlesEmptyDatabase() throws {
        let vm = HabitsViewModel(modelContext: context)
        XCTAssertTrue(vm.habits.isEmpty)
        XCTAssertTrue(vm.activeHabits.isEmpty)
        XCTAssertTrue(vm.archivedHabits.isEmpty)
    }

    // MARK: - Create Habit

    func testSaveNewHabitCreatesHabit() throws {
        let vm = HabitsViewModel(modelContext: context)
        vm.prepareNewHabit()
        vm.habitName = "Smoking"
        vm.habitDescription = "Quit smoking"
        vm.selectedColorHex = "#FF3B30"
        vm.selectedIconName = "cigarette.fill"

        vm.saveHabit()

        XCTAssertEqual(vm.habits.count, 1)
        XCTAssertEqual(vm.habits.first?.name, "Smoking")
        XCTAssertEqual(vm.habits.first?.habitDescription, "Quit smoking")
        XCTAssertEqual(vm.habits.first?.colorHex, "#FF3B30")
        XCTAssertEqual(vm.habits.first?.iconName, "cigarette.fill")
    }

    func testSaveHabitTrimsWhitespace() throws {
        let vm = HabitsViewModel(modelContext: context)
        vm.prepareNewHabit()
        vm.habitName = "  Smoking  "

        vm.saveHabit()

        XCTAssertEqual(vm.habits.first?.name, "Smoking")
    }

    func testSaveHabitConvertsEmptyDescriptionToNil() throws {
        let vm = HabitsViewModel(modelContext: context)
        vm.prepareNewHabit()
        vm.habitName = "Test"
        vm.habitDescription = ""

        vm.saveHabit()

        XCTAssertNil(vm.habits.first?.habitDescription)
    }

    func testSaveHabitRejectsEmptyName() throws {
        let vm = HabitsViewModel(modelContext: context)
        vm.prepareNewHabit()
        vm.habitName = "   "

        vm.saveHabit()

        XCTAssertTrue(vm.habits.isEmpty)
    }

    func testCanSaveValidation() throws {
        let vm = HabitsViewModel(modelContext: context)
        vm.habitName = ""
        XCTAssertFalse(vm.canSave)

        vm.habitName = "   "
        XCTAssertFalse(vm.canSave)

        vm.habitName = "Valid"
        XCTAssertTrue(vm.canSave)
    }

    // MARK: - Edit Habit

    func testSaveHabitUpdatesExisting() throws {
        let habit = TestHelpers.makeHabit(name: "Old Name")
        context.insert(habit)
        try context.save()

        let vm = HabitsViewModel(modelContext: context)
        vm.prepareEditHabit(habit)

        XCTAssertEqual(vm.habitName, "Old Name")
        XCTAssertTrue(vm.isEditing)

        vm.habitName = "New Name"
        vm.saveHabit()

        XCTAssertEqual(vm.habits.first?.name, "New Name")
    }

    func testPrepareEditPopulatesFormFields() throws {
        let habit = TestHelpers.makeHabit(
            name: "Test",
            habitDescription: "Desc",
            colorHex: "#FF0000",
            iconName: "star.fill"
        )
        context.insert(habit)
        try context.save()

        let vm = HabitsViewModel(modelContext: context)
        vm.prepareEditHabit(habit)

        XCTAssertEqual(vm.habitName, "Test")
        XCTAssertEqual(vm.habitDescription, "Desc")
        XCTAssertEqual(vm.selectedColorHex, "#FF0000")
        XCTAssertEqual(vm.selectedIconName, "star.fill")
    }

    func testPrepareEditWithNilDescriptionUsesEmptyString() throws {
        let habit = TestHelpers.makeHabit(name: "Test", habitDescription: nil)
        context.insert(habit)
        try context.save()

        let vm = HabitsViewModel(modelContext: context)
        vm.prepareEditHabit(habit)

        XCTAssertEqual(vm.habitDescription, "")
    }

    // MARK: - Delete Habit (Cascading)

    func testDeleteHabitRemovesHabitAndEvents() throws {
        let habit = TestHelpers.makeHabit(name: "ToDelete")
        context.insert(habit)

        let event1 = TestHelpers.makeEvent(habit: habit, outcome: "resisted")
        let event2 = TestHelpers.makeEvent(habit: habit, outcome: "gave_in")
        context.insert(event1)
        context.insert(event2)
        try context.save()

        let vm = HabitsViewModel(modelContext: context)
        XCTAssertEqual(vm.habits.count, 1)

        vm.confirmDelete(habit)
        XCTAssertTrue(vm.showDeleteConfirmation)

        vm.deleteHabit()

        XCTAssertTrue(vm.habits.isEmpty)

        // Verify events are also deleted
        let eventDescriptor = FetchDescriptor<TemptationEvent>()
        let remainingEvents = try context.fetch(eventDescriptor)
        XCTAssertTrue(remainingEvents.isEmpty)
    }

    func testDeleteHabitWithNoEvents() throws {
        let habit = TestHelpers.makeHabit(name: "NoEvents")
        context.insert(habit)
        try context.save()

        let vm = HabitsViewModel(modelContext: context)
        vm.confirmDelete(habit)
        vm.deleteHabit()

        XCTAssertTrue(vm.habits.isEmpty)
    }

    func testDeleteHabitDoesNothingWithoutConfirm() throws {
        let habit = TestHelpers.makeHabit()
        context.insert(habit)
        try context.save()

        let vm = HabitsViewModel(modelContext: context)
        // Call delete without setting habitToDelete
        vm.deleteHabit()

        XCTAssertEqual(vm.habits.count, 1)
    }

    func testCancelDeleteResetsState() throws {
        let habit = TestHelpers.makeHabit()
        context.insert(habit)
        try context.save()

        let vm = HabitsViewModel(modelContext: context)
        vm.confirmDelete(habit)
        XCTAssertTrue(vm.showDeleteConfirmation)
        XCTAssertNotNil(vm.habitToDelete)

        vm.cancelDelete()
        XCTAssertFalse(vm.showDeleteConfirmation)
        XCTAssertNil(vm.habitToDelete)
        XCTAssertEqual(vm.habits.count, 1)
    }

    // MARK: - Archive/Unarchive

    func testArchiveHabit() throws {
        let habit = TestHelpers.makeHabit(name: "ToArchive")
        context.insert(habit)
        try context.save()

        let vm = HabitsViewModel(modelContext: context)
        vm.archiveHabit(habit)

        XCTAssertTrue(habit.isArchived)
        XCTAssertEqual(vm.archivedHabits.count, 1)
        XCTAssertTrue(vm.activeHabits.isEmpty)
    }

    func testUnarchiveHabit() throws {
        let habit = TestHelpers.makeHabit(name: "Archived", isArchived: true)
        context.insert(habit)
        try context.save()

        let vm = HabitsViewModel(modelContext: context)
        vm.unarchiveHabit(habit)

        XCTAssertFalse(habit.isArchived)
        XCTAssertEqual(vm.activeHabits.count, 1)
        XCTAssertTrue(vm.archivedHabits.isEmpty)
    }

    // MARK: - Sheet State Management

    func testPrepareNewHabitResetsFormFields() throws {
        let vm = HabitsViewModel(modelContext: context)

        // Set some values
        vm.habitName = "Old"
        vm.habitDescription = "Old Desc"
        vm.selectedColorHex = "#FF0000"
        vm.selectedIconName = "star.fill"

        vm.prepareNewHabit()

        XCTAssertEqual(vm.habitName, "")
        XCTAssertEqual(vm.habitDescription, "")
        XCTAssertEqual(vm.selectedColorHex, "#007AFF")
        XCTAssertEqual(vm.selectedIconName, "circle.fill")
        XCTAssertTrue(vm.showAddHabitSheet)
        XCTAssertFalse(vm.isEditing)
    }

    func testDismissSheetResetsAllState() throws {
        let vm = HabitsViewModel(modelContext: context)

        vm.habitName = "Test"
        vm.habitDescription = "Desc"
        vm.selectedColorHex = "#FF0000"
        vm.selectedIconName = "star.fill"
        vm.showAddHabitSheet = true

        vm.dismissSheet()

        XCTAssertFalse(vm.showAddHabitSheet)
        XCTAssertNil(vm.habitToEdit)
        XCTAssertEqual(vm.habitName, "")
        XCTAssertEqual(vm.habitDescription, "")
        XCTAssertEqual(vm.selectedColorHex, "#007AFF")
        XCTAssertEqual(vm.selectedIconName, "circle.fill")
    }

    // MARK: - Static Data

    func testAvailableColorsNotEmpty() {
        XCTAssertFalse(HabitsViewModel.availableColors.isEmpty)
        for color in HabitsViewModel.availableColors {
            XCTAssertFalse(color.name.isEmpty)
            XCTAssertTrue(color.hex.hasPrefix("#"))
        }
    }

    func testAvailableIconsNotEmpty() {
        XCTAssertFalse(HabitsViewModel.availableIcons.isEmpty)
        for icon in HabitsViewModel.availableIcons {
            XCTAssertFalse(icon.isEmpty)
        }
    }
}
