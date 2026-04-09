import Foundation
import SwiftData
import Observation

@Observable
final class HabitsViewModel {
    private var modelContext: ModelContext

    var habits: [Habit] = []
    var showAddHabitSheet: Bool = false
    var habitToEdit: Habit?
    var showDeleteConfirmation: Bool = false
    var habitToDelete: Habit?

    // Form fields for add/edit
    var habitName: String = ""
    var habitDescription: String = ""
    var selectedColorHex: String = "#007AFF"
    var selectedIconName: String = "circle.fill"

    var isEditing: Bool {
        habitToEdit != nil
    }

    var canSave: Bool {
        !habitName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        fetchHabits()
    }

    func fetchHabits() {
        let descriptor = FetchDescriptor<Habit>(
            sortBy: [SortDescriptor(\.createdAt)]
        )
        do {
            let all = try modelContext.fetch(descriptor)
            habits = all.sorted { !$0.isArchived && $1.isArchived }
        } catch {
            print("Failed to fetch habits: \(error)")
            habits = []
        }
    }

    var activeHabits: [Habit] {
        habits.filter { !$0.isArchived }
    }

    var archivedHabits: [Habit] {
        habits.filter { $0.isArchived }
    }

    // MARK: - Add/Edit Habit

    func prepareNewHabit() {
        habitToEdit = nil
        habitName = ""
        habitDescription = ""
        selectedColorHex = "#007AFF"
        selectedIconName = "circle.fill"
        showAddHabitSheet = true
    }

    func prepareEditHabit(_ habit: Habit) {
        habitToEdit = habit
        habitName = habit.name
        habitDescription = habit.habitDescription ?? ""
        selectedColorHex = habit.colorHex ?? "#007AFF"
        selectedIconName = habit.iconName ?? "circle.fill"
        showAddHabitSheet = true
    }

    func saveHabit() {
        let trimmedName = habitName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        if let existingHabit = habitToEdit {
            // Update existing
            existingHabit.name = trimmedName
            existingHabit.habitDescription = habitDescription.isEmpty ? nil : habitDescription
            existingHabit.colorHex = selectedColorHex
            existingHabit.iconName = selectedIconName
        } else {
            // Create new
            let newHabit = Habit(
                name: trimmedName,
                habitDescription: habitDescription.isEmpty ? nil : habitDescription,
                colorHex: selectedColorHex,
                iconName: selectedIconName
            )
            modelContext.insert(newHabit)
        }

        do {
            try modelContext.save()
            fetchHabits()
            dismissSheet()
        } catch {
            print("Failed to save habit: \(error)")
        }
    }

    func dismissSheet() {
        showAddHabitSheet = false
        habitToEdit = nil
        habitName = ""
        habitDescription = ""
        selectedColorHex = "#007AFF"
        selectedIconName = "circle.fill"
    }

    // MARK: - Archive/Delete

    func confirmDelete(_ habit: Habit) {
        habitToDelete = habit
        showDeleteConfirmation = true
    }

    func deleteHabit() {
        guard let habit = habitToDelete else { return }
        modelContext.delete(habit)

        do {
            try modelContext.save()
            fetchHabits()
        } catch {
            print("Failed to delete habit: \(error)")
        }

        habitToDelete = nil
        showDeleteConfirmation = false
    }

    func archiveHabit(_ habit: Habit) {
        habit.isArchived = true

        do {
            try modelContext.save()
            fetchHabits()
        } catch {
            print("Failed to archive habit: \(error)")
        }
    }

    func unarchiveHabit(_ habit: Habit) {
        habit.isArchived = false

        do {
            try modelContext.save()
            fetchHabits()
        } catch {
            print("Failed to unarchive habit: \(error)")
        }
    }

    func cancelDelete() {
        habitToDelete = nil
        showDeleteConfirmation = false
    }
}

// MARK: - Available Colors and Icons

extension HabitsViewModel {
    static let availableColors: [(name: String, hex: String)] = [
        ("Blue", "#007AFF"),
        ("Green", "#34C759"),
        ("Orange", "#FF9500"),
        ("Red", "#FF3B30"),
        ("Purple", "#AF52DE"),
        ("Pink", "#FF2D55"),
        ("Teal", "#5AC8FA"),
        ("Indigo", "#5856D6"),
        ("Yellow", "#FFCC00"),
        ("Gray", "#8E8E93")
    ]

    static let availableIcons: [String] = [
        "circle.fill",
        "star.fill",
        "heart.fill",
        "bolt.fill",
        "flame.fill",
        "leaf.fill",
        "drop.fill",
        "moon.fill",
        "sun.max.fill",
        "cloud.fill",
        "cart.fill",
        "creditcard.fill",
        "phone.fill",
        "tv.fill",
        "gamecontroller.fill",
        "cup.and.saucer.fill",
        "fork.knife",
        "wineglass.fill",
        "cigarette.fill",
        "pills.fill"
    ]
}
