## Problem, audience, and goals
Problem statement:
Most habit apps focus on daily success/failure and streaks. As soon as you “fail,” your streak resets and the app becomes demotivating. They also ignore the real work: repeatedly facing temptation. This app aims to track and support the actual moments of compulsion, not just whether a day was “perfect.”

Primary audience / user types:
- People trying to change compulsive or addictive behaviors such as impulsive spending, unhealthy eating, pornography use, smoking, etc.
- People who find themselves repeatedly in situations where an urge hits and want a fast, low-friction way to log “I’m in it right now” and see honest patterns over time.

Top 3 goals for v1.0:
1. Let a user register at least one compulsion / habit they are actively trying to change.
2. Allow the user to log an episode of temptation in under a few seconds from opening the app.
3. Show simple trends over time: whether temptation frequency is changing, and when it tends to spike (e.g., day of week, time of day).

Non-goals for v1.0:
- Streak-based scorekeeping or “perfect day” metrics.
- Social features, sharing, or comparison to other users.
- Clinical guidance, therapeutic content, or diagnoses.
- Cross-device sync and accounts (local-only in v1.0).


## Core user flows and stories
User stories:
- As a person trying to change a behavior, I want to log a temptation the moment it hits so I can track my real struggle instead of pretending it doesn’t happen.
- As a person trying to change a behavior, I want logging to be almost instant so I do not lose focus on resisting the urge.
- As a person trying to change a behavior, I want to see patterns in when I feel tempted so I can prepare for high-risk times and situations.
- As a person trying to change a behavior, I want to register multiple habits/compulsions so I can track more than one area if needed.

Flow 1: Quick log of a temptation (core loop)
Story:
As a user currently facing a temptation, I want to log it with as few steps as possible so I can get back to handling the urge.

Steps:
1. User opens the app and lands directly on the Log screen.
2. The currently selected habit/compulsion is visible as a card in the center of the screen.
3. If needed, the user swipes left/right to switch to a different habit.
4. The user taps a large “Log temptation” button.
5. The app creates a new TemptationEvent with timestamp and associated habit, then briefly confirms that it was recorded.
6. The user can immediately tap again if the urge is still ongoing, or close the app.

Edge cases:
- First-time user with no habits configured (redirect to Add Habit flow).
- Very rapid repeated taps (multiple events in a short time window; v1 treats each tap as a separate event).
- App opened from cold start vs from background (should always land on Log screen).

Flow 2: Add or edit a habit/compulsion
Story:
As a user, I want to add or edit a habit I am working on so I can track the right behavior in a clear way.

Steps:
1. From the Habits screen, user taps “Add habit.”
2. User enters a name (e.g., “Impulse spending”), optional description, and chooses an icon/color.
3. User saves; the new habit appears in the habit list and becomes available on the Log screen.
4. To edit, user taps an existing habit, updates name/description/icon, and saves.

Edge cases:
- User tries to create duplicate names (allow, but consider subtle UI hint).
- User deletes the only active habit (Log screen should handle “no habits” state and direct user back to add one).

Flow 3: Review trends and patterns
Story:
As a user, I want to see if my temptations are becoming more or less frequent and when they tend to happen so I can adjust my environment and expectations.

Steps:
1. From the bottom navigation, user taps the “Insights” tab.
2. App shows a summary for the currently selected habit:
   - Total temptations this week vs last week.
   - Simple chart of temptations over time (last 7/30 days).
   - Time-of-day distribution (morning/afternoon/evening) or hourly buckets.
   - Day-of-week distribution.
3. User can switch habits via a selector at the top.
4. User can tap through to a history list if needed (optional for v1).

Edge cases:
- No logged events yet (show an empty state that prompts user to log from the Log tab).
- Very high event counts (charts should stay legible and performant).

Flow 4: Optional context logging (manual, simple)
Story:
As a user, I want to optionally add simple context (like “At store” or “On phone”) to a temptation log so I can see which situations are riskiest.

Steps:
1. User taps “Log temptation” on the Log screen.
2. Immediately logged event is created so core flow is not blocked.
3. Optionally, a small sheet appears with quick context buttons (e.g., “At store”, “On phone”, “With friends”, “Alone”) plus an optional note field.
4. User taps a context or dismisses the sheet; app updates that event with context if provided.

Edge cases:
- User dismisses sheet without interaction (event remains with no context).
- User disables context prompts entirely in Settings (log becomes single-tap only).


## Screens and navigation
Navigation model:
- Bottom tab bar with three main tabs:
  - Log
  - Insights
  - Habits
- On first launch, user is guided through a minimal onboarding/setup flow, then dropped into the Log tab by default.
- On subsequent launches, app always opens directly to the Log tab.

Screens overview:
- S0: Onboarding / first habit setup (first-run only)
- S1: Log screen (default home)
- S2: Insights screen (trends and history)
- S3: Habits and Settings screen

Screen S0: Onboarding / first habit setup
Purpose:
Help a new user create their first habit/compulsion so the Log screen is immediately useful.

Layout description:
- Simple explanation of what the app does in one or two sentences.
- Text field to name the first habit (e.g., “Impulse spending”).
- Optional description field.
- Simple icon/color picker.
- Primary button: “Create habit and start logging.”

Main UI elements:
- Title/intro text.
- Name text field.
- Optional description text field.
- Icon/color selector.
- Primary action button.

Actions:
- Create first habit.
- Skip (optional; but skipping would require a fallback path on Log screen).

Entry points:
- Automatically shown on first app launch when no habits exist.

Exit points:
- After creating first habit, navigate to S1 Log screen.
- If skipped, navigate to S1 Log screen with an empty state.

