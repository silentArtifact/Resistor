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
│   ├── ContextTag.swift              # @Model — user-defined context tag
│   └── Place.swift                   # @Model — user-named location + distance matching
├── Services/
│   ├── DataExporter.swift            # CSV/JSON export of temptation events
│   ├── LocationManager.swift         # GPS location capture for events
│   └── PatternFinder.swift           # Trigger detection — see "Pattern Detection"
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
    ├── PlaceNameSheet.swift          # Name/rename the spot an event was logged
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
| `sortOrder` | `Int` | User's drag-to-reorder position. Default 0 |
| `events` | `[TemptationEvent]` | `@Relationship(inverse: \TemptationEvent.habit)` — no cascade |

Computed: `todayEventsCount`, `thisWeekEventsCount`, `activeEventsCount`.

**Ordering is `Habit.displayOrder`, not `createdAt`.** Every habit list — the Log
carousel, the Habits screen, the widget's picker, the watch's picker and fallback
target — sorts by `[sortOrder, createdAt, id]`, so one drag on the Habits screen
reorders all four. Reorder is edit-mode `.onMove` → `HabitsViewModel.moveHabits`,
which rewrites the whole active list to a dense 0..n-1 rather than nudging one
row, so repeated drags can't drift into ties. Until a first drag every habit is 0
and the `createdAt` tiebreak reproduces the pre-`sortOrder` order exactly — which
is also why a *new* habit must take `Habit.nextSortOrder(in:)` at creation
(all three creation sites do), or it would default to 0 and jump to the top.

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

### Place

| Field | Type | Notes |
|-------|------|-------|
| `id` | `UUID` | No `@Attribute(.unique)` (CloudKit) |
| `name` | `String` | Short user-facing name — "Home", "Work" |
| `latitude` / `longitude` | `Double` | The named coordinate |
| `createdAt` | `Date` | Set at init |

A short name the user assigns to a spot. Events within `Place.matchRadius`
(150 m) display the name instead of the coarse reverse-geocoded
"Neighborhood, City" string, in History, on the map, and in Insights' Top
Locations.

**Matching is by distance, never by geocoded name.** At the app's
`kCLLocationAccuracyHundredMeters` fixes, home and the grocery store a mile away
routinely reverse-geocode to the *same* string, so aliasing that string would
rename both. Resolution lives in `Place.swift` as a `Collection where Element ==
Place` extension — `match`, `displayName(for:)` (falls back to the geocoded name,
then raw coordinates), and `groupingName(for:)` (the Insights chart key, which
deliberately drops raw coordinates). Views get the list via `@Query`; the
Insights VM fetches it. Nothing is written onto the event, so naming, renaming,
and un-naming apply retroactively and are lossless.

Duplicate names are allowed on purpose: a drifting fix or a site with two
entrances is covered by saving a second `Place` with the same name, and display
groups by name.

Named from `PlaceNameSheet`, reachable two ways — tap a pin on the Event Map, or
tap the Location row in a History event's detail. There is no manage-places list
in Settings; a place is renamed or removed through the same sheet.

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

### Pattern Detection (Insights "Patterns" card)

`Services/PatternFinder.swift` answers the question the rest of Insights can't:
every other chart reads **one** axis, so a run of Friday evenings hides inside
two unremarkable bars. It extracts categorical facets — time of day, weekday,
place (via `Place.groupingName`), each context tag — counts every **pair**, and
compares the observed count against what independent marginals predict.

**It counts temptations and never outcomes.** No resisted percentage appears on
the card, and `Pattern` has no outcome field to put there. The card answers
"what sets me off"; whether the urge was then resisted answers "how am I doing",
and the two side by side read as a grade on the situation rather than a
description of it. Progress is still visible, in the right currency: a trigger
the user is beating **thins out**, and the row says so — "1 of the last 8
Mondays" where it once read 7 of 8. `testOutcomeDoesNotAffectPatterns` pins it.

