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
    var selectedColorHex: String = HabitsViewModel.availableColors[0].hex
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
            sortBy: Habit.displayOrder
        )
        do {
            let all = try modelContext.fetch(descriptor)
            habits = all.sorted { ($0.isArchived ? 1 : 0) < ($1.isArchived ? 1 : 0) }
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
        selectedColorHex = HabitsViewModel.availableColors[0].hex
        selectedIconName = "circle.fill"
        showAddHabitSheet = true
    }

    func prepareEditHabit(_ habit: Habit) {
        habitToEdit = habit
        habitName = habit.name
        habitDescription = habit.habitDescription ?? ""
        selectedColorHex = habit.colorHex ?? HabitsViewModel.availableColors[0].hex
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
                iconName: selectedIconName,
                sortOrder: Habit.nextSortOrder(in: modelContext)
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
        selectedColorHex = HabitsViewModel.availableColors[0].hex
        selectedIconName = "circle.fill"
    }

    // MARK: - Reorder

    /// Applies a drag in the Active Habits list. Rewrites `sortOrder` for the
    /// whole active list rather than nudging the moved habit, so the stored
    /// order stays a dense 0..n-1 and can't drift into ties after repeated
    /// drags. Archived habits are left alone — they're a separate section and
    /// aren't draggable.
    func moveHabits(from source: IndexSet, to destination: Int) {
        var reordered = activeHabits
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, habit) in reordered.enumerated() {
            habit.sortOrder = index
        }

        do {
            try modelContext.save()
            fetchHabits()
        } catch {
            print("Failed to reorder habits: \(error)")
        }
    }

    // MARK: - Archive/Delete

    func confirmDelete(_ habit: Habit) {
        habitToDelete = habit
        showDeleteConfirmation = true
    }

    func deleteHabit() {
        guard let habit = habitToDelete else { return }

        // Manual cascade: delete all events for this habit first
        for event in habit.safeEvents {
            modelContext.delete(event)
        }
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
    /// The habit palette, in the same muted register as the accent swatches in
    /// `HabitsView`.
    ///
    /// This used to be the raw iOS system wheel (`#007AFF`, `#34C759`,
    /// `#FF9500`, …), which meant the app shipped two palettes: nine muted hues
    /// the user picked an accent from, and ten fully-saturated ones that then
    /// coloured every habit card, chart bar, history icon and widget — most of
    /// the app's colour. One picker looked designed and the other looked like a
    /// default, because it was one.
    ///
    /// Mid-tone on purpose: a habit colour has to work as chart ink and as a
    /// filled glyph on both a white card and a black one, so nothing here goes
    /// near the light or dark end.
    static let availableColors: [(name: String, hex: String)] = [
        ("Sand", "#E8A87C"),
        ("Clay", "#C97B63"),
        ("Rose", "#C77D8A"),
        ("Periwinkle", "#7D7AA8"),
        ("Slate Blue", "#6E7FA8"),
        ("Teal", "#5E9E9E"),
        ("Sage", "#7F9E76"),
        ("Moss", "#8A9B5F"),
        ("Ochre", "#C6A15B"),
        ("Storm", "#7A8290")
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
