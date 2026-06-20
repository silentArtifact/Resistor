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
│   ├── UserSettings.swift            # @Model — singleton settings
│   └── ContextTag.swift              # @Model — user-defined context tag
├── Services/
│   ├── DataExporter.swift            # CSV/JSON export of temptation events
│   └── LocationManager.swift         # GPS location capture for events
├── ViewModels/
│   ├── LogViewModel.swift            # Log screen logic + Core Haptics engine
│   ├── InsightsViewModel.swift       # Stats, charts, distributions
│   ├── HabitsViewModel.swift         # Habit CRUD, color/icon lists
│   ├── OnboardingViewModel.swift     # First-run habit creation
│   └── TipJarViewModel.swift         # StoreKit 2 tip jar purchases
└── Views/
    ├── ContentView.swift             # TabView + onboarding gate + accent color
    ├── LogView.swift                 # Core logging flow + hold effect (S1)
    ├── InsightsView.swift            # Charts and trends (S2)
    ├── HabitsView.swift              # Habit management + settings (S3)
    ├── HistoryView.swift             # Past events list + detail sheet
    ├── EventMapView.swift            # Map view for location-tagged events
    └── OnboardingView.swift          # First-run flow (S0)
```

## Data Model (SwiftData)

All four entities use the `@Model` macro. CloudKit compatibility constraints apply (see below).

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
| `contextTags` | `[String]` | Array of raw tag name strings. Multiple allowed. |
| `note` | `String?` | Free-text |
| `habit` | `Habit?` | Inverse of `Habit.events` |

**Important:** `outcome` is stored as raw `String` (SwiftData limitation). Use the computed `outcomeEnum` property. Never compare outcome strings directly.

Enums defined in extensions:
- `Outcome` — `.resisted`, `.gaveIn`, `.unknown` with `displayName`, `iconName`, `color`
- `ContextTag` (legacy enum) — `.onPhone`, `.withFriends`, `.alone`, `.stressed`, `.bored`. Kept for backward compatibility with old raw values. Location-based cases removed (GPS covers location). New tags are user-defined strings.

### ContextTag

| Field | Type | Notes |
|-------|------|-------|
| `id` | `UUID` | No `@Attribute(.unique)` (CloudKit) |
| `name` | `String` | User-facing tag name, stored as-is in `TemptationEvent.contextTags` |
| `createdAt` | `Date` | Set at init |

User-defined context tags managed from the Habits & Settings screen. Displayed as selectable chips on the Log screen before logging. Tag names are stored directly in `TemptationEvent.contextTags` as raw strings.

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

### Hold-to-Log Effect

The Log screen's habit card supports both tap and hold-to-log. The hold interaction uses a multi-layered visual effect system:

**State management:**
- `holdProgress` (0→1) — driven by a 30fps `Timer` over 3 seconds
- `glowPulsing` (Bool) — toggled with `.easeInOut(duration: 0.8).repeatForever(autoreverses: true)` for breathing glow
- `isHolding` — tracks active hold state for conditional rendering

**Visual layers (in order):**
1. **Background tint** — habit color fill opacity ramps from 0.1→0.3 with progress
2. **Progress trim ring** — `RoundedRectangle.trim(from: 0, to: holdProgress)` shows concrete progress
3. **Blurred glow border** — stroke with `.blur(radius: 4)`, opacity modulated by pulse animation
4. **Radiating pulse ring** — background stroke that scales to 1.15x and fades, creating outward energy
5. **Layered shadows** — tight (radius 12→28) + wide (radius 30→60) shadows for halo glow
6. **Scale** — card grows to 1.08x during hold
7. **Icon glow** — SF Symbol gets its own shadow that intensifies
8. **UI dimming** — surrounding elements (carousel, labels, count) fade to 50% opacity

**Haptics:** `LogViewModel` manages a `CHHapticEngine` with a continuous haptic pattern. Intensity ramps from 0.2→1.0 and sharpness from 0.1→0.5 via `CHHapticDynamicParameter`, synchronized with `holdProgress`.

All visual effects are gated on `!reduceMotion` for accessibility. The glow pulse uses SwiftUI's native animation system (not manual sine computation) for smooth interpolation.

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
| Haptics | Tap log: `UIImpactFeedbackGenerator(.medium)`. Hold log: Core Haptics continuous pattern with escalating intensity. |
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
**Test target:** `ResistorTests` — unit tests for ViewModels, Models, and Services.

### Xcode MCP bridge (preferred when connected)

An `xcode` MCP server (Apple's `xcrun mcpbridge`) is registered with Claude Code
for this project, giving agents structured access to the **open** Xcode project —
builds, test runs, and diagnostics as data rather than scraped `xcodebuild` log
text. **When the `xcode` MCP tools are available, prefer them** for building,
testing, and reading errors; fall back to the `xcodebuild` command above only
when the bridge isn't connected.

Requires, on the developer's machine: Xcode Settings → **Intelligence** →
**Model Context Protocol** → **"Allow external agents to use Xcode tools"** is on,
the Resistor project is **open in Xcode**, and the session was restarted after the
server was added (MCP servers load at session start). If the `xcode` tools aren't
present, assume one of those isn't satisfied and use `xcodebuild`. The bridge does
**not** manage Signing & Capabilities or Developer-portal provisioning (App
Groups, CloudKit) — those remain manual Xcode steps.

## Development Team (Agent Roster & Routing)

Resistor is built by a roster of role subagents that mirror a software
lifecycle. **The main session is the orchestrator**: when the user talks
naturally, read intent and dispatch the right role via the Agent tool — the user
should rarely have to name an agent. Subagents do not see the main conversation,
so always hand them a self-contained brief.

| The user's request sounds like… | Dispatch | Owns |
|---|---|---|
| "I have an idea…", "what if users could…", "should we add…" | **product-analyst** | use cases, personas, scope → `docs/design.md` |
| "how should this look/flow", "design the … screen" | **ux-designer** | interaction + visual spec → `docs/design.md` |
| "build it", "implement…", "add…", "fix the bug where…" | **implementer** | Swift/SwiftUI/SwiftData, verified build |
| "is it right", "verify…", "write tests", "it's broken" | **tester** | `ResistorTests`/UITests, honest pass/fail |
| "looks off", "the X screen feels…", "improve the spacing" | **ui-iterator** | screenshot-driven visual polish |

**Full feature, end to end:** when the user pitches a feature and wants it taken
all the way (not just discussed), invoke the **`/feature`** skill
(`.claude/skills/feature/SKILL.md`). It chains product-analyst → ux-designer →
implementer → tester → (ui-iterator if UI changed), threading each stage's output
into the next, running unattended, and reporting the consolidated result at the
end. It never commits — it presents the diff and asks first.

**Routing notes:**
- Lifecycle order is product → design → build → test → polish. A pitch starts at
  product-analyst; a bug starts at tester (reproduce) → implementer (fix) →
  tester (verify).
- A non-negotiable collision (notifications, etc.) is caught at the
  product-analyst stage and stops the pipeline — don't design around it.
- Subagents **register at session start only**. After adding or editing an
  agent file, the user must restart the session (or run `/agents`) for it to
  take effect.

## UI Screenshot Harness (for seeing the UI)

To actually *see* the app's UI — for design review or UI/UX iteration — use the
screenshot harness instead of guessing from code:

```bash
export GEM_HOME="$HOME/.gem/ruby/2.6.0"; export PATH="$GEM_HOME/bin:$PATH"
./scripts/ui-shots.sh        # all screens → build/ui-shots/01-Log.png …04-Habits.png
./scripts/ui-shots.sh --dark # dark mode  → build/ui-shots/01-Log-dark.png …
./scripts/ui-quickshot.sh    # fast Log-screen-only → build/ui-shots/quick.png
```

Then **Read** the PNGs. The harness launches the app with the `-uiTestMode`
argument, which boots a clean **in-memory** SwiftData store seeded with
deterministic sample data (`Resistor/Services/UITestSeed.swift`, DEBUG-only) —
so every run renders identical content, skips onboarding, and never touches
real CloudKit data. The `--dark` flag adds `-uiTestDarkMode`, which forces
`.dark` at the app root so you can verify dark mode (hardcoded non-adaptive
colors show up exactly as a dark-mode user sees them). Light and dark captures
coexist on disk; each mode only cleans its own files.

- `ResistorUITests/SnapshotTests.swift` — XCUITest that walks the screens and
  captures named screenshots. Add a screen here to capture it.
- `ResistorUITests` target + its shared scheme were generated by
  `scripts/add_uitest_target.rb` (idempotent; rerun if the target is lost).
- **`.claude/agents/ui-iterator.md`** — a subagent that runs this loop
  autonomously: screenshot → critique vs `docs/design.md` → edit SwiftUI →
  rebuild → re-screenshot → compare. Use it for "the UI is poor, improve it"
  style requests. `build/` is gitignored, so screenshots aren't committed.

## Open GitHub Issues

- #35 — App icon design
- #37 — Accessibility pass (in progress — comprehensive VoiceOver/Dynamic Type sweep)
- #47 — Quick-log widget: device verification + App Group / CloudKit capability setup
- #48 — No haptics firing on device (tap impact + hold Core Haptics both silent)
- #49 — watchOS app: wrist-fast resisted-temptation logging (post-v1, companion to widget)

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
