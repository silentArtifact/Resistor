import Foundation
import SwiftData

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
