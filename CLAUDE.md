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
│   ├── Place.swift                   # @Model — user-named location + distance matching
│   └── ContactPlace.swift            # @Model — geocoded contact address, device-local cache
├── Services/
│   ├── DataExporter.swift            # CSV/JSON export of temptation events
│   ├── LocationManager.swift         # GPS location capture for events
│   ├── ContactMatcher.swift          # Opt-in address-book geocoding → ContactPlace
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
    ├── HabitStylePicker.swift        # Colour + icon sections shared by both habit forms
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

**Ordering is `Habit.displayOrder`, not `createdAt`, and the first habit in it is
the default habit.** Every habit list — the Log carousel, the Habits screen, the
widget's picker, the watch's picker and target — sorts by `[sortOrder, createdAt,
id]`, so one drag on the Habits screen reorders all four *and* changes which habit
the phone's Log screen and the watch open on. There is no separate default-habit
setting: `UserSettings.defaultHabitId` was orphaned on 2026-08-03 (issue #60)
because two user-settable orderings could disagree — the list showed one habit
first and the app opened on another, and the "Default" badge was the only clue.
Reorder is edit-mode `.onMove` → `HabitsViewModel.moveHabits`,
which rewrites the whole active list to a dense 0..n-1 rather than nudging one
row, so repeated drags can't drift into ties. Until a first drag every habit is 0
and the `createdAt` tiebreak reproduces the pre-`sortOrder` order exactly — which
is also why a *new* habit must take `Habit.nextSortOrder(in:)` at creation
(all three creation sites do), or it would default to 0 and jump to the top — and
now that first place *is* the default habit, that would also silently retarget the
Log screen and the watch.

**The grip glyph on a habit row is the only hint the order is the user's.** Out of
edit mode a `List` gives none, and the order now decides what the app opens on, so
each row carries a `line.3.horizontal` in `.tertiary` when there are 2+ active
habits — tappable (it turns edit mode on), because a drag on it does nothing until
the list is editing. It stands down in edit mode so it doesn't double the system's
own grip. `HabitsView` therefore owns its `isEditing` state and installs
`\.editMode` itself rather than using `EditButton`: `EditButton` writes to the
`editMode` the `NavigationStack` installs *below* `HabitsView`'s own environment,
so the rows could never read it to know when to stand down.
`testHabitOrderDecidesWhichHabitLogOpensOn` pins both halves — that "Edit" really
reaches UIKit (the grips exist), and that a drag moves which habit Log opens on.

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

**The five defaults are seeded whenever the list is empty, which races CloudKit**
— the same shape of bug as the `UserSettings` singleton, and it shipped: a
device that seeds its own five and *then* receives five more shows every default
chip twice on the Log screen. `ContextTag.mergeDuplicates` collapses them from
`ContentView.initializeSettingsIfNeeded`, keeping the lowest `id` per name.

Deduplicating by **name** is lossless here, and this is the one place that's
true: `TemptationEvent.contextTags` holds raw name strings, never tag IDs, so
two rows with one name are the same tag stored twice and deleting either leaves
every event untouched. Contrast `Place`, where two rows sharing a name are a
deliberate feature. Matching is exact — folding case would silently merge a
"bored" the user typed into the seeded "Bored".

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

Named from `PlaceNameSheet`, reachable three ways — tap a pin on the Event Map,
tap the Location row in a History event's detail, or swipe a History row from the
**leading** edge. The swipe appears only when `canName` holds (located, not in
transit, no `Place` matching yet), so it is offered exactly when the row is
showing the fallback the name would replace; the trailing edge stays Delete's,
because that is the edge a full swipe fires. There is no manage-places list in
Settings; a place is renamed or removed through the same sheet.

**The sheet suggests names; it never applies one.** Three sources fill the text
field — businesses at the coordinate (`MKLocalPointsOfInterestRequest`, radius
`Place.matchRadius`, so a POI outside what a saved place would cover is never
offered), names already in use, and Contacts. Auto-picking the nearest POI is the
same wrong answer with a more authoritative name: a
`kCLLocationAccuracyHundredMeters` fix in a strip mall has a dozen candidates,
and unlike a blank it enters `PatternFinder` as a confident facet. The user
confirming is what `Place` was designed around.

Contacts arrive two ways, and the cheap one is not the fallback for the
expensive one — they answer different questions:

- **`ContactNamePicker`** wraps `CNContactPickerViewController`, which runs **out
  of process**: no `CNContactStore` authorization, no prompt, no privacy label,
  and the delegate is handed only the contact that was tapped. Always available.
  Its `onPick` fires on cancel too, with nil — the picker dismisses itself, so a
  SwiftUI `isPresented` left true would strand the sheet closed-but-presented and
  it could never reopen.
- **`ContactMatcher` + `ContactPlace`** (opt-in, from Settings › Contacts) geocode
  the address book once so a contact's name appears *without* picking a source.
  That is the only thing it buys, and it costs full Contacts access, a privacy
  label and a rate-limited geocode per contact — hence a button the user presses,
  never anything automatic. Only the name string is read either way; the place
  still saves at the *event's* coordinate, so no postal address is stored and
  nothing is forward-geocoded onto an event.

`ContactPlace` is **not** a `Place` despite the identical shape, and it lives in
its own `cloudKitDatabase: .none` store — see "The store lives in the App Group"
below.

Settings shows an action and a resting state ("Match My Contacts" / "Matched — N
contacts" + Remove), **not a `Toggle`**: a toggle would have to flip itself back
off whenever a run matched nothing — access declined, or no contact has an
address — which reads as a broken switch. Nothing here is a setting; either
matches exist or they don't.

**The sheet suggests names; it never applies one.** Three sources fill the text
field — businesses at the coordinate (`MKLocalPointsOfInterestRequest`, radius
`Place.matchRadius`, so a POI outside what a saved place would cover is never
offered), names already in use, and the address book. Auto-picking the nearest
POI is the same wrong answer with a more authoritative name: a
`kCLLocationAccuracyHundredMeters` fix in a strip mall has a dozen candidates,
and unlike a blank it enters `PatternFinder` as a confident facet. The user
confirming is what `Place` was designed around.

`ContactNamePicker` wraps `CNContactPickerViewController`, which runs **out of
process** — no `CNContactStore` authorization, no permission prompt, no privacy
label, and the delegate is handed only the contact that was tapped. Only its
name string is read; the place still saves at the *event's* coordinate, so no
postal address is touched and nothing is forward-geocoded. Keep it that way:
matching contacts by address (issue #78 Stage B) buys one tap and costs full
address-book permission plus a geocode per contact. Its `onPick` fires on cancel
too, with nil — the picker dismisses itself, so a SwiftUI `isPresented` left true
would strand the sheet closed-but-presented and it could never reopen.

### UserSettings

| Field | Type | Notes |
|-------|------|-------|
| `id` | `UUID` | No `@Attribute(.unique)` (CloudKit) |
| `defaultHabitId` | `UUID?` | **Orphaned.** Nothing reads it — the first habit in `Habit.displayOrder` is the default. Still merged by `mergeDuplicates` |
| `showContextPrompt` | `Bool` | **Orphaned.** Gated the post-log context sheet, which no longer exists. Nothing reads or sets it — see Sheet Dismissal |
| `accentColorHex` | `String?` | User-configurable accent color hex. Nil = system blue. |
| `hasCompletedOnboarding` | `Bool` | Gates onboarding flow |

Singleton pattern: queried as `@Query private var userSettings: [UserSettings]`, accessed via `userSettings.first`.

**It is a singleton by convention only, and the convention has already broken
once.** CloudKit forbids `@Attribute(.unique)`, so nothing stops two devices —
the phone and the watch, which sync through the same container — from each
creating this record before either has seen the other's. All 13 read sites take
`.first` on a query with **no sort descriptor**, so with two rows present the app
answers *differently from launch to launch*. Found on a real device on
2026-08-01: two rows, one with a `defaultHabitId` pointing at a habit that never
existed, which read as "my habits are gone" without a byte of data being lost.

`UserSettings.mergeDuplicates` collapses them on every launch from
`ContentView.initializeSettingsIfNeeded` — every launch, not once, because a
duplicate can arrive from CloudKit at any point. The survivor is the lowest
`id`: arbitrary, but stable and identical on every device, so two devices
repairing at the same moment converge instead of deleting each other's keeper.
Fields **merge** rather than inherit from the keeper — each takes the most
explicit value across the duplicates — because the rows hold real choices made
on whichever device wrote them. `hasCompletedOnboarding` is `true` if *any* row
says so; the alternative is a stale row throwing the user back into first-run
over live data.

Don't "simplify" this to keeping `.first` and deleting the rest.

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

### Sheet Dismissal

**Do not use `DispatchQueue.main.asyncAfter` to time anything off a sheet. Always
use `onDismiss`.** Live referent: `LogView`'s Add Habit sheet rebuilds or refetches
the view model in `onDismiss`.

This entry used to document a two-sheet outcome → context sequence on the Log
screen. **That flow no longer exists** — `showOutcomeSheet`,
`showContextSheet` and `shouldShowContextAfterOutcome` are all gone. Logging
defaults to `resisted` and is corrected afterward from the confirmation banner;
context is chosen as inline chips *before* the tap. Nothing presents between the
log tap and the banner, which is why the banner no longer needs sequencing at all.

The rule survived its flow because the flow is *why* it exists: the banner
originally fired on a guessed delay and landed behind the sheets it was supposed
to follow. Any future sheet chain must still use `onDismiss`.

**Three fields were orphaned when those sheets went, and none of it is visible
from the models:**

- `TemptationEvent.intensity` — no capture UI anywhere. Read-only in the History
  detail; Insights' "Intensity Trend" card can only render against `UITestSeed`
  data, never a real device's.
- `TemptationEvent.note` — displayed in History and the export, written by no
  view. `LogViewModel.updateEventContext(contextTags:note:)` still exists and is
  unit-tested, with **no production caller**.
- `UserSettings.showContextPrompt` — still defaulted, still merged by
  `mergeDuplicates`, read by nothing.

All three are live in the Production CloudKit schema (deployed 2026-07-31), so
restoring capture for any of them needs UI only — no migration, no schema deploy.
Don't delete them to "clean up": Production record fields can never be removed.

**`UserSettings.defaultHabitId` joined them on 2026-08-03** (issue #60), for a
different reason — not an orphaned sheet, a deliberately removed feature. Its
merge in `mergeDuplicates` is kept rather than deleted, on the same reasoning as
`showContextPrompt`'s: the field cannot leave Production, and a merge that resolves
the more plausible of two values costs nothing while a deleted one would have to be
rewritten if the setting ever comes back.

### Color Handling

- Habit colors stored as hex strings, parsed via `Color+Hex.swift` extension
- Always nil-coalesce: `Color(hex: habit.colorHex ?? "#007AFF") ?? .blue`
- Accent color applied via `.tint()` at the app root in `ContentView`
- Available colors/icons defined as static properties on `HabitsViewModel`

**One muted palette, no system colours.** The app used to ship two: nine muted
accent hues in Settings, and — for habits, and therefore for every chart bar,
history icon, Log card and widget — the raw iOS system wheel (`#007AFF`,
`#34C759`, `#FF9500`…). Most of the app's colour came from the second one, so
the parts a user actually looked at were the parts that looked like a default.
Three rules keep it unified:

- `HabitsViewModel.availableColors` is the **habit** palette — 20 hues ordered
  warm → cool → neutral so the grid reads as a sweep rather than as an
  accretion; it and `UserSettings.accentPalette` are the only palettes.
  Everything is mid-tone because a habit colour has to work as chart ink and as
  a filled glyph on both a white card and a black one. New habits take
  `availableColors[0]` (Sand stays first for that reason) — don't reintroduce a
  `#007AFF` literal at a creation site. `testColorsAreMidTone` pins the
  lightness band, which is the part that actually stops rendering;
  "muted" itself is a design judgement no threshold separates cleanly from the
  system wheel, so it isn't asserted.
- `TemptationEvent.Outcome.color` is **not** `.green` / `.orange` / `.gray`.
  Those three are the most-repeated ink in the app (History badges, the Outcomes
  bar, the Log confirmation banner, map pins) and at full saturation they were
  the loudest thing on every screen, in an app whose tone is deliberately
  clinical. A saturated green also grades the user — it's the colour of a pass
  mark. The muted sage/sienna/slate are the **only** colours in the app that
  vary by mode, via `Color(light:dark:)`: they're drawn as text on a 20% wash of
  themselves, so they have to clear 4.5:1 against both a near-white and a
  near-black background and no single muted tone does both. (`Color(light:dark:)`
  falls back to the dark value on watchOS, which has no light mode and no
  `UIColor(dynamicProvider:)`.)
- `UserSettings.defaultAccentColor` is what a nil `accentColorHex` means —
  Lavender, not the system tint. Onboarding runs before any accent is chosen, so
  falling through to `.accentColor` made the one screen every user sees the one
  screen with none of the app's own colour in it. `UserSettings` owns the accent
  palette because three separate views resolve it.

### Habit icons: a curated catalogue behind a search box

There is **no public API to enumerate SF Symbols**, so the reachable set is a
hand-written list in `HabitsViewModel`, in three parts:

- `availableIcons` — the ~20 common habits, shown when the search box is empty,
  and the source of the `circle.fill` default.
- `iconCatalog` — everything else the search can reach, grouped by what someone
  might be tracking. Curated, not exhaustive: a flat grid of several thousand
  symbols is unusable, and the empty state is the suggested set precisely so the
  common case doesn't change.
- `iconKeywords` — search words a symbol's own **name** doesn't contain. Matching
  reads dots as spaces, so "run" already finds `figure.run`; this covers the
  cases where it doesn't, and nothing in `cup.and.saucer.fill` says coffee.
  `testEveryKeywordedIconIsInTheCatalog` catches a key that names no symbol,
  which would otherwise be silent dead weight.

**A wrong name doesn't fail — it renders nothing.** `Image(systemName:)` on a
name that isn't a symbol draws a blank and reports no error, so `allIcons` filters
the catalogue through `UIImage(systemName:)` at runtime, and
`testEveryCatalogIconIsARealSymbol` asserts every entry resolves. Those two look
redundant and aren't: the filter is for a symbol a *later* SDK added, which
should degrade to absent on an older OS; the test is for a typo, which should
fail the build. Without the test, a typo is indistinguishable from the first case.

That is not hypothetical. `"cigarette.fill"` shipped in `availableIcons` from v1
and drew a blank tile the whole time — Apple ships no cigarette symbol under any
name (issue #82). Smoking being near the app's central use case, it was close to
the worst possible entry to have broken. `smoke.fill` replaced it, and
`"cigarette"` is a keyword on `smoke.fill` and `lungs.fill` so the word still
reaches a glyph. **Verify a new symbol name against a real `UIImage(systemName:)`
call rather than against how plausible it looks** — plausibility is exactly what
made this survive.

`HabitStylePicker` is the Color and Icon `Section`s of a habit form, shared by
the Habits screen's editor and the Log screen's Add Habit sheet, which carried
identical copies. One copy, so the search only had to be built once. It also
prepends the selected icon to the default grid when the icon isn't one of the
suggested twenty — otherwise editing a habit whose icon came from a search opens
on a grid with nothing selected in it. **Onboarding deliberately keeps its own
horizontal strips** and offers no search: it is a first-run flow, its layout is a
scroll strip rather than a form, and the icon is changeable a tap later.

### Manual Cascade Deletion

CloudKit forbids cascade delete rules. When deleting a habit, manually delete all child events first:

```swift
for event in habit.events { modelContext.delete(event) }
modelContext.delete(habit)
```

### History rows: two lines, one of them a sentence

An event row carries two different kinds of fact, and they must not share a line.
The outcome, the habit and the time are fixed — exactly one of each, every time.
The circumstances (place + context tags) are a variable-length list. They used to
race in a single `HStack`, so SwiftUI compressed whichever lost: "Gave In"
hyphenated to "Gav / e In", "Resisted" to "Re- sist- ed", and a place truncated
to "H…" on one row while the row below had room for "Home".

So: line one is `outcomeLabel` + habit name (unscoped lists only) + time, with
the badge `.fixedSize()` because the verdict is the one thing that must never
wrap. Line two is the circumstances as **one dot-separated line** — "Home ·
Stressed · Bored" — not a run of chips. Chips gave five grey boxes the same
visual authority as the outcome and each truncated independently; a single line
truncates once, at the end, where it costs least. The `location.fill` glyph marks
the leading item as a place, which was the only distinction the chips carried.

### Insights: no filler labels, no duplicated facts

Two rules the screen kept breaking:

- **A label must say something the title doesn't.** "Peak Time / Night / *of
  day*" and "Peak Day / Sun / *of week*" restated the title in smaller type.
  `StatCard.subtitle` is optional for exactly this — omit it rather than fill it.
  "temptations" and "−10%" stay, because those are a unit and a figure.
- **Don't state a fact twice on one scroll.** A "Top Location" stat card sat
  above a "Top Locations" chart naming the same place with two more behind it.
  The card is gone.

Top Locations is a hand-built list (name + count on its own full-width line, bar
underneath), not a `Chart` with a category axis: place names are long enough
("Financial District, San Francisco") that Charts drew the labels inside the plot
on top of their own bars.

**The card is the way to the Event Map**, and it renders unconditionally — the
"View Map" link that used to sit below it is gone, since it opened an unfocused
map and asked the user to find again the place they had just tapped past. Two
targets, no nesting:

- **A row** pushes the map framed on that place
  (`EventMapView(habit:focusLocation:)`, camera fitted to that grouping name's
  pins, floor ~500 m so a lone pin isn't zoomed to the pavement).
- **The header's "Map ›" accessory** pushes it unfocused, and is what makes the
  card safe to render empty.

**Neither the card nor the accessory may be gated on `locationDistribution()`.**
An event carries a coordinate long before it carries a name — the geocode can
fail or return nothing — and naming is done *on the map*, so gating strands
exactly the user who has never named anything: no rows → no card → no map → no
way to ever get a row. The empty body distinguishes the two cases via
`InsightsViewModel.hasAnyLocatedEvent`, which is computed over the habit's
**whole history**, not `cachedEventsInRange`: the map isn't range-scoped, so a
7-day range must not claim "No location data yet" over a map full of pins.
`testUnnamedCoordinatesStillCountAsLocationData` and
`testLocatedEventOutsideRangeStillCountsAsLocationData` pin both halves.

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

### Shake to Undo

Shaking the phone while the confirmation banner is up undoes the log — the same
gesture and the same 5s window as the watch, so the two devices don't disagree
about how a mislog is taken back. On iOS this needs no Core Motion (the watch's
`ShakeDetector` exists only because watchOS has no shake gesture): UIKit's
`.motionShake` arrives on the responder chain, and a category override on
`UIWindow` at the bottom of `LogView.swift` reposts it as a `Notification`.

Two things there are load-bearing. It **calls `super`** — iOS's own
shake-to-undo for text editing runs through the same path, and swallowing the
event breaks it in the note and habit-name fields. And it is a **second path,
not a replacement**: the banner keeps its Undo button, because Reduce Motion and
motor-accessibility users can't shake and undo has to stay reachable without
motion.

## CloudKit Constraints

iCloud sync via SwiftData + CloudKit imposes these restrictions:

- **No `@Attribute(.unique)`** — UUID fields cannot use unique constraints
- **All properties must be optional or have defaults**
- **No ordered relationships** — sort at query time
- **No cascading deletes** — implement manually (see above)
- **Additive-only schema migrations** — cannot rename or remove fields once shipped

### Two configurations: the synced store, and a device-local cache

`SharedModelContainer` opens **one container over two `ModelConfiguration`s**.
`cloudSchema` (Habit, TemptationEvent, UserSettings, ContextTag, Place) is the
user's data and mirrors to CloudKit. `localSchema` is `ContactPlace` alone, in
its own `ContactPlaces.store` with `cloudKitDatabase: .none`. `schema` is the
union, because `ModelContainer(for:)` has to cover every configuration.

Three things fall out of keeping the contact cache local, and all three are the
point:

- **No postal address ever leaves the phone.** It is geocoded from Contacts,
  which the user's devices already sync themselves — mirroring it again would put
  the address book in the app's CloudKit database for nothing.
- **No `CD_ContactPlace` to deploy.** A new synced `@Model` is a Production record
  type someone has to create by hand and deploy before it works for a TestFlight
  user (see below); a local one is live the moment it builds.
- The cost is a rebuild per device, which is exactly the Settings button that
  created it. `ContactPlace` is derived and disposable — that is why an empty one
  after a reinstall is a tap, not data loss, and why the local store gets no
  migration path of the kind the main store needed.

`testCloudAndLocalConfigurationsOpenAsOneContainer` and
`testContactCacheIsNotInTheCloudSchema` pin both halves. A bad split does not
fail to compile — `ModelContainer` throws at launch and the app `fatalError`s on
it — and the leak back into `cloudSchema` would be silent and permanent.

### The store lives in the App Group, and moving there is a migration

`SharedModelContainer.makeContainer()` opens the store inside the
`group.com.resistor.app` container so the widget can read it. Before the widget
it lived at SwiftData's default `Library/Application Support/default.store`, and
**pointing a configuration at a new URL does not move the file** — it opens a
new, empty one and strands the old.

**The capability is now enabled and the migration path is live** (as of
`308c8a2`, 2026-08-01). `Resistor.entitlements` declares
`group.com.resistor.app` in both Debug and Release, `ResistorWidget` declares it
too, and both provisioning profiles carry it — verified by decoding them, so the
App ID has the capability and signing isn't stripping the entitlement. That
means `storeURL` returns a real URL, and the *first launch after updating* is
the migration.

`resolvedStoreURL(groupStore:)` handles it: if the App Group has no store and a
legacy one exists, it copies the `.store` **and its `-shm`/`-wal` sidecars**
across, and opens the *legacy* store in place if the copy throws — an app that
looks empty is indistinguishable from data loss. It copies rather than moves, so
the original stays recoverable.

The `-wal` is the part that's easy to miss: it holds every transaction since the
last checkpoint, and on the real device it was 1.8 MB against a 508 KB store.
Copying the `.store` alone rewinds the app to its last checkpoint — weeks, for
this app's write pattern.

### The Production schema is a separate thing you must deploy by hand

**Debug builds talk to the Development CloudKit database; TestFlight and App
Store builds talk to Production.** They are different schemas. A model change
that "just works" on your device has not reached testers at all, and the failure
is *silent* — no crash, no error, the field simply never leaves the phone.

Two things have to be true for a field to sync in TestFlight, and the second is
the one that bites:

1. **The field must exist in the Development schema.** SwiftData materialises a
   CloudKit field lazily — the first time a record actually syncs carrying a
   value for it. An optional attribute that has never been populated on a
   dev-environment build (`intensity`, `note`) simply does not exist in the
   schema, so there is nothing to deploy. "Deploy Schema Changes" will not
   invent it. Either exercise the field on a debug build signed into iCloud, or
   add it by hand in the CloudKit Console (Development → Record Types → +).
2. **It must be deployed to Production**, via CloudKit Console → Development →
   *Deploy Schema Changes…*. Verify the confirm dialog lists exactly what you
   expect before accepting; it is the last reversible moment.

**This is one-way.** Production record types and fields can never be renamed or
removed — the same rule as the bullet above, but enforced by Apple's servers
rather than by discipline. Read the diff, then deploy.

Found on 2026-07-31 by comparing the models against the deployed schema: named
places (`CD_Place`) did not exist in Production *at all*, and `intensity`,
`note` and `sortOrder` were missing from both environments. TestFlight users'
intensity ratings, notes, named locations and habit order were device-local and
would have been lost on any reinstall or new device. All five record types now
match the models.

`CD_speedMps` (`Double`, no index) was added by hand and deployed on 2026-08-04,
in the same change that introduced `TemptationEvent.speedMps` — an optional
never populated on a dev build, so exactly the case where "Deploy Schema
Changes" has nothing to find until someone creates the field. `CD_TemptationEvent`
is 18 fields in both environments.

When adding a field by hand, take its type from a sibling SwiftData already
generated rather than guessing: `Int`/`Int?`/`Bool` → `Int(64)`, `String?` →
`String`, `Double?` → `Double`, `[String]` → `Bytes`, `Date` → `Date/Time`.
Naming is `CD_<propertyName>`. Single-field indexes are **not** required for
sync — `NSPersistentCloudKitContainer` syncs by zone change token, not by
querying data fields — so the three fields added by hand deliberately have none.
Indexes can be added later; they cannot be removed.

**Audit the schema before any release that shipped a model change.** Count
record fields in the Console against the model's stored properties, remembering
6 metadata fields and a `CD_entityName` are always present (so a 5-property
model shows 12 fields).

### Xcode Cloud builds from a shallow clone with no history

A push to `main` triggers the Xcode Cloud **Archive - iOS** workflow, which runs
`ci_scripts/ci_post_clone.sh`. That script stamps `CURRENT_PROJECT_VERSION` from
`CI_BUILD_NUMBER` and chooses the TestFlight release notes — hand-written
`TestFlight/WhatToTest.en-US.txt` if the commit being built touched it, else the
commit subject.

**The checkout is `git fetch --depth 1 origin <sha>` followed by `git checkout
<sha>`.** The repository contains that one commit and nothing else — no parents,
no branches, no history. Anything in the post-clone script that reads git history
therefore sees an empty repository and fails *silently*, because the script's job
is to pick between two acceptable outcomes rather than to succeed or fail.

This cost three attempts at one bug. Everything lands on `main` via
`gh pr merge --merge`, so the commit built is always a merge commit, and the
"was the notes file touched" check needs both `-m --first-parent` (merges need it
to emit a diff at all) *and* `git fetch --deepen 1 origin` (to have a parent to
diff against). The first two fixes were verified on a full local clone, where the
parent always exists, so both looked correct and neither was; builds kept
shipping "Merge pull request #NN from …" to testers.

**So: reproduce the clone, don't reason about it.**

```bash
git init && git remote add origin <url>
git fetch --depth 1 origin <merge sha> && git checkout <merge sha>
git diff-tree --no-commit-id --name-only -r -m --first-parent HEAD   # 0 paths = broken
```

Then verify what was actually *delivered* rather than what should have been: an
App Store Connect API key (App Manager) is on this machine, so
`GET builds/<id>/betaBuildLocalizations` reads the notes a build really shipped
with. Build 35 is the first that carried hand-written notes automatically.

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
#49), one vertical page per habit. **Release logs** — a flick and a 3s hold both write an event, matching the
phone, where the ramp changes how it feels, not whether it commits. Holding past
3s keeps buzzing until release.

**Habit switching is a vertical page swipe or a turn of the Crown**, one habit
per page, via `TabView` + `.tabViewStyle(.verticalPage)`. Its page dots are the
affordance. An earlier version put a chevron on the habit name that opened a
full-screen list, on the reasoning that the button already owned press-and-hold;
a tap to open a sheet to pick a habit is three interactions for the one thing a
wrist-fast app should make cheapest.

**The log control has to be a `Button`, not a gesture, and that is the whole
reason paging works.** A custom press gesture on the disc swallows every vertical
drag: the swipe neither turns the page *nor* is distinguishable from a lift, so
the release logs an event — verified, it does exactly that. A `Button` yields its
touch to the enclosing scroll the moment it pans and fires `action` only on a
release the scroll didn't take, which is precisely the distinction, for free. The
hold ramp rides on `ButtonStyle.Configuration.isPressed` (`PressReporting`), which
stays true for as long as the finger is down — so there is still no duration
threshold, holding past 3s still buzzes until release, and a flick and a full
hold both log. Don't reintroduce `onLongPressGesture`/`DragGesture` here, and
don't try to fix the accidental log with a distance threshold of your own; that
was tried first and the pager still never saw the drag.

Pages are in `Habit.displayOrder`, so a drag on the phone's Habits screen is the
order on the wrist. The pick lives in memory only
(`WatchLogStore.selectedHabitID`) and resets to the default habit on relaunch,
exactly like the phone's Log screen; persisting a watch-local override would make
the two devices disagree about what "the" habit is. Target resolution is pick →
first in `Habit.displayOrder`, and a pick that gets archived falls back rather than
logging to an archived habit. There is no "habit unavailable" state any more: it
covered a *stored* target that had gone stale, and with `defaultHabitId` orphaned
nothing is stored — archiving the target just promotes the next habit.

Pager pages are deliberately **not** scrollable — a vertical scroll inside a
vertically paged `TabView` fights it for the same drag and the same Crown. Only
the single-habit and no-habit states keep the `ScrollView`.

**The store refreshes on `NSPersistentStoreRemoteChange`, not just on resume.** A
reorder on the phone reaches the watch as a silent CloudKit import; without the
observer in `WatchLogStore.init` the pager keeps rendering the order it fetched
at launch, so the user reorders on the phone, looks at the wrist, and sees the
old order. `scenePhase` still refreshes on resume for imports that landed while
the app was suspended.

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

One watch-specific trap, load-bearing:

- **`CHHapticEngine` does not exist in the watchOS SDK.** The phone's continuous
  ramped pattern is approximated by a repeated discrete `WKHapticType.click` at a
  tightening gap. Don't try to port `LogViewModel`'s Core Haptics code; it cannot
  compile there.

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

The `com.resistor.app.watchkitapp` App ID needs iCloud enabled with the
`iCloud.com.resistor.app` container selected, **and** Push Notifications enabled
(for the silent CloudKit sync push) — automatic signing won't mint a profile for
an entitlement the App ID lacks, so a capability missing in the portal surfaces
as a signing failure, not a sync bug. Both are set as of 2026-07-29.

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
(`com.resistor.app.watchkitapp.ResistorWatchComplication`) embedded in
**ResistorWatch**'s PlugIns and wired by the idempotent
`scripts/add_watch_complication_target.rb`.

**The bundle ID may not end in `.complication`** — and the failure mode is
invisible locally. The Developer portal refuses to register
`com.resistor.app.watchkitapp.complication` at all ("An App ID with Identifier
… is not available"), and Xcode will not mint one either, even under
`-allowProvisioningUpdates`. Dev builds *look* fine because signing silently
falls back to the team wildcard profile (`iOS Team Provisioning Profile: *`), but
a wildcard cannot be used for App Store distribution, so every Xcode Cloud
**Archive - iOS** failed at Code Signing / "Exporting for App Store Distribution
failed" — 12 builds between 2026-07-30 and 2026-07-31, all with the archive step
itself succeeding. Bundle IDs are globally unique and permanently burned once
deleted, so the string cannot be recovered; the target was renamed to the
`.ResistorWatchComplication` suffix on 2026-07-31 and the matching App ID
registered. If you add another embedded target, confirm its bundle ID actually
registers in the portal rather than trusting a green local build.
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

Current as of 2026-08-04. Everything previously listed here (#35 icon, #37
accessibility, #47 widget, #48 haptics, #49 watch, #61/#62 Log layout, #63 icon
and colour choices, #78 place-name suggestions, #82 blank cigarette glyph) is
closed.

- #53 — Log screen: surface multiple habits (scrollable list) to use the empty space
- #77 — Calendar as a pattern facet: tag an event with the meeting it overlapped

**Two of those closed without the device check they asked for**, which is worth
knowing before trusting them:

- **#47 (widget)** was closed on the signing artifacts alone. The widget's
  runtime behaviour — configuration UI, tap-writes-one-event, debounce,
  needs-reconfiguration states, VoiceOver — has never been exercised on
  hardware.
- **#37 (accessibility)** shipped its code changes (accent picker selected
  trait, history row grouping, carousel dot labels) and closed with the
  VoiceOver / Dynamic Type walkthrough deferred to manual QA. It has not been
  run.

## v1.0 Scope — all shipped

Kept as a record of what v1 was. Nothing here is outstanding; open work lives in
the section above.

- ~~iCloud sync (CloudKit container setup + entitlements)~~ — Done: entitlements + CloudKit ModelConfiguration
- ~~Unit + UI test targets~~ — Done: ResistorTests with 11 test files
- ~~Tip jar (StoreKit 2 consumable IAPs)~~ — Done: TipJarViewModel + StoreKit config
- ~~App icon~~ — Done: `Assets.xcassets/AppIcon.appiconset/AppIcon.png`, shared by the iOS and watch targets
- ~~Dark mode audit~~ — Done: confirmation banner border, habit card contrast
- ~~Accessibility pass (VoiceOver, Dynamic Type)~~ — Code done: selected traits, event grouping, carousel labels. On-device VoiceOver/Dynamic Type walkthrough still unrun (see Open GitHub Issues)
- ~~TestFlight build~~ — Done: shipping. Release notes are hand-written per push to `main` in `TestFlight/WhatToTest.en-US.txt`

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
