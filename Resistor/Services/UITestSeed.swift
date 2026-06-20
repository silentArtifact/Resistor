#if DEBUG
import Foundation
import SwiftData
import SwiftUI

/// Seeds a deterministic, in-memory data set for UI-test screenshot runs.
///
/// Activated only when the app is launched with the `-uiTestMode` argument
/// (see `ResistorApp`). It populates a fixed set of habits, context tags, and
/// temptation events so every screenshot run renders identical content,
/// without onboarding and without ever touching the real CloudKit store.
///
/// This file is compiled into DEBUG builds only and is never shipped.
enum UITestSeed {
    /// True when the process was launched for UI-test screenshotting.
    static var isActive: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiTestMode")
    }

    /// True when the run should render the first-run onboarding flow instead of
    /// the seeded main app. Boots an empty in-memory store with onboarding
    /// incomplete (and a nil accent color, matching a genuine first run).
    static var isOnboarding: Bool {
        isActive && ProcessInfo.processInfo.arguments.contains("-uiTestOnboarding")
    }

    /// Color scheme to force during a screenshot run. `.dark` when launched with
    /// `-uiTestDarkMode` (so dark-mode captures are deterministic), otherwise
    /// `nil` — which means "follow the system" and leaves normal runs untouched.
    static var forcedColorScheme: ColorScheme? {
        guard isActive else { return nil }
        return ProcessInfo.processInfo.arguments.contains("-uiTestDarkMode") ? .dark : nil
    }

    /// Reference "now" for seeding. Fixed offsets from launch time keep the
    /// relative shape of the data (today / this week / earlier) stable while
    /// still landing in the current calendar period.
    static func populate(_ context: ModelContext) {
        // First-run onboarding capture: leave the store empty and onboarding
        // incomplete so ContentView routes to OnboardingView with a nil accent
        // (system blue tint), exactly as a genuine first launch.
        if isOnboarding { return }

        let calendar = Calendar.current
        let now = Date()

        // Settings: onboarding complete, a chosen accent color.
        let settings = UserSettings(
            showContextPrompt: true,
            accentColorHex: "#8A7FA3",
            hasCompletedOnboarding: true
        )
        context.insert(settings)

        // Context tags shown as chips on the Log screen. Matches the app's
        // default seed set (location-based tags were dropped — GPS covers them).
        for name in ["Stressed", "Bored", "Alone", "On Phone", "With Friends"] {
            context.insert(ContextTag(name: name))
        }

        // Two habits so the Log carousel shows "1 of 2".
        let sugar = Habit(
            name: "Sugar",
            habitDescription: "Reaching for sweets when stressed or bored.",
            colorHex: "#E8A87C",
            iconName: "sun.max.fill"
        )
        let phone = Habit(
            name: "Doomscrolling",
            habitDescription: "Opening social apps on autopilot.",
            colorHex: "#7D7AA8",
            iconName: "iphone"
        )
        context.insert(sugar)
        context.insert(phone)
        settings.defaultHabitId = sugar.id

        // A spread of events across the last ~3 weeks so Insights charts and
        // History have real shape: varied outcomes, intensities, contexts, hours.
        let outcomes = ["resisted", "gave_in", "resisted", "resisted", "gave_in", "unknown"]
        let tagSets: [[String]] = [
            ["Stressed"], ["Bored", "On Phone"], ["Alone"], ["Stressed", "Bored"],
            ["With Friends"], ["Alone", "Bored"], []
        ]
        var seedIndex = 0
        for habit in [sugar, phone] {
            // Deterministic-ish daily counts decreasing toward today (progress shape).
            for dayOffset in 0..<21 {
                let perDay = (dayOffset % 5 == 0) ? 2 : (dayOffset % 3 == 0 ? 1 : 0)
                for n in 0..<perDay {
                    let hour = [8, 13, 16, 19, 22][(seedIndex + n) % 5]
                    guard let base = calendar.date(byAdding: .day, value: -dayOffset, to: now),
                          let when = calendar.date(bySettingHour: hour, minute: (seedIndex * 7) % 60, second: 0, of: base)
                    else { continue }
                    let event = TemptationEvent(
                        habit: habit,
                        occurredAt: when,
                        intensity: (seedIndex % 5) + 1,
                        outcome: outcomes[seedIndex % outcomes.count],
                        contextTags: tagSets[seedIndex % tagSets.count],
                        note: seedIndex % 6 == 0 ? "Noticed the urge and waited it out." : nil
                    )
                    context.insert(event)
                    seedIndex += 1
                }
            }
        }

        try? context.save()
    }
}
#endif
