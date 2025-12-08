import Foundation
import SwiftData
import Observation

@Observable
final class OnboardingViewModel {
    private var modelContext: ModelContext

    var habitName: String = ""
    var habitDescription: String = ""
    var selectedColorHex: String = "#007AFF"
    var selectedIconName: String = "circle.fill"

    var canCreateHabit: Bool {
        !habitName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func createFirstHabit() -> Bool {
        let trimmedName = habitName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }

        let newHabit = Habit(
            name: trimmedName,
            habitDescription: habitDescription.isEmpty ? nil : habitDescription,
            colorHex: selectedColorHex,
            iconName: selectedIconName
        )
        modelContext.insert(newHabit)

        // Create or update user settings
        let settingsDescriptor = FetchDescriptor<UserSettings>()
        do {
            let existingSettings = try modelContext.fetch(settingsDescriptor)
            if let settings = existingSettings.first {
                settings.hasCompletedOnboarding = true
                settings.defaultHabitId = newHabit.id
            } else {
                let newSettings = UserSettings(
                    defaultHabitId: newHabit.id,
                    hasCompletedOnboarding: true
                )
                modelContext.insert(newSettings)
            }

            try modelContext.save()
            return true
        } catch {
            print("Failed to save first habit: \(error)")
            return false
        }
    }

    func skipOnboarding() -> Bool {
        let settingsDescriptor = FetchDescriptor<UserSettings>()
        do {
            let existingSettings = try modelContext.fetch(settingsDescriptor)
            if let settings = existingSettings.first {
                settings.hasCompletedOnboarding = true
            } else {
                let newSettings = UserSettings(hasCompletedOnboarding: true)
                modelContext.insert(newSettings)
            }

            try modelContext.save()
            return true
        } catch {
            print("Failed to skip onboarding: \(error)")
            return false
        }
    }
}