**The unit of evidence is an occasion, not an event.** An occasion is every
event for the habit on the same day inside the same time-of-day period, built by
`PatternFinder.occasions(of:places:)` (facets unioned across the sitting). Two
logs forty minutes apart on one Friday evening are one data point. Counting them
as two independent binomial trials inflates every statistic here, worst for
exactly the compulsive-logging user the app exists for. `minimumOccasions` (10)
is therefore counted in occasions too, and so is every displayed count.

Load-bearing decisions; changing any one silently degrades the card:

- **Ranked by size, filtered by significance.** `sortKey` orders on
  live-before-faded, then occasion count. The p-value only filters and breaks
  ties. Ranking *by* p-value was wrong for this product: a rare pair has a rare
  expectation to divide by, so a 4-occasion fluke (p=1.7e-3) outranks a
  12-occasion trend (p=3.5e-3) — the reverse of what the user is asking.
  `binomialTail` — P(X ≥ observed) under Binomial(n, expected) — still decides
  *whether* a pattern is believable. (An earlier version used a Wilson lower
  bound on the support; it does not fix the ranking, because the expectation is
  small too. Lift survives only as a floor and is never displayed.)
- **A faded pattern sinks but stays.** `Recent.isActive` is false when a pattern
  has no match in its recent window, which drops it below every live one. It is
  still listed — beating something is worth seeing — but it is history, not
  something to prepare for.
- **p ≤ 0.01, not 0.05.** Dozens of candidate pairs are tested at once. At 0.05
  roughly one in twenty clears the bar on noise alone.
- **Overlap suppression.** One real cluster satisfies several pairs
  simultaneously ("Friday · Evening", "Evening · Bored", "Friday · Bored" —
  identical occasions, identical counts). A greedy pass takes a pattern only if
  ≥50% of its occasions aren't already covered, or the card lists one finding
  four times.
- **Deterministic ties.** Those restatements tie on every statistic, and
  `Dictionary` iteration order is not stable across launches. `Pattern.sortKey`
  falls through to dimension rank (day/time before place before tag) then label.

**Mined over all time, reported over a recent window.** A 7-day window holds too
few occasions for any pair to clear the noise floor, so the card sits *above* the
range picker on Insights — everything below the picker is range-scoped, this
isn't, and underneath it the card both looked scoped and contradicted the Peak
Day / Peak Time cards it sat under. Each row states its own window instead:
`frequencyDescription` reads "7 of the last 8 Fridays, 10 in all" (weekday slot,
`recentWeekdaySlots` = 8; day slot for time-only patterns, `recentDaySlots` = 14;
plain count when the pattern has no recurring slot at all).

**The recency tally is the row's one graphic, and it is drawn from
`Recent.hits`.** That array is one `Bool` per slot in the window, **oldest
first** — kept per-slot rather than pre-summed because the ratio alone cannot
show *direction*, and direction is the only progress this app claims. One 4pt
mark per slot, filled where the situation occurred, so the mark count *is* the
window length: eight Fridays draw eight marks, and a trigger being beaten
visibly empties from the right. `testRecentHitsRunOldestFirst` pins the
ordering, because a reversed array would report a fading trigger as a worsening
one — the exact inversion of the claim. Load-bearing details: marks are 4pt wide
with 3pt gaps (tighter and they merge into a bar instead of staying countable,
and the empty slots lose the area they need to register at all — which is the
whole row in the 0-of-8 case); the fill is `.tint`, because Insights has no
accent plumbing and inherits the root `.tint()`; and a **faded** pattern drops to
a neutral `secondaryLabel` fill rather than a dimmer accent, so the single thing
colour means on this row stays "still live". The tally is
`accessibilityHidden` — the line beside it states the same ratio in words.

