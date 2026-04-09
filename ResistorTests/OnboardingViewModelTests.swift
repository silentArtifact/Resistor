import XCTest
import SwiftData
@testable import Resistor

@MainActor
final class OnboardingViewModelTests: XCTestCase {

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

    // MARK: - Validation

    func testCanCreateHabitWithValidName() {
        let vm = OnboardingViewModel(modelContext: context)
        vm.habitName = "Smoking"
        XCTAssertTrue(vm.canCreateHabit)
    }

    func testCannotCreateHabitWithEmptyName() {
        let vm = OnboardingViewModel(modelContext: context)
        vm.habitName = ""
        XCTAssertFalse(vm.canCreateHabit)
    }

    func testCannotCreateHabitWithWhitespaceName() {
        let vm = OnboardingViewModel(modelContext: context)
        vm.habitName = "   "
        XCTAssertFalse(vm.canCreateHabit)
    }

    // MARK: - Create First Habit

    func testCreateFirstHabitSucceeds() throws {
        let vm = OnboardingViewModel(modelContext: context)
        vm.habitName = "Smoking"
        vm.habitDescription = "Quit smoking"
        vm.selectedColorHex = "#FF3B30"
        vm.selectedIconName = "cigarette.fill"

        let result = vm.createFirstHabit()
        XCTAssertTrue(result)

        let habits = try context.fetch(FetchDescriptor<Habit>())
        XCTAssertEqual(habits.count, 1)
        XCTAssertEqual(habits.first?.name, "Smoking")
        XCTAssertEqual(habits.first?.habitDescription, "Quit smoking")
    }

    func testCreateFirstHabitSetsOnboardingComplete() throws {
        let vm = OnboardingViewModel(modelContext: context)
        vm.habitName = "Test"

        _ = vm.createFirstHabit()

        let settings = try context.fetch(FetchDescriptor<UserSettings>())
        XCTAssertEqual(settings.count, 1)
        XCTAssertTrue(settings.first!.hasCompletedOnboarding)
    }

    func testCreateFirstHabitSetsDefaultHabitId() throws {
        let vm = OnboardingViewModel(modelContext: context)
        vm.habitName = "Test"

        _ = vm.createFirstHabit()

        let habits = try context.fetch(FetchDescriptor<Habit>())
        let settings = try context.fetch(FetchDescriptor<UserSettings>())

        XCTAssertEqual(settings.first?.defaultHabitId, habits.first?.id)
    }

    func testCreateFirstHabitConvertsEmptyDescriptionToNil() throws {
        let vm = OnboardingViewModel(modelContext: context)
        vm.habitName = "Test"
        vm.habitDescription = ""

        _ = vm.createFirstHabit()

        let habits = try context.fetch(FetchDescriptor<Habit>())
        XCTAssertNil(habits.first?.habitDescription)
    }

    func testCreateFirstHabitFailsWithEmptyName() throws {
        let vm = OnboardingViewModel(modelContext: context)
        vm.habitName = ""

        let result = vm.createFirstHabit()
        XCTAssertFalse(result)

        let habits = try context.fetch(FetchDescriptor<Habit>())
        XCTAssertTrue(habits.isEmpty)
    }

    func testCreateFirstHabitUpdatesExistingSettings() throws {
        // Pre-create settings
        let existingSettings = UserSettings()
        context.insert(existingSettings)
        try context.save()

        let vm = OnboardingViewModel(modelContext: context)
        vm.habitName = "Test"

        _ = vm.createFirstHabit()

        let settings = try context.fetch(FetchDescriptor<UserSettings>())
        XCTAssertEqual(settings.count, 1)
        XCTAssertTrue(settings.first!.hasCompletedOnboarding)
    }

    // MARK: - Skip Onboarding

    func testSkipOnboardingCreatesSettings() throws {
        let vm = OnboardingViewModel(modelContext: context)

        let result = vm.skipOnboarding()
        XCTAssertTrue(result)

        let settings = try context.fetch(FetchDescriptor<UserSettings>())
        XCTAssertEqual(settings.count, 1)
        XCTAssertTrue(settings.first!.hasCompletedOnboarding)
        XCTAssertNil(settings.first?.defaultHabitId)
    }

    func testSkipOnboardingUpdatesExistingSettings() throws {
        let existingSettings = UserSettings()
        context.insert(existingSettings)
        try context.save()

        let vm = OnboardingViewModel(modelContext: context)

        let result = vm.skipOnboarding()
        XCTAssertTrue(result)

        let settings = try context.fetch(FetchDescriptor<UserSettings>())
        XCTAssertEqual(settings.count, 1)
        XCTAssertTrue(settings.first!.hasCompletedOnboarding)
    }

    func testSkipOnboardingDoesNotCreateHabit() throws {
        let vm = OnboardingViewModel(modelContext: context)

        _ = vm.skipOnboarding()

        let habits = try context.fetch(FetchDescriptor<Habit>())
        XCTAssertTrue(habits.isEmpty)
    }
}
