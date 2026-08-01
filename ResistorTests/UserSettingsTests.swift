import XCTest
import SwiftData
import SwiftUI
@testable import Resistor

@MainActor
final class UserSettingsTests: XCTestCase {

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

    // MARK: - Default Initialization

    func testDefaultValues() {
        let settings = UserSettings()

        XCTAssertNotNil(settings.id)
        XCTAssertNil(settings.defaultHabitId)
        XCTAssertTrue(settings.showContextPrompt)
        XCTAssertNil(settings.accentColorHex)
        XCTAssertFalse(settings.hasCompletedOnboarding)
    }

    // MARK: - Custom Initialization

    func testCustomValues() {
        let habitId = UUID()
        let settings = UserSettings(
            defaultHabitId: habitId,
            showContextPrompt: false,
            accentColorHex: "#FF3B30",
            hasCompletedOnboarding: true
        )

        XCTAssertEqual(settings.defaultHabitId, habitId)
        XCTAssertFalse(settings.showContextPrompt)
        XCTAssertEqual(settings.accentColorHex, "#FF3B30")
        XCTAssertTrue(settings.hasCompletedOnboarding)
    }

    // MARK: - Persistence

    func testPersistAndFetch() throws {
        let habitId = UUID()
        let settings = UserSettings(
            defaultHabitId: habitId,
            showContextPrompt: false,
            accentColorHex: "#5856D6",
            hasCompletedOnboarding: true
        )
        context.insert(settings)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<UserSettings>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.defaultHabitId, habitId)
        XCTAssertFalse(fetched.first!.showContextPrompt)
        XCTAssertEqual(fetched.first?.accentColorHex, "#5856D6")
        XCTAssertTrue(fetched.first!.hasCompletedOnboarding)
    }

    func testSingletonQueryPattern() throws {
        let settings = UserSettings(hasCompletedOnboarding: true)
        context.insert(settings)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<UserSettings>())
        // App uses `fetched.first` as singleton access
        XCTAssertEqual(fetched.count, 1)
        XCTAssertNotNil(fetched.first)
    }

    // MARK: - Mutation

    func testUpdateFields() throws {
        let settings = UserSettings()
        context.insert(settings)
        try context.save()

        let habitId = UUID()
        settings.defaultHabitId = habitId
        settings.showContextPrompt = false
        settings.accentColorHex = "#34C759"
        settings.hasCompletedOnboarding = true
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<UserSettings>())
        XCTAssertEqual(fetched.first?.defaultHabitId, habitId)
        XCTAssertFalse(fetched.first!.showContextPrompt)
        XCTAssertEqual(fetched.first?.accentColorHex, "#34C759")
        XCTAssertTrue(fetched.first!.hasCompletedOnboarding)
    }

    // MARK: - Accent Color Hex Compatibility

    func testAccentColorHexParsesWithColorExtension() {
        let settings = UserSettings(accentColorHex: "#007AFF")
        let color = Color(hex: settings.accentColorHex ?? "")
        XCTAssertNotNil(color)
    }

    func testNilAccentColorHexReturnsNilColor() {
        let settings = UserSettings(accentColorHex: nil)
        XCTAssertNil(settings.accentColorHex)
    }

    func testAllAppAccentColorsPersistCorrectly() throws {
        let appColors = ["#007AFF", "#34C759", "#FF9500", "#FF3B30", "#AF52DE",
                         "#FF2D55", "#5AC8FA", "#5856D6", "#FFCC00", "#8E8E93"]

        for hex in appColors {
            let settings = UserSettings(accentColorHex: hex)
            context.insert(settings)
        }
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<UserSettings>())
        let fetchedHexes = fetched.compactMap { $0.accentColorHex }
        for hex in appColors {
            XCTAssertTrue(fetchedHexes.contains(hex), "Missing persisted color: \(hex)")
        }
    }

    // MARK: - Unique IDs

    func testEachSettingsInstanceHasUniqueId() {
        let settings1 = UserSettings()
        let settings2 = UserSettings()
        XCTAssertNotEqual(settings1.id, settings2.id)
    }

    // MARK: - Duplicate Repair

    /// The state found on a real device on 2026-08-01: two settings rows, one
    /// pointing at a habit that no longer exists. Every read site takes
    /// `userSettings.first` on an unsorted query, so which one won changed
    /// between launches.
    func testMergeDuplicatesKeepsOneRowAndTheResolvableDefaultHabit() throws {
        let habit = TestHelpers.makeHabit(name: "Sugar")
        context.insert(habit)

        let dangling = UserSettings(defaultHabitId: UUID(), hasCompletedOnboarding: true)
        let good = UserSettings(defaultHabitId: habit.id, hasCompletedOnboarding: true)
        context.insert(dangling)
        context.insert(good)
        try context.save()

        UserSettings.mergeDuplicates([dangling, good], habits: [habit], in: context)
        try context.save()

        let remaining = try context.fetch(FetchDescriptor<UserSettings>())
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.defaultHabitId, habit.id, "Kept the id that points at nothing")
    }

    /// The keeper is the lowest `id` regardless of the order the rows arrive in,
    /// so two devices repairing at once pick the same survivor instead of
    /// deleting each other's.
    func testMergeDuplicatesPicksTheSameKeeperFromEitherOrder() {
        let a = UserSettings(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!)
        let b = UserSettings(id: UUID(uuidString: "FFFFFFFF-0000-0000-0000-00000000000F")!)
        [a, b].forEach(context.insert)

        XCTAssertEqual(UserSettings.mergeDuplicates([a, b], habits: [], in: context)?.id, a.id)
        XCTAssertEqual(UserSettings.mergeDuplicates([b, a], habits: [], in: context)?.id, a.id)
    }

    /// A row that never completed onboarding must not drag a completed one back
    /// to the first-run flow — that is the failure that looks like data loss.
    func testMergeDuplicatesKeepsExplicitChoicesFromEitherRow() {
        let stale = UserSettings(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            hasCompletedOnboarding: false
        )
        let real = UserSettings(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            showContextPrompt: false,
            accentColorHex: "#6B9E9E",
            hasCompletedOnboarding: true
        )
        [stale, real].forEach(context.insert)

        let keeper = UserSettings.mergeDuplicates([stale, real], habits: [], in: context)

        XCTAssertEqual(keeper?.id, stale.id, "Keeper should still be the lowest id")
        XCTAssertTrue(keeper?.hasCompletedOnboarding == true)
        XCTAssertFalse(keeper?.showContextPrompt == true)
        XCTAssertEqual(keeper?.accentColorHex, "#6B9E9E")
    }
}