**Rows are sentences, not facet lists.** `Pattern.summary` templates on facet
*type* — "Friday mornings around 11 AM, at Home", "Evenings, when bored" — rather
than joining display names with middots (`label` still does that, internally, for
tie-breaks). `typicalHour` names a specific hour only when ≥60% (`hourAgreement`)
of the cluster's events share that exact clock hour; agreement is measured on the
exact hour rather than a ±1 window because Evening is four hours wide, so an even
spread still puts 75% within ±1 of the middle and would falsely claim "around
7 PM". `Pattern.id` includes the dimension rank so a Place and a context tag that
share a name stay distinct rows.

**Two surfaces beyond the card.** `PatternFinder.active(in:at:)` matches the
current moment against the **calendar facets only** — place and context describe
what an occasion turned out to be, and neither is knowable before the user logs
(asking for a GPS fix to decide whether to show a line of text is not a trade
worth making). `LogViewModel.activePattern` feeds a heads-up above the habit card
on the Log screen — a `calendar.badge.clock` glyph, a small "Usual time" label,
and the sentence itself: *"Friday mornings around 11 AM, at Home."* The label
sits **above** the finding rather than in front of it; the earlier *"This is a
usual time — …"* preamble spent the whole first line before saying anything and
pushed the sentence — the part that has to be read at a glance — down into a
wrapped clause. The glyph is calendar-and-clock, not
`clock.badge.exclamationmark`: the finding is a weekday and an hour, and the app
does not raise alarms. That is the whole point of the feature — being ready
before the temptation lands — and with notifications permanently out, the Log
screen is the only place it can arrive. Tapping a row on Insights pushes `HistoryView(habit:
pattern:)`, which re-filters with the same `facets(of:)` call, so the list can't
disagree with the count the row claims.

**Three-facet patterns come from refining an accepted pair, never from mining
triples directly** — and the reason is the opposite of the intuitive one. Triples
need *less* data, not more: a triple's expected share is its parent pair's times
a third probability ≤ 1, so it always clears significance more easily. At 100
occasions a pair needs 13 matches, a triple 8; at 30, 4 (pinned by
`testTripleWouldClearAtLowerSupportThanItsParentPair`). Mining them directly
would re-admit the 3-of-3 coincidence the tail test exists to reject, over a
candidate pool several times larger.

So `refining` runs *after* a pair has won its slot: it appends a third facet only
when ≥70% (`refinementRetention`) of that pair's occasions carry it, and the
resulting triple must still clear every floor on its own. The pair earned the
evidence; the triple only sharpens how it reads. Consequences worth knowing:

- Refinement **never adds a row**. It relabels an accepted one, so the ranking
  and the dedup are still decided entirely by the pair pass.
- A third facet on *half* the cluster is rejected on purpose. It would be a
  sub-cluster — reporting it shrinks a finding the user already had.
- It stops at three. A fourth facet is just another pass, but a four-clause
  sentence stops being something a user can act on.

`UITestSeed` **plants a cluster** — Sugar, at Home, on the weekday and hour the
harness is *running in*, ten weeks back — and drops that period from the base
hour rotation. Both details are load-bearing. The base data is uniform by
construction, so without the plant the harness can only capture the card's empty
state; and the Log heads-up only renders while the clock is inside a pattern, so
a fixed Friday-evening cluster would be uncapturable on any other day. Ten weeks,
not four: at occasion counting, four is four data points against ~28 and does not
clear the significance floor.

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
| Notifications | **None, permanently.** Do not add notification features. (Does *not* cover the silent CloudKit sync push — see below.) |
| iCloud sync | Required for v1 — SwiftData + CloudKit container |
| Distribution | TestFlight -> App Store, free with optional tip jar |
| Haptics | Tap log: `UIImpactFeedbackGenerator(.medium)`. Hold log: Core Haptics continuous pattern with escalating intensity. |
| Navigation | Max one level deep. Tab bar primary. History is only push nav. |
| Error handling | `try? modelContext.save()` with print. No user-facing errors in v1. |
| Sheets | Half-sheet (`.medium`) for quick input, full for forms |

## Conventions

