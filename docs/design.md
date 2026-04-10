# Resistor — Design Specification

Comprehensive design document for Resistor, an iOS habit-tracking app that logs moments of temptation rather than streaks.

**Primary audience:** People trying to change compulsive or addictive behaviors (impulsive spending, unhealthy eating, smoking, etc.)

**Core premise:** Track the actual moments of compulsion, not whether a day was "perfect." No streaks, no gamification, no social features.

---

## Table of Contents

1. [Goals and Non-Goals](#goals-and-non-goals)
2. [User Flows](#user-flows)
3. [Screens and Navigation](#screens-and-navigation)
4. [Visual Design System](#visual-design-system)
5. [Interaction and Motion](#interaction-and-motion)
6. [Content and Voice](#content-and-voice)
7. [Privacy and Data Lifecycle](#privacy-and-data-lifecycle)
8. [Testing Strategy](#testing-strategy)
9. [Accessibility Requirements](#accessibility-requirements)
10. [Release and Distribution](#release-and-distribution)
11. [Success Metrics](#success-metrics)
12. [Post-v1 Roadmap](#post-v1-roadmap)
13. [Design Questions and Decisions](#design-questions-and-decisions)

---

## Goals and Non-Goals

### v1.0 Goals

1. Let a user register at least one compulsion/habit they are actively trying to change.
2. Allow the user to log an episode of temptation in under a few seconds from opening the app.
3. Show simple trends over time: frequency changes, time-of-day spikes, day-of-week patterns.

### Non-Goals for v1.0

- Streak-based scorekeeping or "perfect day" metrics
- Social features, sharing, or comparison
- Clinical guidance, therapeutic content, or diagnoses
- Cross-platform (iOS only)

---

## User Flows

### Flow 1: Quick Log (Core Loop)

1. User opens app, lands on Log screen.
2. Currently selected habit visible as a card.
3. Swipe left/right to switch habits if needed.
4. Tap "Log Temptation" button.
5. Event created with timestamp and habit reference.
6. Outcome sheet presents: intensity selector (1-5) + "I Resisted" / "I Gave In" / "Skip".
7. If context prompt enabled, context sheet presents: tag grid + note field.
8. Confirmation banner slides down, auto-hides after 1.5s.

Edge cases:
- No habits configured: redirect to Add Habit flow
- Rapid repeated taps: each tap creates a separate event
- App from cold start vs background: always lands on Log screen

### Flow 2: Add/Edit Habit

1. From Habits screen, tap "Add habit" (or tap existing habit to edit).
2. Enter name, optional description, choose icon/color.
3. Save. Habit appears in list and becomes available on Log screen.

Edge cases:
- Duplicate names allowed
- Deleting only active habit: Log screen shows empty state with "Add Habit" button

### Flow 3: Review Trends

1. Tap "Insights" tab.
2. Summary for selected habit: total this week vs last, charts, distributions.
3. Switch habits via selector pills.
4. Tap "View History" for chronological event list.

Edge cases:
- No events: empty state prompting to log from Log tab
- High event counts: charts stay legible

### Flow 4: Context Logging

1. After "Log Temptation" tap and outcome selection.
2. Context sheet presents with quick tags + optional note.
3. User selects tags (multi-select) and/or writes note, or dismisses.
4. Event updated with context. Dismissing leaves event with no context.

---

## Screens and Navigation

**Navigation:** Bottom tab bar with three tabs: Log, Insights, Habits.

- First launch: onboarding flow, then Log tab.
- Subsequent launches: directly to Log tab.

### S0: Onboarding (first-run only)

- App explanation (one or two sentences)
- Text field for first habit name
- Optional description
- Icon/color picker
- "Create habit and start logging" button
- "Skip for now" option

### S1: Log Screen (default tab)

- Habit card carousel (swipe or arrow buttons)
- Large "Log Temptation" button
- Today's count for selected habit
- Outcome sheet (half-sheet): intensity 1-5, "I Resisted" / "I Gave In" / "Skip"
- Context sheet (half-sheet): tag grid + note field, "Skip" / "Save"
- Confirmation banner overlay

### S2: Insights Screen

- Habit selector pills (horizontal scroll)
- Summary stats: this period vs previous, peak time, peak day
- Outcome breakdown (stacked bar + resisted %)
- Daily trend chart (bar chart)
- Time of day chart (bar chart)
- Day of week chart (bar chart)
- "View History" navigation link

### S3: Habits and Settings Screen

- Active habits list with swipe actions (archive, delete)
- Archived habits list with swipe actions (unarchive, delete)
- Add/edit habit form (name, description, color, icon, preview)
- Context menu: set/remove as default habit
- Settings: context prompt toggle, accent color picker
- Data: export, delete all data
- (Future: tip jar)

### History (pushed from Insights)

- Events grouped by date
- Swipe to delete
- Tap for detail sheet (read-only)

---

## Visual Design System

### Color Palette

**Accent Colors** (user-configurable in Settings):

| Name | Hex |
|------|-----|
| Slate Blue | `#6B7FA3` |
| Storm Gray | `#7A7F8A` |
| Sage | `#7A8F7A` |
| Dusty Rose | `#A37A7A` |
| Copper | `#A3897A` |
| Lavender | `#8A7FA3` |
| Teal | `#6B9E9E` |
| Charcoal | `#5A5A5F` |
| Dusk | `#8A7A99` |

Applied via `.tint()` at app root. Stored as `accentColorHex: String?` on UserSettings.

**Semantic Colors:**

| Role | Color | Usage |
|------|-------|-------|
| Background | `Color(.systemBackground)` | All screen backgrounds |
| Surface | `Color(.secondarySystemBackground)` | Cards, stat boxes, chart containers |
| Text primary | `Color.primary` | Body text |
| Text secondary | `Color(.secondaryLabel)` | Captions, subtitles |
| Resisted | System green | Outcome: resisted |
| Gave in | System orange | Outcome: gave in |
| Unknown | `Color(.tertiaryLabel)` | Outcome: skipped |
| Destructive | `Color.red` | Delete actions |

**Habit Colors** (10 presets):

Blue `#007AFF`, Green `#34C759`, Orange `#FF9500`, Red `#FF3B30`, Purple `#AF52DE`, Pink `#FF2D55`, Teal `#5AC8FA`, Indigo `#5856D6`, Yellow `#FFCC00`, Gray `#8E8E93`

Used at full saturation for icon tints, 15% opacity for card backgrounds.

### Typography

System fonts only. No custom typefaces. All text uses SwiftUI text styles (Dynamic Type compatible).

| Element | Style | Weight |
|---------|-------|--------|
| Screen title | `.title` / `.navigationTitle` | Bold |
| Habit name (card) | `.title` | `.bold` |
| Section headers | `.headline` | Default |
| Body text | `.body` | Default |
| Button labels | `.title2` (primary), `.title3` (outcome) | `.semibold` |
| Stat values | `.title` | `.bold` |
| Stat labels | `.caption` | Default |
| Context tags | `.subheadline` | Default |

### Spacing and Layout

| Token | Value | Usage |
|-------|-------|-------|
| Screen padding | 24pt | Content inset from edges |
| Card padding | 32pt | Habit card internal |
| Card corner radius | 20pt | Habit card |
| Button corner radius | 16pt (primary), 14pt (outcome), 8pt (tags) | Varies |
| Surface corner radius | 12pt | Stat cards, chart containers |
| Section spacing | 24pt | Between sections |
| Element spacing | 16pt | Within sections |

All interactive elements meet 44x44pt minimum tap target.

### Component Catalog

**Habit Card:** Icon (48pt, habit color) + name + optional description. Background: habit color @ 15% opacity. Corner radius 20pt.

**Primary Button (Log Temptation):** White text on accent color. Full width, 16pt corner radius, 20pt vertical padding.

**Outcome Buttons:** "I Resisted" (white on green), "I Gave In" (white on orange). Full width, 14pt corner radius.

**Stat Card:** Caption + large value + subtitle. Surface background, 12pt corner radius.

**Confirmation Banner:** Green checkmark + "Logged!". System background, 12pt corner radius, subtle shadow. Slides from top, auto-hides 1.5s.

### App Icon

Minimalist shield. Single-color white glyph on slate blue (`#6B7FA3`) background. No text, no gradients. 1024x1024 master, scaled per Apple HIG.

### Dark Mode

Dark mode is the default. Light mode must also work.
- Card backgrounds: `Color(.secondarySystemBackground)`, not hardcoded hex
- Habit color tints at 15% opacity work on both
- Avoid pure white/black — use semantic colors

---

## Interaction and Motion

### Gesture Map

| Gesture | Location | Action | Threshold |
|---------|----------|--------|-----------|
| Tap | Log button | Create event, open outcome sheet | — |
| Tap | Intensity circle | Select intensity | — |
| Tap | Outcome button | Set outcome, dismiss sheet | — |
| Tap | Context tag | Toggle tag selection | — |
| Horizontal drag | Habit card | Swipe between habits | 50pt commit, 30pt min start |
| Swipe trailing | Habit row | Archive/Delete | System default |
| Swipe trailing | Event row | Delete | System default |

### Drag Gesture (Habit Card)

- Resistance: `translation.width * 0.4` (40% of finger travel)
- Commit: 50pt raw translation
- Below threshold: spring back
- Spring: `response: 0.3, dampingFraction: 0.7`
- During drag: `.interactiveSpring`

### Haptic Feedback

Single haptic: log temptation only. `UIImpactFeedbackGenerator`, `.medium` style, on button tap before sheet.

No haptics on navigation, sheets, or secondary actions.

### Sheet Presentation

| Sheet | Detent | Purpose |
|-------|--------|---------|
| Outcome | `.medium` | Intensity + resisted/gave in |
| Context | `.medium` | Tags + note |
| Add/Edit Habit | Full | Form with color/icon picker |
| Event Detail | `.medium` | Read-only event info |

### Sheet Sequencing (Outcome -> Context)

```
Tap "Log Temptation"
  -> Reset all sheet state
  -> Event created immediately (timestamp accuracy)
  -> Outcome sheet (.medium)
    -> User picks intensity + outcome, OR "Skip"
    -> onDismiss:
      -> If context prompt enabled -> context sheet (.medium)
        -> User selects tags/note, OR "Skip"
        -> onDismiss -> confirmation banner
      -> If context prompt disabled -> confirmation banner
```

Rules:
- Use `onDismiss` callbacks. Never `DispatchQueue.main.asyncAfter`.
- Event exists immediately regardless of sheet interactions.
- Confirmation banner fires only after ALL sheets dismiss.

### Animations

| Element | Animation | Duration |
|---------|-----------|----------|
| Banner appear/dismiss | Slide from top + fade | 0.3s easeInOut |
| Habit card drag | Interactive spring | — |
| Card snap-back | Spring | 0.3s |
| Sheets, tabs, navigation | System default | System |

### Confirmation Banner

- Triggers after all sheets dismiss
- Green checkmark + "Logged!"
- `.overlay(alignment: .top)` with `.transition(.move(edge: .top).combined(with: .opacity))`
- Auto-hides after 1.5s via cancellable `DispatchWorkItem`
- Does not block interaction or push content

---

## Content and Voice

### Voice Rules

1. State facts, not feelings. "Logged." not "Great job!"
2. Neutral, mechanical terms. "Event", "logged", "resisted", "gave in".
3. No motivational copy. No "You've got this", "Keep going".
4. No personification.
5. Brevity over warmth.
6. No emoji in UI text.

### Forbidden Language

| Don't Use | Use Instead |
|-----------|-------------|
| Failure/failed | Gave in |
| Relapse | Gave in |
| Addiction/addict | Don't label user |
| Compulsion | Habit or temptation |
| Weakness, Strength | Omit |
| Proud/pride, Shame/ashamed | Omit |
| Streak | Omit (counter to concept) |
| Slip/slip-up | Gave in |
| Clean/sober | Omit |

### All User-Facing Strings

**Navigation:** Log, Insights, Habits

**Log Screen:**
- "Log Temptation" button
- "Today: {n} logged"
- "{n} of {total}" carousel counter
- "Logged!" confirmation
- Empty: "No habits to track" / "Create a habit to start logging temptations." / "Add Habit"

**Outcome Sheet:**
- "How did it go?"
- "Did you resist or give in to the temptation?"
- "How strong was the urge?" / "Mild" / "Overwhelming"
- "I Resisted" / "I Gave In" / "Skip"

**Context Sheet:**
- "Add context (optional)"
- "Note (optional)" / "Add a note..."
- "Skip" / "Save"

**Context Tags:**
At Store, On Phone, With Friends, Alone, At Work, At Home, Stressed, Bored

**Insights:**
- "No habits to analyze" / "No data yet"
- "Outcomes", "Daily Trend", "Time of Day", "Day of Week"
- "This Week", "This Month", "vs Previous", "temptations"
- "Peak Time", "Peak Day", "of day", "of week"
- "View History"

**Habits:**
- "Active Habits", "Archived"
- "Habit name", "Description (optional)", "Color", "Icon", "Preview"
- "New Habit", "Edit Habit", "Cancel", "Save"
- "Show context prompt after logging", "Accent Color"
- "Set as Default" / "Remove as Default"
- "Export Data", "Delete All Data"
- Delete alert: "Delete all data?" / "This removes all habits, events, and settings. This cannot be undone." / "Delete Everything"

**Onboarding:**
- "Resistor"
- "Track your temptations, understand your patterns."
- "What habit are you working on?"
- "e.g., Sugar, Smoking, Social Media"
- "Create habit and start logging" / "Skip for now"

**Outcome Display Names:**
- resisted -> "Resisted"
- gave_in -> "Gave In"
- unknown -> "Not recorded"

### Error Messages (future)

v1 does not surface errors to users. Future: non-blocking banner.
- "Save failed. Try again."
- "Could not load data."
- "Export failed."

---

## Privacy and Data Lifecycle

### Storage

- SwiftData with CloudKit-backed container
- iCloud sync enabled at launch
- Fully functional offline, syncs when connectivity returns
- No custom backend, only Apple infrastructure

### What Gets Synced

- Habit (low sensitivity — names could be sensitive)
- TemptationEvent (high sensitivity — timestamps, outcomes, notes)
- UserSettings (low sensitivity — preferences)

### What Does NOT Leave Device

- No third-party servers, analytics, crash reporting, telemetry, or SDKs

### Data Export

JSON only (no CSV). Triggered from Settings.

```json
{
  "exported_at": "ISO8601",
  "habits": [
    {
      "id": "UUID",
      "name": "string",
      "description": "string|null",
      "color_hex": "string|null",
      "icon_name": "string|null",
      "is_archived": "bool",
      "created_at": "ISO8601"
    }
  ],
  "events": [
    {
      "id": "UUID",
      "habit_id": "UUID|null",
      "occurred_at": "ISO8601",
      "outcome": "string",
      "intensity": "int|null",
      "context_tags": ["string"],
      "note": "string|null"
    }
  ]
}
```

### Data Deletion

- **Single event:** Swipe-to-delete in History. Immediate, no confirmation.
- **Single habit:** Swipe-to-delete in Habits. Confirmation required. Deletes all child events.
- **All data:** "Delete All Data" in Settings. Confirmation required. Resets to onboarding state.
- **Archive vs Delete:** Archive hides habit, preserves events, reversible. Delete is permanent.

### iCloud Sync Details

- Default CloudKit container (bundle ID)
- SwiftData handles CloudKit schema automatically
- Conflict resolution: last-writer-wins (acceptable — events rarely edited)
- No iCloud signed in: data is local-only, no error
- Sign in later: local data merges automatically

### App Store Privacy Labels

- **Data Used to Track You:** None
- **Data Linked to You:** Health & Fitness (behavioral data)
- **Data Not Collected:** Everything else

---

## Testing Strategy

### Test Targets

- `ResistorTests` — Unit tests (XCTest)
- `ResistorUITests` — UI tests (XCUITest)

Neither target exists yet.

### Unit Tests (Priority Order)

**P1: Core Logging (LogViewModel)**
- Event creation with correct habit reference and timestamp
- Outcome updates (resisted, gave in)
- Intensity saving (1-5) and nil handling
- Context tag and note updates
- No crash when no habits exist
- Confirmation auto-hide

**P2: Habit Navigation**
- Next/previous wrapping
- Out-of-bounds index handling
- Fetching excludes archived habits
- Default habit ID

**P3: Insights Calculations**
- Total events in range (week, month)
- Change from previous period
- Resisted percentage, outcome breakdown
- Daily, time-of-day, day-of-week distributions

**P4: Habit CRUD**
- Add, edit, archive, unarchive, delete
- Sort active before archived

**P5: Model Properties**
- Today events count
- Outcome enum mapping
- Time of day period
- Color hex parsing

**P6: Data Export**
- JSON schema correctness
- Null field serialization
- Empty data handling

### UI Tests

1. Log a temptation (full flow through outcome + context)
2. Onboarding (create first habit)
3. Tab navigation
4. Habit management (add, edit)
5. Accessibility (VoiceOver navigation)

### Test Data

In-memory ModelContainer for all tests. Seed factories:
- `makeHabit(name:)` — single habit
- `makeEvent(habit:outcome:intensity:hoursAgo:)` — single event
- `makeSeedData(habits:eventsPerHabit:)` — bulk

### Coverage Targets

- ViewModels: 80%+
- Model computed properties: 100%
- Data export: 100%
- Overall: 60%+

Guidelines, not gates. No CI to enforce.

---

## Accessibility Requirements

### VoiceOver

- Every interactive element has a label
- VoiceOver must complete every flow
- Habit cards, stat cards, chart containers grouped as single accessible elements
- Custom labels for: log button ("Log temptation for [habit name]"), carousel arrows, intensity circles, outcome buttons

### Dynamic Type

- All text uses SwiftUI text styles (no hardcoded sizes)
- Long habit names wrap, never truncate
- Stat cards stack vertically at accessibility sizes
- Context tag grid reflows
- Intensity circles remain 44pt minimum
- Test at: Default, Large, AX3, AX5

### Reduce Motion

When enabled:
- Confirmation banner: crossfade instead of slide
- Habit card drag: snap immediately instead of spring
- Sheet presentation: system automatic

### Color and Contrast

- All text meets WCAG AA (4.5:1 body, 3:1 large)
- Outcome colors paired with icons, never color alone
- Audit: habit color tint on dark background, secondary text on secondary background

### Keyboard Navigation (iPad)

- All elements reachable via Tab
- Enter/Space activates
- Escape dismisses sheets

---

## Release and Distribution

### Distribution Path

Development (local builds) -> TestFlight (Matt + friends) -> App Store (public, free)

### Versioning

- 0.1.0 — First TestFlight build
- 0.2.0 — Insights, history, export
- 0.3.0 — iCloud sync, dark mode polish, accessibility
- 1.0.0 — App Store submission
- 1.1.0 — Location clustering
- 1.2.0 — Widget + Watch

### TestFlight Plan

First build (0.1.0) must have:
- Create habit, log temptation with outcome/intensity
- View insights, charts
- Manage habits
- iCloud sync

Testers: Matt (Sugar, iPhone 16 Pro) + 3-4 friends.

### App Store Metadata

- **Name:** Resistor
- **Subtitle:** Track temptations, see patterns.
- **Category:** Health & Fitness
- **Price:** Free
- **In-App Purchases:** Tip Jar (optional)
- **Keywords:** temptation, habit, tracker, urge, resist, impulse, pattern, behavior, self-control, log

### Tip Jar (StoreKit 2)

Located at bottom of Settings section. Single consumable IAP:
- Tip: $1.99 (`com.resistor.tip`)

On success: "Thank you." text. On failure/cancel: no message. No nag screens.

### Launch Checklists

**Pre-TestFlight:**
- App builds clean
- iCloud sync tested between devices
- Unit and UI tests pass
- App icon present
- Dark and light modes correct
- Export and delete-all work
- Onboarding works
- Bundle ID, signing, iCloud entitlement configured

**Pre-App Store:**
- TestFlight feedback addressed
- Privacy policy published
- Screenshots captured
- Metadata written
- Tip jar configured and tested
- Accessibility audit complete
- Tested on iPhone 16 Pro

---

## Success Metrics

### Primary Criteria

1. Matt uses it daily for 2+ weeks
2. Logging takes under 3 seconds
3. Insights reveal a pattern the user didn't consciously know

### Positive Signals

- Consistent daily logging over 2+ weeks
- Outcome data populated (not all "unknown")
- Context tags used on >30% of events
- User checks Insights unprompted

### Warning Signals

- Logging stops after a few days (too much friction)
- All outcomes "unknown" (outcome sheet perceived as mandatory)
- Insights never opened
- App deleted within a week

### Quality Gates

**Pre-TestFlight:**
- Log action <100ms
- No crashes in 50 consecutive logs
- Events never lost or duplicated
- iCloud sync within 30s on Wi-Fi

**Pre-App Store:**
- All tests pass
- Accessibility audit clean
- Dark/light mode audits clean
- Export works
- 2 weeks personal daily use

### What This App Is NOT

- Replace therapy
- Build a user base
- Generate revenue (tips are bonus)
- Compete with habit trackers

---

## Post-v1 Roadmap

### Tier 1: Fast-Follow (v1.1)

**Location Clustering** — Geographic breakdown of where temptations happen. CoreLocation + MapKit. Opt-in, "When In Use" permission. Sensitive data considerations.

**iPad Support** — Layout should adapt. Wider cards, multi-column Insights.

### Tier 2: Enhancement (v1.2)

**Home Screen Widget (WidgetKit)** — Today's count for default habit. Small/medium/large sizes. No logging from widget.

**Apple Watch App (WatchKit)** — Logging only. Complication shows today's count. Outcome selection. Syncs via iCloud.

### Tier 3: Future Consideration

- Custom context tags (user-defined beyond preset 8)
- Intensity trends (average intensity over time chart)
- Weekly/monthly summary view
- Import data (complement to export)
- Siri Shortcut ("Hey Siri, log a temptation")

### Not Planned (Permanently Out of Scope)

- Social features (private, sensitive data)
- Streaks (counter to philosophy)
- Gamification (badges, points, levels)
- AI insights
- Accounts/login (iCloud handles identity)
- Android, web dashboard
- Therapist/coach sharing

---

## Design Questions and Decisions

Summary of all design decisions made during the design phase.

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Tone | Clinical, minimal, no persona | Tool, not a coach |
| Dark mode | Default | Calm, minimal aesthetic |
| Accent color | Slate blue default, user-configurable (9 options) | Personal preference |
| Notifications | None, permanently | Temptation isn't scheduled |
| iCloud sync | Required for v1 | Multi-device use expected |
| Distribution | TestFlight -> App Store | Prove concept first |
| Business model | Free + optional tip jar | No paywall |
| Location tracking | Post-v1 fast-follow | Most-wanted but acceptable to defer |
| Watch + Widget | Post-v1 | Enhancement, not core |
| Testing | Unit + UI tests | Not manual QA only |
| Export format | JSON only | Simpler than CSV + JSON |
| Context tags | Multiple allowed | Single tag too limiting |
| Intensity default | Nil (not 3) | Nil = didn't engage, preserves data integrity |
| Banner timing | After all sheets dismiss | Was hidden behind sheets |
| Default habit | User-settable via context menu | Core for fast logging |
| Time zones | Store UTC, display local | Standard practice |
