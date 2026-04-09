# Resistor — Project Guide

Resistor is a habit-tracking iOS app that logs moments of temptation rather than streaks. It targets people changing compulsive or addictive behaviors by providing fast logging, honest pattern visibility, and positive reinforcement.

**Platform:** iOS 17+ (iPhone only)
**Language:** Swift, SwiftUI, SwiftData
**Architecture:** MVVM with `@Observable` ViewModels
**Dependencies:** System frameworks only (no SPM, no CocoaPods, no third-party)

## File Structure

```
Resistor/
├── ResistorApp.swift                 # App entry, ModelContainer + CloudKit setup
├── Resistor.entitlements             # iCloud/CloudKit entitlements
├── TipJar.storekit                   # StoreKit configuration for testing
├── Assets.xcassets/                  # App icon, accent color
├── Extensions/
│   └── Color+Hex.swift              # Color(hex:) initializer
├── Models/
│   ├── Habit.swift                   # @Model — habit entity
│   ├── TemptationEvent.swift         # @Model — logged event entity
│   └── UserSettings.swift            # @Model — singleton settings
├── Services/                         # (empty — NotificationManager deleted)
├── ViewModels/
│   ├── LogViewModel.swift            # Log screen logic
│   ├── InsightsViewModel.swift       # Stats, charts, distributions
│   ├── HabitsViewModel.swift         # Habit CRUD, color/icon lists
│   ├── OnboardingViewModel.swift     # First-run habit creation
│   └── TipJarViewModel.swift         # StoreKit 2 tip jar purchases
└── Views/
    ├── ContentView.swift             # TabView + onboarding gate + accent color
    ├── LogView.swift                 # Core logging flow (S1)
    ├── InsightsView.swift            # Charts and trends (S2)
    ├── HabitsView.swift              # Habit management + settings (S3)
    ├── HistoryView.swift             # Past events list + detail sheet
    └── OnboardingView.swift          # First-run flow (S0)
```

## Data Model (SwiftData)

All three entities use the `@Model` macro. CloudKit compatibility constraints apply (see below).

### Habit

| Field | Type | Notes |
|-------|------|-------|
| `id` | `UUID` | No `@Attribute(.unique)` (CloudKit) |
| `name` | `String` | Required, default `""` |
| `habitDescription` | `String?` | Optional user-facing description |
| `colorHex` | `String?` | Hex string like `"#007AFF"`, parsed via `Color(hex:)` |
| `iconName` | `String?` | SF Symbol name (e.g., `"flame.fill"`) |
| `isArchived` | `Bool` | Soft-delete flag; archived habits hidden from Log/Insights |
| `createdAt` | `Date` | Set at init |
| `events` | `[TemptationEvent]` | `@Relationship(inverse: \TemptationEvent.habit)` — no cascade |

Computed: `todayEventsCount`, `thisWeekEventsCount`, `activeEventsCount`.

### TemptationEvent

| Field | Type | Notes |
|-------|------|-------|
| `id` | `UUID` | No `@Attribute(.unique)` (CloudKit) |
| `occurredAt` | `Date` | Timestamp of log |
| `intensity` | `Int?` | 1–5 scale. Nil = user didn't engage (not "chose 3") |
| `outcome` | `String` | Raw string: `"resisted"`, `"gave_in"`, `"unknown"` |
| `contextTags` | `[String]` | Array of raw strings from `ContextTag` enum. Multiple allowed. |
| `note` | `String?` | Free-text |
| `habit` | `Habit?` | Inverse of `Habit.events` |

**Important:** `outcome` is stored as raw `String` (SwiftData limitation). Use the computed `outcomeEnum` property. Never compare outcome strings directly.

Enums defined in extensions:
- `Outcome` — `.resisted`, `.gaveIn`, `.unknown` with `displayName`, `iconName`, `color`
- `ContextTag` — `.atStore`, `.onPhone`, `.withFriends`, `.alone`, `.atWork`, `.atHome`, `.stressed`, `.bored`

### UserSettings

| Field | Type | Notes |
|-------|------|-------|
| `id` | `UUID` | No `@Attribute(.unique)` (CloudKit) |
| `defaultHabitId` | `UUID?` | Which habit to show first on Log screen |
| `showContextPrompt` | `Bool` | Whether context sheet appears after logging |
| `accentColorHex` | `String?` | User-configurable accent color hex. Nil = system blue. |
| `hasCompletedOnboarding` | `Bool` | Gates onboarding flow |

Singleton pattern: queried as `@Query private var userSettings: [UserSettings]`, accessed via `userSettings.first`.

## Architecture Patterns

### ViewModel Pattern

All ViewModels use `@Observable` (Observation framework, iOS 17+). They are **not** `ObservableObject`.

Views hold ViewModels as `@State private var viewModel: SomeViewModel?` and init in `onAppear`:

