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
}
