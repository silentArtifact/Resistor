import Foundation
import SwiftData
import Observation

@Observable
final class LogViewModel {
    private var modelContext: ModelContext

    var habits: [Habit] = []
    var selectedHabitIndex: Int = 0
    var lastLoggedEvent: TemptationEvent?
    var showConfirmation: Bool = false
    private var confirmationWorkItem: DispatchWorkItem?

    var selectedHabit: Habit? {
        guard !habits.isEmpty, selectedHabitIndex >= 0, selectedHabitIndex < habits.count else {
            return nil
        }
        return habits[selectedHabitIndex]
    }

    var hasHabits: Bool {
        !habits.isEmpty
    }

    init(modelContext: ModelContext, defaultHabitId: UUID? = nil) {
        self.modelContext = modelContext
        fetchHabits()
        if let defaultId = defaultHabitId,
           let index = habits.firstIndex(where: { $0.id == defaultId }) {
            selectedHabitIndex = index
        }
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
        if !habits.isEmpty && selectedHabitIndex >= habits.count {
            selectedHabitIndex = habits.count - 1
        }
    }

    func logTemptation() {
        guard let habit = selectedHabit else { return }

        let event = TemptationEvent(habit: habit)
        modelContext.insert(event)

        do {
            try modelContext.save()
            lastLoggedEvent = event
        } catch {
            print("Failed to save temptation event: \(error)")
        }
    }

    func triggerConfirmation() {
        confirmationWorkItem?.cancel()
        showConfirmation = true
        let workItem = DispatchWorkItem { [weak self] in
            self?.showConfirmation = false
        }
        confirmationWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: workItem)
    }

    func updateEventContext(contextTags: [String], note: String?) {
        guard let event = lastLoggedEvent else { return }

        event.contextTags = contextTags
        event.note = note?.isEmpty == true ? nil : note

        do {
            try modelContext.save()
        } catch {
            print("Failed to update event context: \(error)")
        }
    }

    func updateEventIntensity(_ intensity: Int) {
        guard let event = lastLoggedEvent else { return }

        event.intensity = intensity

        do {
            try modelContext.save()
        } catch {
            print("Failed to update event intensity: \(error)")
        }
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