- **No third-party dependencies.** System frameworks only.
- **No notifications.** Permanent design choice. **One apparent exception that
  isn't one:** both the phone and watch carry `aps-environment` and the
  `remote-notification` background mode, and the App IDs have Push Notifications
  enabled. That is the *silent* push `NSPersistentCloudKitContainer` needs to
  learn the remote database changed — without it a watch log took minutes to
  reach the phone, because the store only imported at launch. There is no
  `UNUserNotificationCenter.requestAuthorization` call anywhere, no permission
  prompt, and no alert/badge/sound. The rule is about user-facing notifications
  and still holds absolutely. Don't "remove the notification stuff" on sight, and
  don't treat it as a precedent for adding real notifications.
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
**CI:** GitHub Actions (`.github/workflows/ci.yml`) build-and-tests every PR and
push to `main` on a `macos-15` runner. It pins **Xcode 26.3** and the **iPhone 17
Pro** simulator to match local builds — keep CI and local on the same Xcode 26
toolchain so the Swift type-checker behaves identically (Xcode 16.4's solver timed
out on `LogView`'s habit card; 26's does not). The workflow downloads the watchOS
runtime before testing because the scheme embeds the watch app (see below).
**Test target:** `ResistorTests` — unit tests for ViewModels, Models, and Services.

**`ResistorUITests` is also in the `Resistor` scheme's test action, with the five
screenshot-harness `testCapture…` tests explicitly skipped** — so CI runs the
UITest target's *assertions* but not its captures. The captures are a dev tool
(one taps an Insights chart band by computed pixel offset with a 2s timeout,
which flakes on a slower runner rather than signalling anything). Consequences:
a new assertion UITest runs in CI automatically, which is the point; a new
`testCapture…` must be added to `<SkippedTests>` in
`xcshareddata/xcschemes/Resistor.xcscheme` or it will run there too. Verify what
the scheme will actually run without running it:

```bash
xcodebuild test-without-building -project Resistor.xcodeproj -scheme Resistor \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -enumerate-tests -test-enumeration-style flat
```

The full UITest suite (captures included) still runs under the separate
`ResistorUITests` scheme, which is what `scripts/ui-shots.sh` drives.

