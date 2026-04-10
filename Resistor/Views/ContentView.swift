import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var habits: [Habit]
    @Query private var userSettings: [UserSettings]

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
        return .blue
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

            // Seed default context tags on first launch only
            let defaults = ["Stressed", "Bored", "Alone", "At Home", "At Work", "On Phone", "With Friends", "At Store"]
            for name in defaults {
                modelContext.insert(ContextTag(name: name))
            }

            try? modelContext.save()
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Habit.self, TemptationEvent.self, UserSettings.self, ContextTag.self], inMemory: true)
}
