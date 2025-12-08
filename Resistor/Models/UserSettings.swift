import Foundation
import SwiftData

@Model
final class UserSettings {
    @Attribute(.unique) var id: UUID
    var defaultHabitId: UUID?
    var showContextPrompt: Bool
    var dailyReminderEnabled: Bool
    var dailyReminderHour: Int?
    var dailyReminderMinute: Int?
    var hasCompletedOnboarding: Bool

    init(
        id: UUID = UUID(),
        defaultHabitId: UUID? = nil,
        showContextPrompt: Bool = true,
        dailyReminderEnabled: Bool = false,
        dailyReminderHour: Int? = nil,
        dailyReminderMinute: Int? = nil,
        hasCompletedOnboarding: Bool = false
    ) {
        self.id = id
        self.defaultHabitId = defaultHabitId
        self.showContextPrompt = showContextPrompt
        self.dailyReminderEnabled = dailyReminderEnabled
        self.dailyReminderHour = dailyReminderHour
        self.dailyReminderMinute = dailyReminderMinute
        self.hasCompletedOnboarding = hasCompletedOnboarding
    }
}