Screen S1: Log screen (Log tab)
Purpose:
Be the fastest possible way to log “I am currently facing this temptation.”

Layout description:
- Top: horizontal swipeable carousel of habit cards, showing one habit prominently at a time.
- Center: large card showing current habit name, maybe short description.
- Bottom: big full-width button “Log temptation”.
- Optional: small button or icon to toggle context logging options.

Main UI elements:
- Habit card carousel.
- Large “Log temptation” button.
- Optional context button.
- Optional quick view of today’s count for the selected habit.

Actions:
- Swipe left/right to change selected habit.
- Tap big button to log a temptation event.
- Optionally tap to add context or note.

Entry points:
- Default entry after app launch (after onboarding).
- Tapping “Log” tab from anywhere.

Exit points:
- Navigation to Insights or Habits via tab bar (no deep navigation from here in v1).

Screen S2: Insights screen (Insights tab)
Purpose:
Show overall progress and patterns for temptations.

Layout description:
- Top: habit selector (segmented control, dropdown, or horizontal chips).
- Section: key stats (e.g., “Temptations this week”, “Change vs last week”).
- Section: small line or bar chart over time (last N days).
- Section: time-of-day distribution chart.
- Section: day-of-week distribution chart.
- Optional: link to open a simple chronological history list.

Main UI elements:
- Habit selector.
- Summary metrics.
- Charts or simple visualizations.
- Optional “View history” button.

Actions:
- Change selected habit.
- Switch between time ranges (7 days / 30 days) if implemented.
- Open history list.

Entry points:
- Tapping Insights tab.

Exit points:
- Tab bar to Log or Habits.
- Back from history list to Insights.

Screen S3: Habits and Settings screen (Habits tab)
Purpose:
Manage the list of habits and basic app settings.

Layout description:
- Section: list of existing habits with name, color/icon, and counts.
- Button: “Add habit.”
- For each habit: tap to view/edit details; swipe to archive/delete.
- Section: basic settings (toggle context prompts, notification reminder time if added later).

Main UI elements:
- Habits list.
- Add habit button.
- Habit detail/edit form.
- Settings toggles.

Actions:
- Add habit.
- Edit habit.
- Archive or delete habit.
- Configure settings (e.g., “Prompt for context after logging”, “Daily reminder time”).

Entry points:
- Tapping Habits tab.
- Optional deep links from other screens (e.g., “Manage habits”).

Exit points:
- Tab bar to Log or Insights.


## Data model
Entities overview:
- Habit
- TemptationEvent
- UserSettings

Entity: Habit
Fields:
- id: UUID
- name: String
- description: String? (optional)
- colorHex: String? (optional)
- iconName: String? (optional, maps to SF Symbol or custom asset)
- isArchived: Bool
- createdAt: Date

Notes:
- In v1, assume a small number of habits (for example, 1–5 active).
- Archived habits remain in storage so old events still reference them.

Entity: TemptationEvent
Fields:
- id: UUID
- habitId: UUID (foreign key reference to Habit.id)
- occurredAt: Date
- intensity: Int? (optional; e.g., 1–5 scale)
- outcome: String (e.g., "resisted", "gave_in", "unknown")
- contextTag: String? (e.g., "at_store", "on_phone", "with_friends", "alone")
- note: String? (optional, free-text note)

Notes:
- v1 focuses on logging events, not enforcing any specific outcome. The outcome field is available if you want to let the user mark “I gave in” vs “I resisted.”
- contextTag is kept simple as a string that can map to predefined context options.

Entity: UserSettings
Fields:
- id: UUID (could be a fixed single record)
- defaultHabitId: UUID? (habit to show first on Log screen)
- showContextPrompt: Bool
- dailyReminderEnabled: Bool
- dailyReminderHour: Int? (0–23)
- dailyReminderMinute: Int? (0–59)

Relationships:
- One Habit has many TemptationEvents.
- One TemptationEvent belongs to one Habit.
- UserSettings is a singleton record for the app instance.

Storage approach:
- v1.0: On-device database using SwiftData or Core Data.
- All data stored locally on device; no backend or sync.
- Future versions may add iCloud sync, but data model is already compatible with that (IDs and relationships are explicit).


## Technical architecture
Platforms:
- iOS version: target iOS 17+ (to allow use of SwiftData; adjust if you decide to support older OS versions).
- Device targets: iPhone only in v1.0.

UI:
- Framework: SwiftUI.
- Architectural pattern: MVVM.
- Each main screen (Log, Insights, Habits) has its own ViewModel.

State management:
- ObservableObject-based view models with @Published properties.
- @StateObject for root screen view models.
- @Environment access for shared data context (SwiftData/Core Data).

Persistence:
- Primary choice: SwiftData (if iOS 17+ is acceptable).
- Alternative: Core Data with NSPersistentContainer if you need older OS support.
- Data model mirrors Habit, TemptationEvent, and UserSettings entities.

Dependencies:
- System frameworks only for v1.0 (no third-party dependencies).
- Possible future additions:
  - Charts framework from Apple (if available and convenient) for Insights.
  - iOS UserNotifications for optional reminders.

App structure:
- Root view with TabView for three tabs (Log, Insights, Habits).
- App launches into Log tab after initial onboarding is completed.
- First-run logic checks if any Habit exists:
  - If no habits, present onboarding/setup flow (S0).
  - After first habit is created, navigate to Log tab.

Networking:
- None in v1.0.
- All data and logic are local to the device.

Testing considerations:
- ViewModels should be testable with in-memory data stores (mock repository implementing a simple protocol for fetching and saving Habit and TemptationEvent objects).
- Business logic for statistics (weekly counts, time-of-day distribution) lives in a separate service or in the Insights ViewModel, not inside the SwiftUI views.
