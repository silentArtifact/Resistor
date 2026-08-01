import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var habits: [Habit]
    @Query private var userSettings: [UserSettings]
    @Query private var contextTags: [ContextTag]

    @State private var showOnboarding = false
    @State private var selectedTab: Tab = .log

    enum Tab {
        case log
        case insights
        case habits
    }

    private var needsOnboarding: Bool {
        // Show onboarding if no settings exist or onboarding not completed
        guard let settings = userSettings.first else {
            return true
        }
        return !settings.hasCompletedOnboarding
    }

    private var accentColor: Color {
        if let hex = userSettings.first?.accentColorHex,
           let color = Color(hex: hex) {
            return color
        }
        return UserSettings.defaultAccentColor
    }

    var body: some View {
        Group {
            if needsOnboarding {
                OnboardingView(onComplete: {
                    showOnboarding = false
                })
            } else {
                mainTabView
            }
        }
        .tint(accentColor)
        .onAppear {
            initializeSettingsIfNeeded()
        }
    }

    private var mainTabView: some View {
        TabView(selection: $selectedTab) {
            LogView()
                .tabItem {
                    Label("Log", systemImage: "plus.circle.fill")
                }
                .tag(Tab.log)

            InsightsView()
                .tabItem {
                    Label("Insights", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tag(Tab.insights)

            HabitsView()
                .tabItem {
                    Label("Habits", systemImage: "list.bullet")
                }
                .tag(Tab.habits)
        }
    }

    private func initializeSettingsIfNeeded() {
        if userSettings.isEmpty {
            let settings = UserSettings()
            modelContext.insert(settings)
        } else {
            // Runs every launch, not just once: CloudKit can import another
            // device's copy at any point, and until there is exactly one row
            // `userSettings.first` — which all 13 read sites use — is a coin
            // toss. A duplicate that lands mid-session is repaired next launch.
            UserSettings.mergeDuplicates(userSettings, habits: habits, in: modelContext)
        }

        // Seed default context tags if none exist (covers both fresh installs
        // and upgrades from before tag seeding was added). The emptiness check
        // is per-device and races the CloudKit import, so a second device seeds
        // its own five and then receives five more — every default chip twice.
        // Same repair as the settings singleton above, for the same reason.
        if contextTags.isEmpty {
            let defaults = ["Stressed", "Bored", "Alone", "On Phone", "With Friends"]
            for name in defaults {
                modelContext.insert(ContextTag(name: name))
            }
        } else {
            ContextTag.mergeDuplicates(contextTags, in: modelContext)
        }

        try? modelContext.save()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Habit.self, TemptationEvent.self, UserSettings.self, ContextTag.self], inMemory: true)
}
