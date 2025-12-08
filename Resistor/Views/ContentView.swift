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

    private var hasNoHabits: Bool {
        habits.filter { !$0.isArchived }.isEmpty
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
            try? modelContext.save()
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Habit.self, TemptationEvent.self, UserSettings.self], inMemory: true)
}
