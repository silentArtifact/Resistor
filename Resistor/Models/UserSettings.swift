import Foundation
import SwiftData
import SwiftUI

@Model
final class UserSettings {
    var id: UUID = UUID()
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