**watchOS runtime required for the iOS test action.** The `Resistor` scheme now
embeds the `ResistorWatch` watch app (Embed Watch Content phase), so
`xcodebuild test -scheme Resistor …` builds the watch app and **fails on a fresh
checkout without the watchOS simulator runtime** ("watchOS … must be installed in
order to test the scheme"). Install it once with `xcodebuild -downloadPlatform
watchOS` (~4 GB). Build the watch app directly with:

```bash
xcodebuild -project Resistor.xcodeproj \
  -scheme ResistorWatch \
  -destination 'generic/platform=watchOS Simulator' \
  build
```

The watch app (`ResistorWatch/`) is a single-screen quick-log companion (issue
#49). **Release logs** — a flick and a 3s hold both write an event, matching the
phone, where the ramp changes how it feels, not whether it commits. Holding past
3s keeps buzzing until release.

**Habit switching:** tapping the habit name (a chevron appears once there is more
than one active habit) opens a full-screen list. Not a swipe across the button —
that already owns press-and-hold, and the phone's carousel needed a 0.15s arming
delay to stop every swipe flashing the hold visuals. The pick lives in memory
only (`WatchLogStore.selectedHabitID`) and resets to the default habit on
relaunch, exactly like the phone's Log screen; persisting a watch-local override
would make the two devices disagree about what "the" habit is. Target resolution
is pick → `UserSettings.defaultHabitId` → first in `Habit.displayOrder`, and a
pick that gets archived falls back rather than logging to an archived habit.

**Location:** the watch logs coordinates like the phone, via the *same*
`Resistor/Services/LocationManager.swift` (CoreLocation and `CLGeocoder` both
exist on watchOS) — it's a member of the watch target, wired by
`scripts/add_watch_target.rb`. The capture itself is
`LocationProviding.attachLocation(to:in:)`, shared by `LogViewModel` and
`WatchLogStore`; it fires after the event is saved, so no fix just means no
location, never a failed log. It drops the write if the event was undone while
the fix was in flight. The watch needs its **own**
`NSLocationWhenInUseUsageDescription` (in `ResistorWatch/Info.plist`) and its own
authorization — the phone's grant does not carry across devices, so the watch
prompts on first launch. `Place` naming is unaffected: nothing is written onto
the event, so a watch-logged coordinate resolves to a named place on the phone
retroactively.

Two watch-specific traps, both load-bearing:

- **`CHHapticEngine` does not exist in the watchOS SDK.** The phone's continuous
  ramped pattern is approximated by a repeated discrete `WKHapticType.click` at a
  tightening gap. Don't try to port `LogViewModel`'s Core Haptics code; it cannot
  compile there.
- **The hold gesture's `minimumDuration` is 86,400s on purpose.** A long press
  that *succeeds* ends the gesture and reports the press as over while the finger
  is still down, cutting the haptic off mid-hold. Setting it beyond any real press
  means only `onPressingChanged` fires and `perform` is dead by design. Don't
  "fix" it to 3s.

Shake-to-undo (`ShakeDetector.swift`) deletes the last logged event within a 5s
window, via Core Motion — watchOS has no shake gesture API. The accelerometer runs
only during that window.

It has its **own** SwiftData `ModelContainer` on the same
CloudKit container (`iCloud.com.resistor.app`) — App Groups do **not** bridge
iPhone↔Apple Watch, so phone/watch parity comes from CloudKit sync, not the
shared App-Group store the widget uses. The target is wired by the idempotent
`scripts/add_watch_target.rb` (rerun if the target is lost).

**The watch target shares the iOS app's `Resistor/Assets.xcassets`** — its
`AppIcon.appiconset` carries both an `ios` and a `watchos` 1024x1024 entry
pointing at the same PNG (one image, no duplication). Keep the membership: a
shipped watch app needs an icon, and App Store validation rejects icons with an
**alpha channel** (verify with `sips -g hasAlpha`).

**Correction (2026-07-29):** an earlier version of this note claimed a missing
icon was what made the install ring fill and then revert to "Install". That was
wrong — a guess from a plausible detail, never verified. The actual cause was
that the Apple Watch had **never been registered as a development device**, so no
provisioning profile covered it. Two other explanations were also asserted and
disproven along the way (the App ID's iCloud capability, the profile's `Platform`
array). If you see the install-ring revert, check device registration and the
profile's `ProvisionedDevices` **first** — read the artifacts (`security cms -D -i
<profile> | plutil -p -`), don't reason from what looks likely.

`ResistorWatchComplication/` is a watchOS WidgetKit app extension
(`com.resistor.app.watchkitapp.complication`) embedded in **ResistorWatch**'s
PlugIns and wired by the idempotent `scripts/add_watch_complication_target.rb`.
It exists so the watch app is reachable from a watch face — the whole point of
wrist-fast logging. It is a static launcher glyph only: `StaticConfiguration`,
one timeline entry, `.never` policy, no entitlements / App Group / SwiftData and
zero shared source. Tapping a complication launches its owning app on watchOS,
so there is no deep-link plumbing. Showing live data (e.g. today's resisted
count) would require moving the watch store into an App Group so the extension
process could read it — deferred.

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
  - The `com.resistor.app.watchkitapp` App ID needs iCloud enabled with the
    `iCloud.com.resistor.app` container selected, **and** Push Notifications
    enabled (for the silent CloudKit sync push) — automatic signing won't mint a
    profile for an entitlement the App ID lacks. Both are set as of 2026-07-29.
  - **If the install ring completes and then reverts to "Install":** check that
    the watch is a registered development device and appears in the profile's
    `ProvisionedDevices`. That — not a missing icon — was the cause last time.

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
