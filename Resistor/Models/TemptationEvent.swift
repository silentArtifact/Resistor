import Foundation
import SwiftUI
import SwiftData

@Model
final class TemptationEvent {
    var id: UUID = UUID()
    var occurredAt: Date = Date()
    var intensity: Int?
    var outcome: String = "unknown"
    var contextTags: [String] = []
    var note: String?

    var habit: Habit?

    init(
        id: UUID = UUID(),
        habit: Habit,
        occurredAt: Date = Date(),
        intensity: Int? = nil,
        outcome: String = "unknown",
        contextTags: [String] = [],
        note: String? = nil
    ) {
        self.id = id
        self.habit = habit
        self.occurredAt = occurredAt
        self.intensity = intensity
        self.outcome = outcome
        self.contextTags = contextTags
        self.note = note
    }
}

extension TemptationEvent {
    enum Outcome: String, CaseIterable {
        case resisted = "resisted"
        case gaveIn = "gave_in"
        case unknown = "unknown"

        var displayName: String {
            switch self {
            case .resisted: return "Resisted"
            case .gaveIn: return "Gave In"
            case .unknown: return "Not recorded"
            }
        }

        var iconName: String {
            switch self {
            case .resisted: return "checkmark.circle.fill"
            case .gaveIn: return "xmark.circle.fill"
            case .unknown: return "questionmark.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .resisted: return .green
            case .gaveIn: return .red
            case .unknown: return .gray
            }
        }
    }

    enum ContextTag: String, CaseIterable {
        case atStore = "at_store"
        case onPhone = "on_phone"
        case withFriends = "with_friends"
        case alone = "alone"
        case atWork = "at_work"
        case atHome = "at_home"
        case stressed = "stressed"
        case bored = "bored"

        var displayName: String {
            switch self {
            case .atStore: return "At Store"
            case .onPhone: return "On Phone"
            case .withFriends: return "With Friends"
            case .alone: return "Alone"
            case .atWork: return "At Work"
            case .atHome: return "At Home"
            case .stressed: return "Stressed"
            case .bored: return "Bored"
            }
        }
    }

    var outcomeEnum: Outcome {
        Outcome(rawValue: outcome) ?? .unknown
    }

    var hourOfDay: Int {
        Calendar.current.component(.hour, from: occurredAt)
    }

    var dayOfWeek: Int {
        Calendar.current.component(.weekday, from: occurredAt)
    }

    var timeOfDayPeriod: String {
        let hour = hourOfDay
        switch hour {
        case 5..<12: return "Morning"
        case 12..<17: return "Afternoon"
        case 17..<21: return "Evening"
        default: return "Night"
        }
    }
}
