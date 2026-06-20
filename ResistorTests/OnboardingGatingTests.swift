import XCTest
import SwiftData
@testable import Resistor

/// Runtime verification of the onboarding gate (issue #52, UC-OB2 / UC-OB3).
///
/// The intro step itself is a view-only change with no ViewModel logic, so the
/// string/ordering assertions are source-verified. What *is* runtime-testable is
/// the gating contract the two-step flow depends on and must not break:
/// onboarding shows first-run only, completing OR skipping clears the gate, and
/// Delete All Data restores it. These tests reproduce ContentView's
/// `needsOnboarding` predicate against real SwiftData state.
@MainActor
final class OnboardingGatingTests: XCTestCase {

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

    /// Mirrors `ContentView.needsOnboarding` exactly: no settings -> show;
    /// otherwise gate on `hasCompletedOnboarding`.
    private func needsOnboarding() throws -> Bool {
        let settings = try context.fetch(FetchDescriptor<UserSettings>()).first
        guard let settings else { return true }
        return !settings.hasCompletedOnboarding
    }

    // MARK: - UC-OB3: first-run only

    func testFirstRunWithNoSettingsShowsOnboarding() throws {
        XCTAssertTrue(try needsOnboarding())
    }

    func testFreshSettingsDefaultShowsOnboarding() throws {
        // A freshly inserted UserSettings (e.g. via initializeSettingsIfNeeded)
        // defaults hasCompletedOnboarding = false, so the gate is still open.
        context.insert(UserSettings())
        try context.save()
        XCTAssertTrue(try needsOnboarding())
    }

    // MARK: - UC-OB2: completing the first-habit step clears the gate

    func testCompletingFirstHabitStepClearsGate() throws {
        let vm = OnboardingViewModel(modelContext: context)
        vm.habitName = "Smoking"

        XCTAssertTrue(vm.createFirstHabit())
        XCTAssertFalse(try needsOnboarding(),
                       "Onboarding must not reappear after creating the first habit")
    }

    // MARK: - UC-OB2: skipping the first-habit step also clears the gate

    func testSkippingFirstHabitStepClearsGate() throws {
        let vm = OnboardingViewModel(modelContext: context)

        XCTAssertTrue(vm.skipOnboarding())
        XCTAssertFalse(try needsOnboarding(),
                       "Onboarding must not reappear after skipping")
    }

    // MARK: - UC-OB3: never reappears in-app once completed

    func testGateStaysClosedAcrossReReads() throws {
        let vm = OnboardingViewModel(modelContext: context)
        vm.habitName = "Sugar"
        _ = vm.createFirstHabit()

        // Multiple reads simulate the app re-evaluating needsOnboarding on
        // every body render — it must remain false with no re-open path.
        XCTAssertFalse(try needsOnboarding())
        XCTAssertFalse(try needsOnboarding())
    }

    // MARK: - UC-OB3: reappears only after Delete All Data

    func testDeleteAllDataReopensGate() throws {
        // Complete onboarding first.
        let vm = OnboardingViewModel(modelContext: context)
        vm.habitName = "Smoking"
        _ = vm.createFirstHabit()
        XCTAssertFalse(try needsOnboarding())

        // Reproduce HabitsView.deleteAllData(): wipe everything, then insert a
        // fresh default UserSettings (hasCompletedOnboarding == false).
        // (ContextTag is omitted here only because the shared test ModelContainer
        // schema doesn't register it; the gate-reopen behavior depends on the
        // UserSettings reset, which is fully exercised below.)
        try context.delete(model: TemptationEvent.self)
        try context.delete(model: Habit.self)
        try context.delete(model: UserSettings.self)
        context.insert(UserSettings())
        try context.save()

        XCTAssertTrue(try needsOnboarding(),
                      "Onboarding must reappear after Delete All Data")

        // And the wipe actually removed the seeded habit.
        let habits = try context.fetch(FetchDescriptor<Habit>())
        XCTAssertTrue(habits.isEmpty)
    }
}
