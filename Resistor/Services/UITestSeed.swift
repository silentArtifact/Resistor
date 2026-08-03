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

        // Two habits so the Log carousel shows "1 of 2". Sugar is inserted first
        // and so sorts first in `Habit.displayOrder` (equal sortOrder, earlier
        // createdAt) — which is what makes it the habit the Log screen opens on,
        // and therefore the one whose planted pattern is on screen for capture.
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

        // A spread of events across the last ~3 weeks so Insights charts and
        // History have real shape: varied outcomes, intensities, contexts, hours.
        let outcomes = ["resisted", "gave_in", "resisted", "resisted", "gave_in", "unknown"]
        let tagSets: [[String]] = [
            ["Stressed"], ["Bored", "On Phone"], ["Alone"], ["Stressed", "Bored"],
            ["With Friends"], ["Alone", "Bored"], []
        ]
        // Three spots for GPS-tagged events. The first two reverse-geocode to
        // the SAME coarse string — the case named places exist to separate — so
        // screenshots show "Home" and "Mission, San Francisco" side by side.
        let spots: [(lat: Double, lon: Double, name: String)] = [
            (37.7749, -122.4194, "Mission, San Francisco"),
            (37.7849, -122.4194, "Mission, San Francisco"),
            (37.7649, -122.4294, "Financial District, San Francisco")
        ]
        context.insert(Place(name: "Home", latitude: spots[0].lat, longitude: spots[0].lon))

        // The planted trigger below is anchored to the weekday and hour the
        // harness is *running in*, so both screens that consume patterns are
        // capturable: Insights always has a row to list, and the Log screen's
        // heads-up — which only appears while the clock sits inside a pattern —
        // is on screen during the run instead of on some Friday nobody captures.
        let plantedHour = calendar.component(.hour, from: now)
        let plantedPeriod = TemptationEvent.timeOfDayPeriod(for: now)

        // The base rotation deliberately skips the planted period, so the
        // cluster is the only thing feeding it. Uniform base data is uniform on
        // purpose — without a real cluster the card can only show its empty state.
        let baseHours = [2, 8, 13, 16, 19, 22].filter {
            guard let at = calendar.date(bySettingHour: $0, minute: 0, second: 0, of: now) else { return false }
            return TemptationEvent.timeOfDayPeriod(for: at) != plantedPeriod
        }

        var seedIndex = 0
        for habit in [sugar, phone] {
            // Deterministic-ish daily counts decreasing toward today (progress shape).
            for dayOffset in 0..<21 {
                let perDay = (dayOffset % 5 == 0) ? 2 : 1
                for n in 0..<perDay {
                    let hour = baseHours[(seedIndex + n) % baseHours.count]
                    guard let base = calendar.date(byAdding: .day, value: -dayOffset, to: now),
                          let when = calendar.date(bySettingHour: hour, minute: (seedIndex * 7) % 60, second: 0, of: base)
                    else { continue }
                    let spot = spots[seedIndex % spots.count]
                    let event = TemptationEvent(
                        habit: habit,
                        occurredAt: when,
                        intensity: (seedIndex % 5) + 1,
                        outcome: outcomes[seedIndex % outcomes.count],
                        contextTags: tagSets[seedIndex % tagSets.count],
                        note: seedIndex % 6 == 0 ? "Noticed the urge and waited it out." : nil,
                        latitude: spot.lat,
                        longitude: spot.lon,
                        locationName: spot.name
                    )
                    context.insert(event)
                    seedIndex += 1
                }
            }
        }

        // The planted trigger itself: Sugar, this weekday at this hour, at Home.
        //
        // Ten weeks, not four. `PatternFinder` counts *occasions* — the two logs
        // forty minutes apart below are deliberately one — so four weeks is four
        // data points against ~28 and does not clear the significance floor,
        // leaving the card empty. Ten clears it with margin, and is what a real
        // weekly trigger looks like anyway. Every occurrence is in a past week,
        // so nothing is dated in the future no matter when the harness runs.
        if let anchor = calendar.date(bySettingHour: plantedHour, minute: 0, second: 0, of: now) {
            for week in 1...10 {
                guard let slot = calendar.date(byAdding: .weekOfYear, value: -week, to: anchor) else { continue }
                for n in 0..<2 {
                    context.insert(TemptationEvent(
                        habit: sugar,
                        occurredAt: calendar.date(byAdding: .minute, value: n * 40, to: slot) ?? slot,
                        intensity: 4,
                        outcome: n == 0 ? "gave_in" : "resisted",
                        contextTags: ["Bored"],
                        latitude: spots[0].lat,
                        longitude: spots[0].lon,
                        locationName: spots[0].name
                    ))
                }
            }
        }

        try? context.save()
    }
}
#endif
