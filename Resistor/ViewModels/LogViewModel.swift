import Foundation
import SwiftData
import Observation

@Observable
final class LogViewModel {
    private var modelContext: ModelContext

    var habits: [Habit] = []
    var selectedHabitIndex: Int = 0
    var showContextSheet: Bool = false
    var lastLoggedEvent: TemptationEvent?
    var showConfirmation: Bool = false

    var selectedHabit: Habit? {
        guard !habits.isEmpty, selectedHabitIndex >= 0, selectedHabitIndex < habits.count else {
            return nil
        }
        return habits[selectedHabitIndex]
    }

    var hasHabits: Bool {
        !habits.isEmpty
    }

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        fetchHabits()
    }

    func fetchHabits() {
        let descriptor = FetchDescriptor<Habit>(
            predicate: #Predicate { !$0.isArchived },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        do {
            habits = try modelContext.fetch(descriptor)
        } catch {
            print("Failed to fetch habits: \(error)")
            habits = []
        }
    }

    func logTemptation(showContext: Bool = false) {
        guard let habit = selectedHabit else { return }

        let event = TemptationEvent(habit: habit)
        modelContext.insert(event)

        do {
            try modelContext.save()
            lastLoggedEvent = event
            showConfirmation = true

            if showContext {
                showContextSheet = true
            }

            // Auto-hide confirmation after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.showConfirmation = false
            }
        } catch {
            print("Failed to save temptation event: \(error)")
        }
    }

    func updateEventContext(contextTag: TemptationEvent.ContextTag?, note: String?) {
        guard let event = lastLoggedEvent else { return }

        event.contextTag = contextTag?.rawValue
        event.note = note?.isEmpty == true ? nil : note

        do {
            try modelContext.save()
        } catch {
            print("Failed to update event context: \(error)")
        }

        showContextSheet = false
    }

    func updateEventOutcome(_ outcome: TemptationEvent.Outcome) {
        guard let event = lastLoggedEvent else { return }

        event.outcome = outcome.rawValue

        do {
            try modelContext.save()
        } catch {
            print("Failed to update event outcome: \(error)")
        }
    }

    func selectHabit(at index: Int) {
        guard index >= 0, index < habits.count else { return }
        selectedHabitIndex = index
    }

    func selectNextHabit() {
        guard habits.count > 1 else { return }
        selectedHabitIndex = (selectedHabitIndex + 1) % habits.count
    }

    func selectPreviousHabit() {
        guard habits.count > 1 else { return }
        selectedHabitIndex = (selectedHabitIndex - 1 + habits.count) % habits.count
    }
}
