import Foundation
import SwiftData
import Observation
import CoreHaptics

@Observable
final class LogViewModel {
    private var modelContext: ModelContext

    var habits: [Habit] = []
    var selectedHabitIndex: Int = 0
    var lastLoggedEvent: TemptationEvent?
    var showConfirmation: Bool = false
    private var confirmationWorkItem: DispatchWorkItem?

    // MARK: - Core Haptics

    private var hapticEngine: CHHapticEngine?
    private var continuousPlayer: CHHapticAdvancedPatternPlayer?
    private(set) var supportsHaptics: Bool = false

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

    // MARK: - Haptic Engine

    func prepareHaptics() {
        supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
        guard supportsHaptics else { return }

        do {
            hapticEngine = try CHHapticEngine()
            hapticEngine?.resetHandler = { [weak self] in
                do {
                    try self?.hapticEngine?.start()
                } catch {
                    print("Failed to restart haptic engine: \(error)")
                }
            }
            hapticEngine?.stoppedHandler = { _ in }
            try hapticEngine?.start()
        } catch {
            print("Failed to create haptic engine: \(error)")
            supportsHaptics = false
        }
    }

    func startContinuousHaptic() {
        guard supportsHaptics, let engine = hapticEngine else { return }

        // Start at full intensity so dynamic parameter acts as a direct multiplier
        let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0)
        let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.0)
        let event = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [intensity, sharpness],
            relativeTime: 0,
            duration: 5
        )

        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            continuousPlayer = try engine.makeAdvancedPlayer(with: pattern)
            try continuousPlayer?.start(atTime: CHHapticTimeImmediate)
        } catch {
            print("Failed to start continuous haptic: \(error)")
        }
    }

    func updateHapticIntensity(_ progress: Float) {
        guard supportsHaptics, let player = continuousPlayer else { return }

        // Ramp intensity from 0.2 to 1.0 and sharpness from 0.1 to 0.5
        let intensityValue = 0.2 + (progress * 0.8)
        let sharpnessValue = 0.1 + (progress * 0.4)

        let intensityParam = CHHapticDynamicParameter(
            parameterID: .hapticIntensityControl,
            value: intensityValue,
            relativeTime: 0
        )
        let sharpnessParam = CHHapticDynamicParameter(
            parameterID: .hapticSharpnessControl,
            value: sharpnessValue,
            relativeTime: 0
        )

        do {
            try player.sendParameters([intensityParam, sharpnessParam], atTime: 0)
        } catch {
            print("Failed to update haptic parameters: \(error)")
        }
    }

    func stopHaptic() {
        guard supportsHaptics, let player = continuousPlayer else { return }

        do {
            try player.stop(atTime: CHHapticTimeImmediate)
        } catch {
            print("Failed to stop haptic: \(error)")
        }
        continuousPlayer = nil
    }
}