```swift
.onAppear {
    if viewModel == nil {
        viewModel = SomeViewModel(modelContext: modelContext)
    } else {
        viewModel?.fetchHabits()
    }
}
```

ViewModels receive `ModelContext` via init, not environment.

### Sheet Sequencing

The Log screen presents two sheets in sequence: outcome -> context. Uses state flag + `onDismiss`:

```swift
.sheet(isPresented: $showOutcomeSheet, onDismiss: {
    if shouldShowContextAfterOutcome {
        shouldShowContextAfterOutcome = false
        showContextSheet = true
    } else {
        vm.triggerConfirmation()
    }
}) { ... }
```

Do **not** use `DispatchQueue.main.asyncAfter` for sheet timing. Always use `onDismiss`.

### Color Handling

- Habit colors stored as hex strings, parsed via `Color+Hex.swift` extension
- Always nil-coalesce: `Color(hex: habit.colorHex ?? "#007AFF") ?? .blue`
- Accent color applied via `.tint()` at the app root in `ContentView`
- Available colors/icons defined as static properties on `HabitsViewModel`

### Manual Cascade Deletion

CloudKit forbids cascade delete rules. When deleting a habit, manually delete all child events first:

```swift
for event in habit.events { modelContext.delete(event) }
modelContext.delete(habit)
```

## CloudKit Constraints

iCloud sync via SwiftData + CloudKit imposes these restrictions:

- **No `@Attribute(.unique)`** — UUID fields cannot use unique constraints
- **All properties must be optional or have defaults**
- **No ordered relationships** — sort at query time
- **No cascading deletes** — implement manually (see above)
- **Additive-only schema migrations** — cannot rename or remove fields once shipped

## Key Design Decisions

| Decision | Choice |
|----------|--------|
| Tone | Clinical, minimal — no emotional language, no persona |
| Appearance | Dark mode default, light mode must also work |
| Accent color | User-configurable from 9 muted hues in Settings |
| Notifications | **None, permanently.** Do not add notification features. |
| iCloud sync | Required for v1 — SwiftData + CloudKit container |
| Distribution | TestFlight -> App Store, free with optional tip jar |
| Haptics | Log action only (`UIImpactFeedbackGenerator`, `.medium`) |
| Navigation | Max one level deep. Tab bar primary. History is only push nav. |
| Error handling | `try? modelContext.save()` with print. No user-facing errors in v1. |
| Sheets | Half-sheet (`.medium`) for quick input, full for forms |

## Conventions

- **No third-party dependencies.** System frameworks only.
- **No notifications.** Permanent design choice.
- **Clinical tone.** No emotional language, no motivational copy. See `docs/design.md`.
- **SF Symbols** for all icons. No custom image assets (except app icon).
- **Hex strings** for colors, parsed at runtime via `Color+Hex`.
- **SwiftData + CloudKit** for all persistence. No UserDefaults, no files.

## Build & Development

```bash
xcodebuild -project Resistor.xcodeproj \
  -scheme Resistor \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build
```

**Simulator:** iPhone 17 Pro (iOS 26). Do not use iPhone 16 runtimes.
**Physical device:** iPhone 16 Pro.
**No CI/CD.** Local builds only.
**No test targets yet.** See `docs/design.md` for test plan.

## Open GitHub Issues

- #35 — App icon design
- #36 — Dark mode audit
- #37 — Accessibility pass

## Remaining Work (v1.0)

- ~~iCloud sync (CloudKit container setup + entitlements)~~ — Done: entitlements + CloudKit ModelConfiguration
- ~~Unit + UI test targets~~ — Done: ResistorTests with 11 test files
- ~~Tip jar (StoreKit 2 consumable IAPs)~~ — Done: TipJarViewModel + StoreKit config
- App icon (minimalist shield) — Issue #35
- ~~Dark mode audit~~ — Done: confirmation banner border, habit card contrast
- ~~Accessibility pass (VoiceOver, Dynamic Type)~~ — Done: selected traits, event grouping, carousel labels
- TestFlight build (requires Xcode: signing, CloudKit container, team ID)

## Design Documents

Full design spec lives in `docs/design.md`, covering:
- Use cases and user flows
- Visual design system (colors, typography, spacing, components)
- Interaction and motion (gestures, haptics, animations, sheet sequencing)
- Content and voice (tone rules, all user-facing strings, forbidden language)
- Privacy and data lifecycle (iCloud sync, export, deletion, privacy labels)
- Testing strategy (unit/UI test plan, coverage targets)
- Release and distribution (TestFlight, App Store, tip jar)
- Accessibility requirements (VoiceOver, Dynamic Type, Reduce Motion)
- Post-v1 roadmap (location clustering, widget, watch)
- Success metrics (quality gates, engagement signals)
