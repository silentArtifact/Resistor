import Foundation
import SwiftData
import SwiftUI

@Model
final class UserSettings {
    var id: UUID = UUID()
    /// Orphaned (issue #60): nothing reads this. The default habit is the first
    /// one in `Habit.displayOrder`, so the drag order the user can already see
    /// *is* the setting — two orderings could disagree, and did. Kept because a
    /// Production CloudKit field can never be removed, and still merged below so
    /// the value survives intact if the setting is ever brought back.
    var defaultHabitId: UUID?
    var showContextPrompt: Bool = true
    var accentColorHex: String?
    var hasCompletedOnboarding: Bool = false

    init(
        id: UUID = UUID(),
        defaultHabitId: UUID? = nil,
        showContextPrompt: Bool = true,
        accentColorHex: String? = nil,
        hasCompletedOnboarding: Bool = false
    ) {
        self.id = id
        self.defaultHabitId = defaultHabitId
        self.showContextPrompt = showContextPrompt
        self.accentColorHex = accentColorHex
        self.hasCompletedOnboarding = hasCompletedOnboarding
    }
}

// MARK: - Singleton Repair

extension UserSettings {
    /// Collapses a duplicated settings "singleton" down to one row.
    ///
    /// CloudKit forbids `@Attribute(.unique)`, so nothing stops two devices —
    /// the phone and the watch, which sync through the same container — from
    /// each creating this record before either has seen the other's. Every read
    /// in the app is `userSettings.first` on a `@Query` with no sort descriptor,
    /// so with two rows present the app answers *differently from launch to
    /// launch*: one run resolves the user's default habit, the next resolves a
    /// `defaultHabitId` left pointing at a habit that no longer exists.
    ///
    /// The survivor is the lowest `id`. That is arbitrary but *stable*, and
    /// identical on every device, so two devices repairing at the same time
    /// converge on the same keeper instead of deleting each other's.
    ///
    /// Fields are merged rather than inherited from the keeper, because the
    /// duplicates hold real choices the user made on whichever device wrote
    /// them. Each field takes the most explicit value present: onboarding counts
    /// as done if *any* row says so (otherwise a stale row could re-trigger the
    /// first-run flow over live data), the context prompt counts as off if any
    /// row turned it off, and the accent is the first one actually set.
    ///
    /// - Returns: the surviving settings row, or `nil` if there were none.
    @discardableResult
    static func mergeDuplicates(
        _ settings: [UserSettings],
        habits: [Habit],
        in context: ModelContext
    ) -> UserSettings? {
        let ordered = settings.sorted { $0.id.uuidString < $1.id.uuidString }
        guard let keeper = ordered.first else { return nil }
        guard ordered.count > 1 else { return keeper }

        keeper.hasCompletedOnboarding = ordered.contains(where: \.hasCompletedOnboarding)
        keeper.showContextPrompt = !ordered.contains { !$0.showContextPrompt }
        keeper.accentColorHex = ordered.compactMap(\.accentColorHex).first

        // Prefer a default habit that actually resolves. Nothing reads this any
        // more (see the property), but the merge is kept so a revived setting
        // wouldn't inherit whichever of two rows happened to win. Falling back to
        // the first non-nil id rather than to nil matters during a CloudKit
        // import, when the settings rows can arrive before the habits they point
        // at — nilling it there would silently discard the user's choice.
        let habitIds = Set(habits.map(\.id))
        let candidates = ordered.compactMap(\.defaultHabitId)
        keeper.defaultHabitId = candidates.first { habitIds.contains($0) } ?? candidates.first

        for duplicate in ordered.dropFirst() {
            context.delete(duplicate)
        }
        return keeper
    }
}

// MARK: - Accent Palette

extension UserSettings {
    /// The nine accent hues offered in Settings. Lives here rather than on the
    /// settings screen because it is the set of values `accentColorHex` can
    /// hold, and three separate views need to resolve it.
    static let accentPalette: [(name: String, hex: String)] = [
        ("Slate Blue", "#6B7FA3"),
        ("Storm Gray", "#7A7F8A"),
        ("Sage", "#7A8F7A"),
        ("Dusty Rose", "#A37A7A"),
        ("Copper", "#A3897A"),
        ("Lavender", "#8A7FA3"),
        ("Teal", "#6B9E9E"),
        ("Charcoal", "#5A5A5F"),
        ("Dusk", "#8A7A99"),
    ]

    /// What `nil` means — i.e. what a user who never opens Settings sees.
    ///
    /// This used to fall through to the system tint, which meant the entire
    /// first run, onboarding included, was iOS blue: the one screen guaranteed
    /// to be seen by everyone was the one screen with none of the app's own
    /// colour in it. Lavender because it's the least default-looking hue in the
    /// set and it reads on both backgrounds.
    static let defaultAccentHex = "#8A7FA3"

    static var defaultAccentColor: Color {
        Color(hex: defaultAccentHex) ?? .blue
    }
}
