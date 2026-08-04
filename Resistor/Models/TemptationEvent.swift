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
    var latitude: Double?
    var longitude: Double?
    var locationName: String?

    var habit: Habit?

    init(
        id: UUID = UUID(),
        habit: Habit,
        occurredAt: Date = Date(),
        intensity: Int? = nil,
        outcome: String = "unknown",
        contextTags: [String] = [],
        note: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        locationName: String? = nil
    ) {
        self.id = id
        self.habit = habit
        self.occurredAt = occurredAt
        self.intensity = intensity
        self.outcome = outcome
        self.contextTags = contextTags
        self.note = note
        self.latitude = latitude
        self.longitude = longitude
        self.locationName = locationName
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

        /// Muted, not `.green` / `.orange`.
        ///
        /// These three colours are the most-repeated ink in the app — the
        /// History badges, the Outcomes bar, the Log confirmation banner, the
        /// map pins — and at full system saturation they were the loudest thing
        /// on every screen, in an app whose whole palette is deliberately
        /// desaturated and whose tone is deliberately clinical. A saturated
        /// green also grades the user: it is the colour of a pass mark. Muted
        /// sage and sienna still separate the two outcomes at a glance without
        /// scoring them.
        ///
        /// Values are picked to clear 4.5:1 as text on a 20%-opacity wash of
        /// themselves — how `HistoryView` actually draws them — in both modes.
        var color: Color {
            switch self {
            case .resisted: return Color(light: "#3F6B4A", dark: "#8FBF9B")
            case .gaveIn: return Color(light: "#8C4F32", dark: "#D89A78")
            case .unknown: return Color(light: "#5F646B", dark: "#A0A6AE")
            }
        }
    }

    enum ContextTag: String, CaseIterable {
        case onPhone = "on_phone"
        case withFriends = "with_friends"
        case alone = "alone"
        case stressed = "stressed"
        case bored = "bored"

        var displayName: String {
            switch self {
            case .onPhone: return "On Phone"
            case .withFriends: return "With Friends"
            case .alone: return "Alone"
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
        Self.timeOfDayPeriod(for: occurredAt)
    }

    /// The period any date falls in. Static so the Log screen can ask which
    /// period *now* is without inventing an event to ask on behalf of.
    static func timeOfDayPeriod(for date: Date) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<12: return "Morning"
        case 12..<17: return "Afternoon"
        case 17..<21: return "Evening"
        default: return "Night"
        }
    }

    /// Returns a display-friendly name for a context tag string.
    /// Handles both old enum-style raw values (e.g. "at_store") and new custom tag names.
    static func displayName(for tagRaw: String) -> String {
        if let legacy = ContextTag(rawValue: tagRaw) {
            return legacy.displayName
        }
        return tagRaw
    }

    /// Adds the tag if absent, removes it if present. Removes only the first
    /// match: a duplicate is a bug from elsewhere, and silently collapsing it
    /// here would hide it while making one tap take two.
    func toggleContextTag(_ tagRaw: String) {
        if let index = contextTags.firstIndex(of: tagRaw) {
            contextTags.remove(at: index)
        } else {
            contextTags.append(tagRaw)
        }
    }

    var hasLocation: Bool {
        latitude != nil && longitude != nil
    }

    var locationDisplayName: String? {
        if let name = locationName, !name.isEmpty { return name }
        guard let lat = latitude, let lon = longitude else { return nil }
        return String(format: "%.4f, %.4f", lat, lon)
    }
}
