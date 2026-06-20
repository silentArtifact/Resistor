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
4. Capture the outcome (resisted / gave in) of each logged temptation without adding any step to the single-tap log, so the Insights outcome breakdown reflects real behavior instead of "Not recorded".
5. Let a user log a resisted temptation for a chosen habit from the Home Screen in one tap, without opening the app, via a configurable WidgetKit widget (post-v1; see Quick-Log Widget under User Flows).

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
4. Tap (or hold) "Log Temptation".
5. Event created with timestamp, habit reference, and **outcome defaulting to `resisted`** (the common case: the user logs the moment they were tempted and overcame the urge). Logging stays a single tap — there is **no** up-front outcome decision.
6. Optional outcome/intensity/context sheets present per existing sheet-sequencing rules (these remain "Skip"-able and never block the log).
7. Confirmation banner slides down offering **"Gave in"** and **"Undo"**, auto-hides after 5s (the dwell window for an in-the-moment correction; see Flow 1a).

Edge cases:
- No habits configured: redirect to Add Habit flow
- Rapid repeated taps: each tap creates a separate event, each defaulting to `resisted`
- App from cold start vs background: always lands on Log screen

> **Default-outcome note.** The `resisted` default applies to **new** events only. Pre-existing events stored with `outcome = "unknown"` are left untouched — this is an additive behavior change, not a data migration. No field is renamed or removed; the `Outcome` enum already defines all three raw values. CloudKit-safe.

### Flow 1a: Outcome Correction (post-log)

Outcome is captured by defaulting, then **corrected** if the temptation was not resisted. Correction is never a fork in the logging path. There are two surfaces, no third.

**Surface A — in the moment (confirmation banner).**

1. User logs a temptation (Flow 1). Event saved with `outcome = "resisted"`.
2. Confirmation banner appears with "Gave in" and "Undo", auto-hiding after 5s.
3. User taps "Gave in" -> the just-logged event's `outcome` flips to `gave_in`. This is a **pure one-tap flip**: it does not re-open intensity, context, or note prompts.
4. Banner dismisses (or updates to reflect the correction) and the 5s timer is cancelled on interaction.

**Surface C — after the fact (History event detail).**

1. User opens an event from History (pushed from Insights).
2. The Outcome row in the event detail sheet is **editable** via a picker.
3. User changes the outcome; the change is saved to that event. No other fields are re-prompted.

Edge cases:
- Banner auto-dismisses before the user taps "Gave in": the event stays `resisted`; the user can still correct it later via Surface C.
- Undo (banner) deletes the event entirely, as today — distinct from "Gave in", which only edits the outcome.
- "Unknown" / "Not recorded" is **never newly settable from the banner.** Surface A offers only "Gave in" (the correction) and "Undo".

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

### Flow 3a: Time-of-Day Drill-Down

The Time of Day chart presents four coarse periods (Morning, Afternoon, Evening,
Night) as the legible overview. The user may expand one period in place to inspect
its hour-by-hour breakdown. Expansion is in-place on the Insights screen; it does
**not** push a new screen (honors the max-one-level-deep navigation rule).

1. On the Insights screen, the Time of Day chart shows the four-period bar chart.
2. User selects a period (e.g. Evening).
3. The chart expands in place to show hourly bars for only that period's hours
   (Evening = 17:00, 18:00, 19:00, 20:00).
4. User selects the same period again, or selects a collapse affordance, to return
   to the four-period overview.
5. Selecting a different period replaces the current expansion with that period's
   hours.

Period-to-hour mapping (derived from `occurredAt`, matching
`TemptationEvent.timeOfDayPeriod`):

| Period | Hours (24h) |
|--------|-------------|
| Morning | 05, 06, 07, 08, 09, 10, 11 |
| Afternoon | 12, 13, 14, 15, 16 |
| Evening | 17, 18, 19, 20 |
| Night | 21, 22, 23, 00, 01, 02, 03, 04 |

Edge cases:
- Night wraps midnight (21:00–04:00). Hourly bars for Night are ordered 21→04, not
  numerically, so the window reads as a continuous block.
- A period with zero events still expands; its hourly bars all read zero. No empty
  state is shown for an expanded period — the zero bars are the answer.
- The expansion respects the active habit and time range (7/30 days); changing
  either while expanded **recomputes** the hourly bars for the still-selected period
  and keeps it expanded (it does **not** collapse). Rationale below in
  "Filter changes while expanded."
- Hour count is keyed to the device's selected habit and range filter only — no
  cross-habit aggregation.

**Filter changes while expanded (decided).** When the user changes the habit
selector or the 7/30-day range while a period is expanded, the chart **stays
expanded on the same period and recomputes its hourly bars** — it does not collapse
to the overview. Rationale: a user inspecting "Evening" is mid-question
("when in the evening?"); switching habit or range is almost always a follow-up of
that same question ("…and for my other habit?"). Collapsing would force a re-tap to
resume the comparison and lose the user's place. The expansion is a view state keyed
to a period identity (Morning/Afternoon/Evening/Night), not to a specific dataset,
so it survives a data refresh cleanly. The bars animate their height to the new
counts (see Motion); no stale data is ever shown because the hourly query reads the
same `cachedEventsInRange` the overview does.

### Flow 4: Context Logging

Context tags are user-defined and managed via the `ContextTag` SwiftData model. Tags are displayed as selectable chips directly on the Log screen (pre-selected before logging), rather than in a post-log sheet.

1. Before logging, user optionally selects context tag chips on the Log screen.
2. On log, selected tags are attached to the event immediately.
3. Tag names stored as raw strings in `TemptationEvent.contextTags`.
4. Users create/delete tags from the Habits & Settings screen.

### Flow 5: Quick-Log Widget (Home Screen, one-tap log)

A Home Screen widget logs a resisted temptation for one bound habit in a single
tap, without launching the app. This serves the in-the-urge moment when opening
the app is itself friction (or a relapse trigger — the home screen is often the
exact surface the user is trying to resist). It is a second entry point to the
core loop (Flow 1), not a new feature surface; the event written is identical in
shape to a tap-logged event.

Each placed widget is **configured to exactly one habit** (long-press → Edit
Widget → choose habit), backed by the standard `AppIntentConfiguration` /
`WidgetConfigurationIntent` pattern with a habit-selection parameter over an
`AppEntity` of the user's non-archived habits. A user may place multiple widgets,
one per habit. This is a fixed product decision — the widget never shows a habit
picker at tap time, never logs to a "current" habit, and never shows more than
one habit.

1. User adds the Resistor widget to the Home Screen and edits it to bind a habit.
2. At rest, the widget shows the bound habit's icon, name, and today's logged
   count for that habit.
3. User taps the widget once. An interactive App Intent (iOS 17+) writes exactly
   one `TemptationEvent` for the bound habit with `outcome = "resisted"`,
   `intensity = nil`, and no context tags — the same default a single in-app tap
   produces (Flow 1, UC-O1).
4. The app is **not** launched. The widget reloads its timeline and shows the
   incremented today count.

There is **no confirmation banner, no undo, and no outcome correction in the
widget** — a widget cannot present transient UI. Correction ("Gave in") and
deletion (undo) happen later in the app: History event detail (Surface C / UC-O4)
for outcome, swipe-to-delete in History for removal. The widget is a write-only
fast path; all editing lives in the app.

Edge cases:
- **Widget not yet configured (no habit bound):** the widget renders a neutral
  unconfigured state inviting the user to edit it; a tap does **not** log
  anything (there is no habit to log to). It opens the widget's configuration or
  the app rather than writing a stray event.
- **Bound habit archived after configuration:** the widget shows an
  unavailable/needs-reconfiguration state and a tap does not log. An archived
  habit is excluded from logging just as it is excluded from the Log screen.
- **Bound habit deleted after configuration:** same as archived — the binding no
  longer resolves to a live habit; the widget shows the needs-reconfiguration
  state and a tap does not log.
- **User has zero habits:** the configuration habit list is empty; the widget
  cannot be bound and shows the unconfigured state. No habit can be created from
  the widget.
- **Shared store unavailable or not yet synced:** the widget reads/writes the
  same SwiftData + CloudKit store the app uses (via an App Group so the widget
  extension and app share the container). If the store cannot be reached, a tap
  must not silently drop the event nor write a duplicate; the widget surfaces a
  non-loggable state for that refresh rather than logging into the void. Offline
  is normal — a write made offline persists locally and syncs later, exactly as
  in-app logging does.
- **Rapid repeated taps (double-log):** each deliberate tap is a real event, as
  on the Log screen (Flow 1 edge cases). However, an accidental double-fire of a
  single tap must not create two events; the intent debounces near-simultaneous
  invocations for the same widget so one physical tap yields exactly one event.
  A user who genuinely taps twice (two urges) gets two events — that is correct.
- **Stale count between refreshes:** the at-rest count is a timeline snapshot and
  may lag reality (e.g. after an in-app log, or a log from another device syncing
  in). The count is a convenience indicator, not a source of truth; it reconciles
  on the next timeline reload (after a widget tap, or WidgetKit's normal refresh
  cadence). The count is never used to make a logging decision, so staleness is
  cosmetic, never a correctness risk.

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
- Confirmation banner overlay — offers "Gave in" and "Undo" (see Outcome Capture use cases below)

#### Outcome Capture (use cases)

Logging defaults every new event to `outcome = "resisted"`, so the single-tap log
records a usable outcome with zero extra steps. The only departure from `resisted`
is an explicit, optional correction. This requires **no schema change**: the
`Outcome` enum already defines `resisted` / `gaveIn` / `unknown`, and both Insights
and History already display outcome. Today nothing ever writes anything but
`unknown`; these use cases make the write happen.

**UC-O1 — Single-tap log records "resisted" by default.**
As someone who just resisted an urge, I want logging to be one tap so that I capture
the moment without friction, and have its outcome recorded as resisted.
Acceptance criteria:
- Tapping (or holding) "Log Temptation" creates exactly one `TemptationEvent` whose
  `outcome` is `"resisted"`.
- No outcome decision is presented before or during the log; the log completes in a
  single tap.
- The event appears in Insights' outcome breakdown under "Resisted", not "Not
  recorded".
- Pre-existing events with `outcome = "unknown"` are unchanged after this behavior
  ships.

**UC-O2 — Correct to "gave in" from the confirmation banner.**
As someone who logged but actually gave in, I want a one-tap correction in the moment
so that the record is accurate without redoing the log.
Acceptance criteria:
- The confirmation banner shows a "Gave in" control alongside "Undo".
- Tapping "Gave in" sets the just-logged event's `outcome` to `"gave_in"` and persists
  it.
- The correction does **not** open or re-open the intensity, context, or note prompts.
- The banner remains visible long enough to act: it auto-dismisses after **5 seconds**
  (up from 4s). Any banner interaction cancels the auto-dismiss timer.
- "Gave in" edits the existing event; it never creates a second event and never deletes
  the event.
- The banner offers no path to set "Not recorded" / "unknown".

**UC-O3 — Undo remains distinct from "Gave in".**
As someone who logged by mistake, I want Undo to remove the event entirely, separate
from correcting its outcome.
Acceptance criteria:
- "Undo" deletes the just-logged event (existing behavior, unchanged).
- "Undo" and "Gave in" are visually and behaviorally distinct; one deletes, the other
  edits.

See "Outcome Correction (use cases)" under History for the after-the-fact surface
(UC-O4).

#### Outcome Capture (interaction and visual spec)

This is the build-ready spec for **Surface A** (the confirmation banner). It refines
the `confirmationBanner(vm:)` function in `Views/LogView.swift:455` and the
`triggerConfirmation()` / new flip method on `LogViewModel`. No new screen, no
navigation push, no new data model. The banner is still an `.overlay(alignment: .top)`
with the existing slide+fade transition; only its right-side content and the dwell
logic change.

##### Layout (both states)

The banner is a single `HStack` inside the existing rounded card (12pt radius,
`Color(.systemBackground)` fill, `Color(.separator)` 0.5pt stroke, shadow,
24pt outer horizontal padding, 16pt inner horizontal / 12pt vertical padding). The
HStack has three regions, left to right:

1. **Status group (leading).** `Image(systemName:)` + `Text` in an `HStack(spacing: 8)`,
   treated as one accessibility element (`.accessibilityElement(children: .combine)`).
   Icon and label are **state-driven** (see the two states below). This group never
   moves; only its glyph, tint, and word change when the outcome flips.
2. **`Spacer()`** — pushes the controls to the trailing edge.
3. **Controls group (trailing).** An `HStack(spacing: 0)` holding the correction
   control, a hairline divider, and the destructive control. The two controls are
   deliberately separated so "edit" and "delete" are never mistaken for each other:

   | Slot | Control | Type | Treatment |
   |------|---------|------|-----------|
   | First (inner) | **Gave in** | `Button` with text `"Gave in"` | `.font(.subheadline.weight(.semibold))`, `.foregroundStyle(.orange)` (the `gaveIn` semantic color — signals what tapping produces, and the only color cue distinguishing it from Undo). |
   | Divider | — | `Divider()` in a fixed `.frame(height: 20)` | A vertical hairline (`Color(.separator)`) between the two controls so they read as two distinct targets, not one run of text. Hidden in the post-flip state (see below). |
   | Second (outer) | **Undo** | `Button` with text `"Undo"` | `.font(.subheadline)` (regular weight, no color = `.secondary`). Lighter weight + neutral color makes it visually subordinate to the colored, semibold correction control. |

   Each `Button` gets `.padding(.horizontal, 12).padding(.vertical, 11)` and
   `.contentShape(Rectangle())` so its tappable area is ≥44pt tall and comfortably
   wide; the visible text is smaller but the hit target is full-height. Do **not** put
   `.padding` on the labels alone — pad the button so the hit target, not just the
   glyph, is large. The two buttons sit flush against the divider; the 12pt inner
   padding on each gives ~24pt of clear space straddling the divider, well above the
   8pt minimum inter-target gap.

Ordering rationale: **Gave in is inner (closer to the status word), Undo is outer
(trailing edge).** "Gave in" is the expected, frequent correction and reads as a
continuation of the status ("Logged → actually, Gave in"); Undo is the rare,
destructive escape hatch and conventionally lives at the far trailing edge. This also
keeps the destructive action furthest from the thumb's resting sweep after a log,
reducing accidental deletes.

##### State 1 — Just logged (default, outcome = `resisted`)

- Status icon: `checkmark.circle.fill`, `.foregroundStyle(.green)`.
- Status label: `"Logged"`, `.fontWeight(.medium)`, `.foregroundStyle(.primary)`.
- Controls: **Gave in** (orange, semibold) · divider · **Undo** (secondary). Both
  visible and enabled.
- Dwell: auto-dismiss after **5s** (see Timer below).

Note the status word is `"Logged"`, not `"Resisted"` — the banner confirms the *log
action*, and `resisted` is the implicit default. Surfacing "Resisted" here would
imply the user made an outcome choice they did not make, and would make the "Gave in"
control read as contradicting an explicit selection. "Logged" stays neutral; "Gave
in" reads as supplying the outcome, not overriding one.

##### State 2 — After "Gave in" tapped (outcome flipped to `gave_in`)

A single tap on **Gave in** transitions the banner in place (it does **not** dismiss
immediately — the user needs to see the correction registered, and may still want
Undo):

- Status icon swaps to `xmark.circle.fill`, `.foregroundStyle(.orange)`.
- Status label swaps to `"Gave In"` (the canonical outcome display name, title-cased —
  distinct from the lowercase **"Gave in"** button label, which is an action). Use
  `.fontWeight(.medium)`, `.foregroundStyle(.primary)`.
- The **Gave in button is removed**, and the **divider is removed** with it. Tapping
  it again is meaningless (already `gave_in`; the banner offers no path back to
  `resisted` or to `unknown`), so leaving it would be a dead control. Only **Undo**
  remains on the right.
- Undo stays in its same trailing position and behavior (deletes the event). It does
  not move when Gave in is removed — the Spacer absorbs the freed width, so Undo's hit
  target stays anchored at the trailing edge and the user's thumb target is stable.
- Dwell: the 5s auto-dismiss timer **restarts** on the flip (call
  `triggerConfirmation()`'s timer-arming logic again, or a shared `armDismissTimer()`),
  giving the user a fresh 5s to read the corrected state and optionally Undo. This is
  the one case where interaction re-arms rather than only cancels — because the banner
  now shows new information the user must have time to verify.

This is a one-way transition within a single banner presentation: there is no "flip
back to Resisted" control. If the user got it wrong, Undo (delete) is available, or
they can re-log; after dismissal, History (Surface C) is the correction path.

##### Timer behavior (consolidated)

- On log: arm a cancellable 5s `DispatchWorkItem` (replace the literal `4.0` in
  `LogViewModel.triggerConfirmation()` with `5.0`).
- On **Undo** tap: cancel the timer, dismiss the banner immediately, delete the event
  (existing `undoLastLog()` behavior, unchanged except it already cancels the work
  item).
- On **Gave in** tap: cancel the existing timer, perform the outcome flip + save, then
  re-arm a fresh 5s timer (banner stays visible in State 2).
- Any tap on the banner card that is not on a control does nothing (the banner is not
  a button); only the two explicit controls and the auto-dismiss act.

##### Colors and dark mode

- Card fill `Color(.systemBackground)`, stroke `Color(.separator)` — unchanged;
  adaptive, so dark mode is automatic.
- Status and control tints use the **outcome semantic colors** (`.green` for the
  logged/resisted check, `.orange` for gave-in), never the user accent color — outcome
  color is semantic to outcome, not to theme. These system colors are vivid in both
  appearances.
- The vertical `Divider()` uses `Color(.separator)` (do **not** use a hardcoded
  translucent gray — on the pure-black dark canvas a low-opacity gray can vanish, the
  same failure the context chips hit; `.separator` is the adaptive, always-visible
  choice).
- Undo's `.secondary` foreground is adaptive and legible on the system-background card
  in both modes.

##### Motion (reduceMotion-gated)

- Banner appear/dismiss: unchanged — `.move(edge: .top).combined(with: .opacity)`,
  0.3s easeInOut, already gated via `.animation(reduceMotion ? .none : .easeInOut(...))`.
- State 1 → State 2 flip: wrap the status/control mutation in
  `withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.2))`. The icon and
  label cross-fade (apply `.contentTransition(.symbolEffect(.replace))` to the status
  `Image` so the checkmark→xmark swap is a glyph morph, and `.transition(.opacity)`/
  `.id(outcome)` on the label so the word cross-fades). The Gave in button + divider
  removal animates as `.opacity` (and may collapse width via the layout). With Reduce
  Motion on, the swap is instant: no symbol effect, no cross-fade, no width-collapse
  animation — mutate state outside `withAnimation`.
- No haptic on the flip. Per the haptic policy, the only haptic is the log tap itself;
  secondary actions (Undo, Gave in) get **no** haptic.

See "Outcome Correction (use cases)" under History for the after-the-fact surface
(UC-O4).

### S2: Insights Screen

- Habit selector pills (horizontal scroll)
- Summary stats: this period vs previous, peak time, peak day
- Outcome breakdown (stacked bar + resisted %)
- Daily trend chart (bar chart)
- Time of day chart (bar chart) — four periods; a selected period expands in place
  to hourly bars (see Time-of-Day Drill-Down below)
- Day of week chart (bar chart)
- "View History" navigation link

#### Time-of-Day Drill-Down (use cases)

The four-period Time of Day chart is the default, legible overview. Event data is
sparse (typically tens of events per user), so 24 hourly bars up front would read
as noise. A user who notices a spike in one period can expand that period to hourly
detail on demand — fine resolution appears only where the user signaled interest.

This requires **no data-model or schema change**. Hourly granularity is derived
from the existing `TemptationEvent.occurredAt` timestamp (`hourOfDay` /
`timeOfDayPeriod` already exist; `InsightsViewModel.hourlyDistribution()` already
returns per-hour counts). No new field, no CloudKit migration.

**UC-1 — Expand a period to hourly detail.**
As someone reviewing patterns, I want to expand a time period into its hours so
that I can see which hour within a spike is driving it.
Acceptance criteria:
- The four-period chart is the default state on entering Insights.
- Selecting a period replaces that period's single bar with one bar per hour in
  that period's window (per the mapping in Flow 3a).
- The hourly bars are labeled by hour and cover exactly the selected period's hours
  — no more, no fewer.
- Counts in the hourly bars sum to the count shown for that period in the overview
  (for the same habit and time range).

**UC-2 — Collapse back to the overview.**
As someone reviewing patterns, I want to return to the four-period overview so that
I can compare periods again after inspecting one.
Acceptance criteria:
- A collapse affordance returns the chart to the four-period overview.
- The same chart remains on the Insights screen throughout; no navigation push
  occurs, and the back/tab state is unchanged.

**UC-3 — Switch the inspected period.**
As someone reviewing patterns, I want to expand a different period without first
collapsing so that comparison is quick.
Acceptance criteria:
- Selecting a different period while one is expanded replaces the hourly bars with
  the newly selected period's hours.
- At most one period is expanded at a time.

**UC-4 — Drill-down reflects active filters.**
As someone reviewing patterns, I want the hourly view to honor my selected habit
and time range so that the detail matches the overview it came from.
Acceptance criteria:
- Hourly bars reflect only the currently selected habit and the active 7/30-day
  range.
- Changing the habit selector or time range while a period is expanded recomputes
  the hourly bars for the still-selected period (or collapses to overview — a
  ux-designer decision; either is acceptable so long as no stale data is shown).

**UC-5 — Sparse / empty data.**
As someone with few logged events, I want the drill-down to behave predictably so
that an empty hour isn't mistaken for a bug.
Acceptance criteria:
- A period with zero events still expands; all its hourly bars read zero.
- The Night period's hourly bars are ordered 21:00 → 04:00 (wrapping midnight), not
  numerically, so the window reads as one continuous block.
- No separate empty state is shown for an expanded period; zero bars are the
  result.

#### Time-of-Day Drill-Down (interaction and visual spec)

This is the build-ready spec for the drill-down. It refines the `timeOfDayChart`
function inside the existing `SectionCard(title: "Time of Day")` in
`Views/InsightsView.swift`. No new screen, no navigation push, no new data model.

##### Placement and layout

Everything lives inside the existing `SectionCard`. The card grows/shrinks in height
as the chart swaps; the surrounding Insights `ScrollView` reflows naturally.

The card has two stacked regions inside its existing 16pt-spaced `VStack`:

1. **Header row** (replaces the plain `SectionCard` title for this one card). The
   card is built with `SectionCard(title:)` as today, but uses the card's
   `accessory` slot for a trailing collapse control when expanded:
   - Title text: `"Time of Day"` in the overview state. When a period is expanded,
     the title becomes `"Time of Day · Evening"` (middot-joined,
     `Text("Time of Day") + Text(" · ") + Text(period)`), where the period segment
     is `.foregroundStyle(.secondary)`. This anchors the user without a separate
     breadcrumb row. The title uses the existing `.headline` style and is allowed to
     wrap to two lines at large Dynamic Type (no `lineLimit(1)`).
   - Accessory (expanded state only): a **collapse control** — an SF Symbol
     `chevron.up.circle` button, `.font(.body)`, `.foregroundStyle(.secondary)`,
     min 44×44pt tap target (pad to reach it). In the overview state the accessory
     slot is empty.
2. **Chart region** — the `Chart` itself, 150pt tall in both states (unchanged from
   today, so the card does not jump in height between states; only the title and
   x-axis change).

##### States

| State | Chart content | Header | Notes |
|-------|---------------|--------|-------|
| **Overview** (default) | 4 `BarMark`s: Morning, Afternoon, Evening, Night, habit color | Title `"Time of Day"`, no accessory | Identical to today's chart plus tap affordance |
| **Expanded** (one period) | N `BarMark`s, one per hour in the period's window (4 Evening / 5 Afternoon / 7 Morning / 8 Night), habit color | Title `"Time of Day · {Period}"` + collapse chevron | Replaces the 4-bar overview entirely |
| **Expanded, zero-data** | Same N hourly bars, all at height 0 (flat baseline, axis labels visible) | Same as Expanded | No separate empty copy. The flat axis is the answer. The card is **not** rendered at all when the whole habit/range `!vm.hasData` — that case is already handled upstream by `noDataView`, so the drill-down never shows for a habit with zero total events. |
| **Range/habit change while expanded** | Bars animate height to recomputed counts for the same period | Unchanged (same period title) | Stays expanded; see Flow 3a "Filter changes while expanded" |
| **Loading** | No dedicated spinner | — | Insights recompute is synchronous and instant from `cachedEventsInRange`; there is no async loading state for this card. The whole Insights screen already gates on `viewModel == nil` with a `ProgressView` upstream. |

There is intentionally **no disabled state** and **no per-bar selected state** in the
overview — every period bar is always tappable, including zero-count ones (a
zero-count period expands to all-zero hourly bars, consistent with UC-5).

##### Interaction model (gestures)

- **Tap target = the whole period bar (and its full-height column), not a chevron.**
  Implement with Swift Charts `.chartOverlay` + a `chartProxy` hit test that maps the
  tap x-location to the nearest period via `proxy.value(atX:)`. The tappable region
  is the full chart-plot height for that period's x-band, so a zero-count bar (which
  has near-zero drawn height) is still easily tappable. No visible chevron on
  individual bars — keeps the overview clean and legible per the "4-bar overview is
  the legible default" goal.
- **Tap a period (overview → expanded):** sets `expandedPeriod = .evening`. Chart
  swaps to that period's hourly bars.
- **Tap the same period again is NOT the collapse path.** Once expanded, the
  individual hourly bars are not themselves a collapse target (tapping an hourly bar
  does nothing — hourly is the resolution floor this pass). Collapse is an **explicit
  control**: the `chevron.up.circle` accessory in the header. This avoids the
  ambiguity of "did I tap the same period or a different one" when the overview bars
  are no longer on screen.
- **Tap a different period to swap:** only reachable from the overview. Because the
  overview bars are replaced when expanded, swapping is a two-step gesture: collapse
  (chevron) → tap the other period. This is deliberate: at most one period is
  expanded, and the overview is the comparison surface. (A future pass may add a
  compact period segmented control above the hourly chart to allow direct swap
  without collapsing — explicitly out of scope here.)
- State model: a single `@State private var expandedPeriod: TimeOfDayPeriod?` on
  `InsightsView` (nil = overview). The implementer defines a small
  `enum TimeOfDayPeriod: String { case morning, afternoon, evening, night }` with a
  `displayName` and an ordered `hours: [Int]` array (Night = `[21,22,23,0,1,2,3,4]`,
  NOT numeric sort).

##### Hourly data source

The implementer adds a windowed variant to `InsightsViewModel`, e.g.
`hourlyDistribution(for period: TimeOfDayPeriod) -> [(hour: Int, count: Int)]`,
returning one entry per hour in `period.hours`, **in that array's order** (so Night
preserves 21→04). It reads the same `cachedEventsInRange` the overview uses, so it
automatically honors the active habit and 7/30-day range. The per-hour counts must
sum to that period's overview count (UC-1 acceptance criterion).

##### Hour-axis labeling

The x value for each `BarMark` is the **hour label string** (a plottable category),
ordered by the `period.hours` array, so Night renders left-to-right 21,22,23,0,…,4
without Charts re-sorting numerically. Use a `.value("Hour", label)` nominal axis.

Label format — compact, no AM/PM clutter, fits 8 bars on phone width:

- Visible axis labels use a **24-hour two-digit-free short form**: the bare hour
  number, e.g. `5, 6, 7, …` for Morning and `21, 22, 23, 0, 1, 2, 3, 4` for Night.
  No colons, no ":00", no "h". This is the most compact unambiguous label and matches
  the clinical tone.
- To prevent crowding at 8 bars (Night) on a narrow phone or at large Dynamic Type,
  use `.chartXAxis { AxisMarks { ... AxisValueLabel().font(.caption2) } }` and allow
  Charts to thin labels if needed. Do **not** rotate labels. If thinning still
  crowds, label every other bar — but all 8 bars always render; only their text
  labels may thin.
- The accessibility (VoiceOver) label is the **full, unambiguous** form (12-hour with
  AM/PM) — see Accessibility below — so the terse visual labels never cost clarity
  for assistive tech.

##### Color and highlight

- Hourly bars use the **selected habit color**, identical to the overview bars:
  `Color(hex: vm.selectedHabit?.colorHex ?? "#007AFF") ?? .blue`. Never a hardcoded
  brand color. Dark mode is automatic because the surface is
  `secondarySystemBackground` and the bar is the user's hex.
- No separate "selected bar" highlight is needed because the overview bars are
  replaced, not annotated. The only persistent indicator that you are drilled in is
  the title suffix (`· Evening`) plus the collapse chevron.

##### Exact copy

| Element | String |
|---------|--------|
| Card title (overview) | `Time of Day` |
| Card title (expanded) | `Time of Day · Morning` / `· Afternoon` / `· Evening` / `· Night` |
| Period display names | `Morning`, `Afternoon`, `Evening`, `Night` (match existing) |
| Hourly axis labels | bare hour numbers: `5`, `6` … `21`, `22`, `23`, `0`, `1` … `4` |
| Collapse control | no text label; SF Symbol `chevron.up.circle` only |

No empty-state copy, no "tap to expand" hint text (the bars are the affordance; a hint
line would clutter the clinical layout). No motivational or emotional strings. No
emoji.

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
- Tap for detail sheet — outcome is **editable**; all other fields read-only

#### Outcome Correction (use cases)

**UC-O4 — Edit outcome after the fact in History.**
As someone reviewing past events, I want to change an event's outcome so that a record
I logged earlier (or mis-recorded) can be made accurate later.
Acceptance criteria:
- The Outcome row in the event detail sheet is editable (a picker), replacing today's
  read-only row.
- Changing the outcome persists to that specific event and is reflected in Insights.
- Editing outcome does **not** re-prompt or alter intensity, context tags, note, time,
  or location.
- Selectable values: "Resisted" and "Gave In" are always available. **"Not recorded"
  appears as a selectable option only when the event's current outcome is already
  `unknown`** (a legacy event); once the user moves such an event to Resisted or Gave
  In, "Not recorded" is no longer offered for that event. For events that already have
  a recorded outcome, only "Resisted" and "Gave In" are offered.
- Rationale for the conditional "Not recorded": `unknown` is a legacy state for data
  created before outcome capture existed. We let users keep an old event as "Not
  recorded" or resolve it, but we never invite a user to *downgrade* a recorded outcome
  back to "Not recorded" — that would manufacture ambiguity rather than record reality.

#### Outcome Correction (interaction and visual spec)

This is the build-ready spec for **Surface C** (the History event-detail picker). It
refines the read-only Outcome `Section` in `EventDetailSheet`
(`Views/HistoryView.swift:247`). The sheet stays a `.medium`-detent `List`; only the
Outcome section becomes editable. No other field changes — intensity, context, time,
location, note rows are untouched.

##### Picker style

Use an **inline `Picker` rendered as menu-style** inside the existing
`Section("Outcome")` — i.e. a single `List` row showing the current outcome with a
trailing chevron/checkmark menu, consistent with iOS Settings-style editable rows and
with the plain-`List` structure of this sheet. Concretely:

```
Section("Outcome") {
    Picker(selection: $outcome) {
        // one row per selectable option (see conditional rule)
    } label: {
        Label(currentDisplayName, systemImage: currentIconName)   // leading icon tinted to outcome color
    }
    .pickerStyle(.menu)
}
```

Rationale for `.menu` over `.segmented` inline: the option set is **conditional**
(2 or 3 options), and a segmented control with a sometimes-present third segment reads
as unstable. A menu also keeps the collapsed row visually identical to the other
read-only rows in the sheet (icon + value), so the screen does not gain visual weight;
the editability is revealed on tap. The selected value shows the **outcome's semantic
icon and color** in the collapsed row (`event.outcomeEnum.iconName` /
`event.outcomeEnum.color`), preserving the existing row's appearance.

##### Options and the conditional "Not recorded" rule

The picker's option rows are built from a computed list, each row a
`Label(outcome.displayName, systemImage: outcome.iconName)` tagged with the `Outcome`
value, icon tinted to `outcome.color`:

- **"Resisted"** (`checkmark.circle.fill`, green) — always present.
- **"Gave In"** (`xmark.circle.fill`, orange) — always present.
- **"Not recorded"** (`questionmark.circle.fill`, gray) — present **only when
  `event.outcomeEnum == .unknown`** at the time the sheet is shown. Once the user picks
  Resisted or Gave In, persisting removes `unknown` from the option set; reopening the
  picker (or sheet) shows only the two recorded options. A recorded outcome can never
  be downgraded to `unknown`.

Implementation note: compute the options once per render from the event's current
persisted outcome, e.g. `var options: [Outcome] { event.outcomeEnum == .unknown ? [.resisted, .gaveIn, .unknown] : [.resisted, .gaveIn] }`. The currently-selected value is
always in the list (an `unknown` event includes `unknown`; a recorded event's value is
`resisted`/`gaveIn`, both always present), so the menu always has a valid current
selection — no SwiftUI "selection not in options" warning.

##### Selected / unselected appearance

- **Collapsed row (menu closed):** leading `Label` with the current outcome's icon
  (tinted to its semantic color) + display name in `.primary`; trailing menu indicator
  is the system default (up/down chevrons). Matches the other detail rows' icon+text
  rhythm.
- **Open menu rows:** each option shows its icon + name; the system places a checkmark
  on the current selection (standard `.menu` behavior). Icons are tinted to their
  outcome colors so the three options are distinguishable by icon+color, not text
  alone (satisfies the "outcome colors paired with icons, never color alone" rule).
- There is **no separate disabled state**: an option that is not offered is simply
  absent from the list (not shown greyed). The only conditional is presence/absence of
  "Not recorded".

##### Persistence

On selection change, write `event.outcome = newValue.rawValue` and
`try? modelContext.save()` (matching the file's existing
`try? modelContext.save()` + print error policy). The change is immediate, no confirm
step, and is reflected in Insights on next recompute. Editing outcome does not touch
`intensity`, `contextTags`, `note`, `occurredAt`, or location.

##### Dark mode

All colors here are semantic (outcome system colors + `.primary`) and the sheet is a
standard `List`, so dark mode is automatic. No translucent fills that could disappear
on the black canvas.

### W1: Quick-Log Widget (Home Screen)

A WidgetKit Home Screen widget that logs a resisted temptation for one bound
habit in a single tap, without opening the app. It is a second entry point to the
core loop (Flow 1 / Flow 5), built on system frameworks only (WidgetKit +
AppIntents — both first-party, so the no-third-party-dependency rule holds). The
widget extension and the app share one SwiftData + CloudKit store via an App
Group; the widget writes the same `TemptationEvent` an in-app tap writes.

Fixed product decisions (not open for design re-litigation):
- **Configurable, single-habit binding.** Each placed widget is locked to one
  user-chosen habit via `AppIntentConfiguration` / `WidgetConfigurationIntent`,
  with a habit-selection parameter backed by an `AppEntity` over the user's
  non-archived habits. Multiple widgets, one per habit, are allowed.
- **One tap = one resisted log.** A single tap fires an interactive App Intent
  that writes one `TemptationEvent`: `outcome = "resisted"`, `intensity = nil`,
  no context tags. No habit picker at tap time, no app launch.
- **At-rest content:** bound habit's icon, name, and today's logged count.
- **No confirmation, no undo, no correction in the widget.** Correction and
  deletion happen in the app (History / UC-O4). After a tap the widget reloads
  its timeline to show the updated count.

#### Quick-Log Widget (use cases)

The widget exists to remove the last bit of friction from logging in the urge
moment: even opening the app can be a deterrent, and the Home Screen is often the
very surface the user is trying to resist. This requires **no schema change** —
the event written is identical to an in-app tap log, which the data model already
supports. The only new infrastructure is an App Group so the widget extension and
app share the store, plus a WidgetKit/AppIntents target.

**UC-W1 — One-tap log from the Home Screen.**
As someone in the urge moment, I want to log that I resisted a temptation for my
habit straight from the Home Screen so that I capture it without opening the app.
Acceptance criteria:
- Tapping a configured widget writes exactly one `TemptationEvent` bound to the
  widget's habit, with `outcome = "resisted"`, `intensity = nil`, and an empty
  context-tag array.
- The app is not launched by the tap.
- The new event is identical in shape to a single in-app tap log and appears in
  Insights and History for that habit like any other event.
- After the tap, the widget's displayed today count for that habit increments on
  the next timeline reload.

**UC-W2 — Bind the widget to a habit.**
As someone setting up the widget, I want to choose which habit it logs to so that
each widget tracks the habit I intend.
Acceptance criteria:
- Long-press → Edit Widget presents a habit-selection parameter listing only the
  user's non-archived habits, by name (and icon/color where the system allows).
- Selecting a habit binds the widget to it; the at-rest widget then shows that
  habit's icon, name, and today's count.
- Multiple placed widgets can each be bound to a different habit independently.
- Archived habits do not appear in the selection list.

**UC-W3 — At-rest display.**
As someone glancing at the Home Screen, I want the widget to show which habit it
logs and how many times I've logged today so that the tap target is unambiguous.
Acceptance criteria:
- A configured widget shows the bound habit's name, icon, and today's logged
  count for that habit.
- The displayed count reflects events with `occurredAt` on the current day for
  that habit (matching the in-app "Today: {n} logged" definition).
- The count may lag the live store between refreshes; it reconciles on the next
  timeline reload and is never used to decide whether to log.

**UC-W4 — Unconfigured / unavailable widget does not log.**
As someone who hasn't finished setting up the widget (or whose bound habit is
gone), I want a tap to never create a stray or misattributed event so that my data
stays trustworthy.
Acceptance criteria:
- A widget with no habit bound shows an unconfigured state; a tap does not write
  an event (it opens configuration or the app instead).
- If the bound habit was archived or deleted after configuration, the widget
  shows a needs-reconfiguration state and a tap does not write an event.
- When the user has zero non-archived habits, the configuration list is empty and
  the widget cannot be bound; no habit can be created from the widget.

**UC-W5 — One tap yields exactly one event.**
As someone tapping quickly, I want a single physical tap to log exactly once so
that I don't get phantom double-counts.
Acceptance criteria:
- A single tap creates exactly one event; an accidental double-fire of that one
  tap is debounced so it does not create two events.
- Two deliberate, separate taps create two events (two urges = two events),
  consistent with the Log screen's rapid-tap behavior.
- If the shared store is unreachable on a given refresh, a tap does not silently
  drop the event nor write a duplicate; the widget surfaces a non-loggable state
  for that refresh. An offline write persists locally and syncs later, as in-app
  logging does.

#### Quick-Log Widget (exact copy)

All strings clinical, no motivational/emotional language, no emoji, honoring the
Forbidden Language table. These are the **final strings** the implementer ships; the
state-by-state placement is specified under "interaction and visual spec" below.

| Element | Final string |
|---------|--------------|
| At-rest count (medium) | `Today: {n} logged` (the full Log-screen form; medium has the width for it) |
| At-rest count (small) | `{n} today` (space-constrained equivalent; small cannot fit the long form at large Dynamic Type without truncating the habit name) |
| Habit name | The habit's own name, verbatim; never decorated, never prefixed |
| Unconfigured state — primary | `No habit selected` |
| Unconfigured state — secondary | `Choose a habit in Edit Widget` |
| Needs-reconfiguration — primary | `Habit unavailable` |
| Needs-reconfiguration — secondary | `Edit widget to choose another` |
| Store-unavailable — primary | `Count unavailable` |
| Store-unavailable — secondary (medium only) | `Tap to log; count updates later` |
| Tap affordance | No "tap to log" hint text in the at-rest configured state; the habit card is the affordance (consistent with the in-app no-hint convention) |
| Forbidden | No "Great job", "Streak", "You resisted!", success/celebration copy, or emoji anywhere in the widget |

Copy notes:
- The small size drops every secondary line in the error/setup states — it has room
  for one short line only. The primary string alone must be self-explanatory, which is
  why each primary (`No habit selected`, `Habit unavailable`, `Count unavailable`)
  stands on its own.
- `Tap to log; count updates later` is the **one place** a "tap to log" phrase is
  allowed, and only in the store-unavailable medium state: there, tapping still works
  (the write enqueues), but the count cannot be shown, so the line explains why the
  number is missing rather than hinting at the affordance. It is a status explanation,
  not a motivational hint. It is omitted on small for space.

#### Quick-Log Widget (interaction and visual spec)

Build-ready spec for the W1 widget. New WidgetKit extension target + `AppIntents`;
no new screen in the main app, no navigation push, no data-model or schema change.
The widget reuses the existing habit color system (`Color(hex:)`) and semantic colors
only. Everything below is sized for the two in-scope families: **systemSmall** and
**systemMedium**.

##### Rendering constraints the implementer must respect

These are WidgetKit/iOS facts that shape the design — they are not negotiable and the
layout above is built around them:

- **No scrolling, no live state, no gestures.** A Home Screen widget is a static
  timeline snapshot. The only interactivity available (iOS 17+) is
  `Button(intent:)` / `Toggle(intent:)` with an `AppIntent`. There is **no** tap
  hint animation, no press-state ripple beyond the system's built-in button dim, and
  no hold/long-press logging (the in-app hold-to-log effect does **not** port to the
  widget — a tap is the only gesture).
- **The whole widget is the button.** Wrap the entire content in a single
  `Button(intent: LogResistedIntent(habit: …))` so the full card is the tap target
  (matches "the habit card is the affordance"). Use `.buttonStyle(.plain)` so the
  system does not draw its own chrome over the custom layout; the system still applies
  a subtle dim on touch-down, which is the only press feedback (acceptable, and the
  only feedback a widget can give — see "tap affordance treatment" below).
- **No haptics.** Widget-extension code cannot fire `UIImpactFeedbackGenerator` or
  Core Haptics. The widget's log tap therefore has **no** haptic, unlike the in-app
  tap. This is a platform limit, not a design choice; do not attempt a workaround.
- **No confirmation, no undo, no banner.** A widget cannot present transient UI
  (already fixed). The only post-tap feedback is the count changing on the next
  timeline reload (see "after a tap").
- **Configuration is a system sheet, not our UI.** The habit picker is the system's
  Edit Widget sheet, driven by the `WidgetConfigurationIntent`'s habit parameter
  (`@Parameter` over an `AppEntity` whose `suggestedEntities()` returns non-archived
  habits, by name + symbol). We do not lay this out; we only supply the entity list
  and display strings. Archived habits are excluded by filtering at
  `suggestedEntities()`.
- **`containerBackground` is required (iOS 17+).** Use
  `.containerBackground(for: .widget) { … }` for the widget background; do not paint a
  full-bleed color manually. The background is `Color(.systemBackground)` tinted with
  the habit color at low opacity (see Colors).
- **Margins.** Use the system default content margins (do not zero them out). Treat the
  usable content inset as the system-provided `widgetContentMargins`; all spacing
  values below are *inside* that inset.

##### Tap affordance treatment (no hint text allowed)

There is no "tap to log" label and no animated cue. The affordance is conveyed
structurally, the same way the in-app habit card conveys it:

- The configured widget reads as a single, solid, color-tinted card — a deliberate
  filled surface, not flat text on the wallpaper. A filled tappable card is the
  established Resistor affordance language (the Log-screen habit card).
- The habit icon is rendered at full habit-color saturation inside a filled
  circular/rounded token, which reads as a "button face."
- The system's touch-down dim (from `Button`) is the only motion. No custom pulse,
  glow, or scale — those would violate the clinical tone and cannot be driven in a
  widget anyway.
- In the **non-loggable** states (unconfigured, needs-reconfiguration), the card is
  intentionally **de-emphasized** (muted/secondary treatment, no habit-color fill) so
  it does *not* read as a primed log button — a user must not feel invited to tap a
  surface that won't log. The visual difference between "filled habit-color card =
  loggable" and "flat secondary card = not loggable" is the affordance signal.

##### State (a): Configured / at-rest — small (systemSmall)

A vertical stack, top-aligned content with the count pinned low, inside the content
margin:

```
┌─────────────────────────┐
│ ◉  (icon token)         │   ← icon token top-leading
│                         │
│ Sugar                   │   ← habit name
│                         │
│ 3 today                 │   ← count, bottom-leading
└─────────────────────────┘
```

- Layout: `VStack(alignment: .leading, spacing: 0)` with a `Spacer()` between the
  name block and the count so the count sits at the bottom-leading corner.
- **Icon token (top-leading):** `Image(systemName: habit.iconName ?? "circle.fill")`
  in a 28pt font, `.foregroundStyle(habitColor)`, inside a rounded square token
  44×44pt, fill `habitColor.opacity(0.18)`, corner radius 12pt. The token is the
  visual anchor and reads as the button face.
- **Habit name:** `Text(habit.name)`, `.font(.headline)`, `.fontWeight(.semibold)`,
  `.foregroundStyle(.primary)`, `.lineLimit(2)`, `.minimumScaleFactor(0.8)`. Two lines
  max; long names wrap then scale slightly rather than truncate hard. 8pt top spacing
  below the icon token.
- **Count:** `Text("\(n) today")`, `.font(.title2)`, `.fontWeight(.bold)`,
  `.foregroundStyle(.primary)` for the number; `.foregroundStyle(.secondary)` for the
  word `today`. Build as `Text("\(n) ").fontWeight(.bold) + Text("today").font(.subheadline).foregroundStyle(.secondary)`
  so the number dominates and the unit is quiet. Pinned bottom-leading.
- Background: `.containerBackground(for: .widget)` = `Color(.systemBackground)` with an
  `habitColor.opacity(0.12)` overlay fill (the 15%-ish habit tint, matching the
  in-app card language; 12% reads correctly over both system backgrounds).
- The entire card is one `Button(intent: LogResistedIntent(habitID:))`,
  `.buttonStyle(.plain)`.

##### State (a): Configured / at-rest — medium (systemMedium)

A horizontal split: icon + name on the leading 60%, the count as a large numeral
trailing, vertically centered.

```
┌──────────────────────────────────────────────┐
│  ◉   Sugar                            3        │
│       Today: 3 logged                          │
└──────────────────────────────────────────────┘
```

- Layout: `HStack(spacing: 16)` → [leading `VStack`] · `Spacer()` · [trailing big
  numeral].
- **Icon token:** same rounded-square token as small, 48×48pt, icon at 30pt font,
  `habitColor` on `habitColor.opacity(0.18)` fill, 14pt radius. Leading.
- **Leading VStack** (`alignment: .leading, spacing: 4`), sits right of the icon token
  inside the same HStack — i.e. the real structure is
  `HStack { token; VStack { name; countLine } ; Spacer(); bigNumeral }`:
  - `Text(habit.name)`, `.font(.title3)`, `.fontWeight(.semibold)`, `.lineLimit(1)`,
    `.minimumScaleFactor(0.8)`.
  - `Text("Today: \(n) logged")`, `.font(.subheadline)`,
    `.foregroundStyle(.secondary)`, `.lineLimit(1)`. This is the full canonical
    Log-screen string — medium has the width for it.
- **Trailing big numeral:** `Text("\(n)")`, `.font(.system(size: 44, weight: .bold, design: .rounded))`,
  `.foregroundStyle(habitColor)`, `.minimumScaleFactor(0.6)`, `.lineLimit(1)`. This is
  the one place the habit color is used for text (a large glanceable count), and it
  pairs with the secondary `Today: {n} logged` line so color is never the sole carrier
  of meaning. At triple-digit counts the scale factor shrinks it to fit; it never
  clips.
- Background: same habit-tinted `containerBackground` as small.
- The whole `HStack` is wrapped in one `Button(intent:)`, `.buttonStyle(.plain)`.

> The medium count appears **twice** (the big trailing numeral and the `Today: {n}
> logged` line). This is deliberate: the numeral is the glance value, the text line is
> the unambiguous, VoiceOver-friendly, clinical-tone statement that matches in-app
> copy. They always show the same `n`.

##### State (b): Unconfigured / needs-setup (no habit bound)

No habit is bound (fresh placement, before Edit Widget). A tap must **not** log.
Because the widget content is a `Button(intent:)`, the unconfigured state must use a
**different intent** that does nothing loggable — bind it to an `AppIntent` whose
`perform()` is a no-op returning `.result()` (it cannot deep-link or open config from
inside `perform`; the system's own long-press → Edit Widget is the real path). Simpler
and preferred: in the unconfigured state, render the content **not** wrapped in a
`Button` at all (plain `View`), so there is no log target and a tap falls through to
the system (long-press still opens Edit Widget). Use the no-button approach.

- **Small:** `VStack(alignment: .leading, spacing: 6)`:
  - Icon: `Image(systemName: "square.dashed")`, 26pt, `.foregroundStyle(.secondary)`.
    The dashed-square glyph signals "empty slot," not a habit.
  - `Text("No habit selected")`, `.font(.subheadline)`, `.fontWeight(.medium)`,
    `.foregroundStyle(.primary)`, `.lineLimit(2)`.
  - (No secondary line on small — space.)
- **Medium:** `HStack(spacing: 14)` icon token (dashed square, 40pt, secondary, in a
  `Color(.secondarySystemFill)` rounded token) + `VStack(alignment: .leading, spacing: 4)`:
  - `Text("No habit selected")`, `.font(.headline)`, `.foregroundStyle(.primary)`.
  - `Text("Choose a habit in Edit Widget")`, `.font(.subheadline)`,
    `.foregroundStyle(.secondary)`, `.lineLimit(2)`.
- Background: `.containerBackground(for: .widget) { Color(.systemBackground) }` — **no
  habit-color tint** (there is no habit, and the muted surface signals non-loggable).
- No `Button`. The whole card is one combined accessibility element (see VoiceOver).

##### State (c): Needs-reconfiguration (bound habit archived or deleted)

The stored habit ID no longer resolves to a live, non-archived habit. Identical layout
to state (b) but different glyph and copy, and still **no `Button`** (tap must not
log):

- Glyph: `Image(systemName: "exclamationmark.triangle")`, `.foregroundStyle(.secondary)`
  (not `.red` — this is a setup condition, not a destructive error; `.secondary`
  keeps it calm and clinical). Small 26pt; medium 40pt in a `Color(.secondarySystemFill)`
  token.
- **Small:** `Text("Habit unavailable")`, `.font(.subheadline)`, `.fontWeight(.medium)`,
  `.primary`, `.lineLimit(2)`. No secondary line.
- **Medium:** primary `Text("Habit unavailable")` `.font(.headline)` `.primary`;
  secondary `Text("Edit widget to choose another")` `.font(.subheadline)`
  `.secondary`, `.lineLimit(2)`.
- Background: plain `Color(.systemBackground)` container, no habit tint.
- Do **not** show the dead habit's name or color (the binding is stale; showing it
  would imply it still logs there).

##### State (d): Store-unavailable / non-loggable refresh

The bound habit resolves fine, but on this timeline refresh the shared SwiftData +
CloudKit store could not be read (App Group container unreachable / mid-migration), so
the today count is unknown. Unlike (b)/(c), **tapping still works** — the
`LogResistedIntent` enqueues the write, which persists locally and syncs later (offline
is normal). So this state **keeps the `Button(intent:)`** but cannot show a real count.

- Layout mirrors the **configured** state of the same size, so the user still sees the
  habit identity and a loggable card — only the count is replaced:
  - **Small:** icon token (habit color, as configured) + habit name (as configured) +
    in the count slot, `Text("Count unavailable")`, `.font(.subheadline)`,
    `.foregroundStyle(.secondary)` (no numeral). Single line, no secondary.
  - **Medium:** icon token + name (as configured); the `Today: {n} logged` line is
    replaced by `Text("Count unavailable")` `.font(.subheadline)` `.secondary`, and a
    second line `Text("Tap to log; count updates later")` `.font(.caption)`
    `.foregroundStyle(.tertiary)` (`Color(.tertiaryLabel)`); the trailing big numeral
    is replaced by `Image(systemName: "ellipsis")` 28pt `.foregroundStyle(.secondary)`
    (a neutral "pending" placeholder, never a `0` — `0` would be a false count).
- Background: keep the **habit-color tint** (this is still a loggable card bound to the
  habit), distinguishing it from the un-tinted (b)/(c) non-loggable states.
- Rationale for keeping the tap: dropping the write here would violate UC-W5 (offline
  writes must persist). The widget logs into the local store and the count reconciles
  on the next successful read. The only thing "unavailable" is the *display* of the
  count, not the ability to log.

> If even the habit identity cannot be resolved because the store is unreachable
> (cannot tell configured from unconfigured), fall back to the **needs-reconfiguration
> (c)** appearance with no `Button`, because we cannot guarantee a tap routes to a real
> habit. Prefer (d) whenever the bound habit ID and name are known from the
> configuration intent (which is held by WidgetKit independently of the store) even if
> the count read fails — the configuration carries the habit identity, so identity is
> usually available even when the event count is not.

##### After a tap (timeline reload)

- `LogResistedIntent.perform()` writes one `TemptationEvent` (`outcome = "resisted"`,
  `intensity = nil`, `contextTags = []`, `habit` = the bound habit) to the shared
  container, `try? save()`, then calls
  `WidgetCenter.shared.reloadTimelines(ofKind: "QuickLogWidget")` (or reload all) so
  the widget re-renders with the incremented count.
- **Debounce (UC-W5):** the intent records the last-fire timestamp per widget
  configuration (e.g. in the App Group `UserDefaults` keyed by the habit ID) and
  ignores a second fire within ~800ms of the same configuration, so an accidental
  double-delivery of one physical tap yields one event. Two deliberate taps separated
  by more than the window create two events. This is logic, not visual — there is no
  on-widget indication of debounce.
- There is no animation of the count change — a widget reload is a system-driven
  snapshot replacement, not an animatable view transition. The number simply updates
  on the next render. (Nothing to gate on Reduce Motion here; see below.)

##### Colors and dark mode

- `habitColor` = `Color(hex: habit.colorHex ?? "#007AFF") ?? .blue` — the exact
  existing pattern. Never a hardcoded brand color, never the user *accent* color
  (the widget is habit-scoped, not theme-scoped; accent lives at the app root tint and
  does not apply in the widget extension).
- Card background: `Color(.systemBackground)` + `habitColor.opacity(0.12)` overlay in
  loggable states; plain `Color(.systemBackground)` in (b)/(c). All adaptive →
  **dark mode is automatic**. Do not use a hardcoded translucent gray anywhere (it can
  vanish on the pure-black dark wallpaper, the same failure the in-app context chips
  hit); use `Color(.secondarySystemFill)` for the muted token and `Color(.separator)`
  if any hairline is needed.
- The big medium numeral and the icon glyph are the habit color; everything else is
  `.primary` / `.secondary` / `.tertiary` semantic text. Because the count is also
  stated as text (`Today: {n} logged`), color is never the only carrier of meaning.
- Habit-color contrast on the tinted card: the 12% tint is a faint wash, so
  `.primary` text and the full-saturation habit glyph both keep AA contrast in light
  and dark. (A future ui-iterator pass should screenshot the widget on light and dark
  wallpapers — flagged as follow-up; not done here.)

##### Reduce Motion

There is no widget-side animation to gate (timeline reloads are not animatable view
transitions, and there is no tap-cue animation by design). Reduce Motion therefore has
**no effect** on this widget — call it out so the implementer does not add motion that
would then need gating. The system button touch-down dim is a platform behavior, not
app motion.

##### Dynamic Type

- All text uses text styles (`.headline`, `.title2`, `.title3`, `.subheadline`,
  `.caption`) plus `.minimumScaleFactor` on the constrained lines (habit name, big
  numeral) so large accessibility sizes scale-to-fit instead of clipping. No fixed
  font sizes except the medium big numeral, which is `.system(size: 44, …)` with
  `.minimumScaleFactor(0.6)` so it shrinks rather than clips.
- Widgets do **not** honor arbitrary Dynamic Type past a point (WidgetKit clamps), but
  the layout must still survive the largest size it does honor: on small at AX sizes,
  the long `Today: {n} logged` would overflow, which is exactly why small uses the
  short `{n} today` form. Test small + medium at Default, Large, AX3, AX5 in the widget
  gallery preview.
- Long habit names wrap (small, 2 lines) or scale (medium, 1 line) — never hard
  truncate with an ellipsis on the name itself.

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

**Confirmation Banner:** A status glyph + status word on the left; a correction
control and a destructive control on the right. Full-width with horizontal padding.
System background, 12pt corner radius, subtle shadow. Slides from top, auto-hides 5s.
The banner has two visual states (just-logged and post-gave-in-flip). "Gave in"
flips the just-logged event's outcome to `gave_in` (a pure one-tap edit — no
re-prompts). "Undo" deletes the last logged event. Either interaction cancels the
auto-dismiss timer. The full build-ready layout, both states, and the
Undo-vs-Gave-in disambiguation are specified under **S1 → Outcome Capture
(interaction and visual spec)** below.

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
| Tap | Time of Day period bar (overview) | Expand that period to hourly bars | Full plot-height x-band hit test via `chartOverlay` + `chartProxy` |
| Tap | Time of Day collapse chevron (expanded) | Collapse to four-period overview | 44×44pt min target |
| Tap | Confirmation banner "Gave in" (State 1 only) | Flip last-logged event outcome to `gave_in` (no re-prompt); banner → State 2; re-arm 5s timer | — |
| Tap | Confirmation banner "Undo" (both states) | Delete last-logged event; dismiss banner | — |
| Tap | History event-detail Outcome picker | Open menu, select outcome; persist to that event | — |
| Tap | Quick-Log Widget card (configured / store-unavailable state) | Fire `LogResistedIntent`: write one resisted event for the bound habit, reload timeline | ~800ms per-config debounce against accidental double-fire |
| Long press | Quick-Log Widget card (any state) | System Edit Widget sheet (habit binding) — system gesture, not app-drawn | System default |

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
| Banner outcome flip (State 1 → 2) | Status glyph morph (`.symbolEffect(.replace)`) + label cross-fade + Gave-in/divider opacity-out | 0.2s easeInOut |
| Habit card drag | Interactive spring | — |
| Card snap-back | Spring | 0.3s |
| Time of Day expand/collapse | Bars cross-fade + height change | 0.25s easeInOut |
| Time of Day filter-change while expanded | Bar heights interpolate to new counts | 0.25s easeInOut |
| Sheets, tabs, navigation | System default | System |

#### Time-of-Day Drill-Down motion

- **Expand/collapse:** wrap the `expandedPeriod` mutation in
  `withAnimation(.easeInOut(duration: 0.25))`. The chart swaps its data; Swift Charts
  animates bar height and the new/removed bars cross-fade. The `SectionCard` title
  suffix and collapse chevron appear/disappear within the same animation. Because the
  chart frame height is fixed at 150pt in both states, the card does not jolt — only
  the bars and labels change.
- **Filter change while expanded:** the recompute is animated identically (bars glide
  to their new heights), reinforcing that it is the same period viewed with new data.
- **Reduce Motion (required):** gate every animation above on `!reduceMotion`
  (`@Environment(\.accessibilityReduceMotion)`). When Reduce Motion is on, mutate
  `expandedPeriod` and the filter-driven data with **no** `withAnimation` wrapper —
  the chart swaps instantly, no cross-fade, no height interpolation. This matches the
  established Reduce Motion pattern (instant state change, no spring/slide).

### Confirmation Banner

- Triggers after all sheets dismiss
- **State 1 (just logged):** left = green `checkmark.circle.fill` + "Logged"; right =
  **Gave in** (orange, semibold) · vertical hairline divider · **Undo** (secondary).
  Gave in is the inner control, Undo is at the trailing edge.
- **State 2 (after Gave in tapped):** left = orange `xmark.circle.fill` + "Gave In";
  right = **Undo** only (Gave in button and divider removed).
- Full-width layout with 24pt outer horizontal padding; each control padded to a
  ≥44pt-tall, ~24pt-straddling hit target with `.contentShape(Rectangle())`.
- `.overlay(alignment: .top)` with `.transition(.move(edge: .top).combined(with: .opacity))`
- Auto-hides after **5s** via cancellable `DispatchWorkItem` (extended from 4s to give a
  real in-the-moment correction window). Tapping **Gave in** re-arms a fresh 5s timer
  (banner stays visible in State 2); tapping **Undo** cancels the timer and dismisses.
- "Gave in" sets `lastLoggedEvent.outcome` to `gave_in` and persists; a pure outcome
  edit (no intensity/context/note re-prompt), then transitions the banner to State 2.
- Undo deletes `lastLoggedEvent` from the model context and immediately dismisses the
  banner.
- No haptic on either control (haptic policy: log tap only).
- Does not block interaction or push content.
- Full build-ready layout, both states, colors, and motion: see **S1 → Outcome
  Capture (interaction and visual spec)**.

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
- Banner State 1: status word "Logged"; controls "Gave in" (action, lowercase) and "Undo"
- Banner State 2 (after Gave in): status word "Gave In" (outcome name, title-case); control "Undo"
- Distinction is deliberate: "Gave in" = the button you tap (an action); "Gave In" = the recorded outcome it produces. Both are correct per the canonical strings.
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
User-defined. Managed via the `ContextTag` SwiftData model. Users create and delete tags from the Habits & Settings screen. Tags are displayed as selectable chips on the Log screen (pre-select before logging) using a flow layout. Default seed tags for new installs: Stressed, Bored, Alone, On Phone, With Friends. Location-based tags (At Store, At Work, At Home) were removed because GPS location tracking already captures where events occur.

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

#### Time-of-Day Drill-Down (VoiceOver)

The chart bars are not natively accessible as individual elements, so provide an
explicit accessibility representation rather than relying on the visual `Chart`.

- **Overview bars.** Each period bar is one accessible element.
  - Label: `"{Period}, {n} events"` — e.g. `"Evening, 12 events"`. Use `"1 event"`
    singular, `"0 events"` for zero (not "no events").
  - Trait: `.isButton`.
  - Hint: `"Double tap to show hourly breakdown."`
  - On activate: expands that period (same effect as the visual tap).
- **Collapse control (expanded only).**
  - Label: `"Collapse hourly breakdown"`.
  - Trait: `.isButton`.
  - On activate: returns to the four-period overview.
- **Hourly bars (expanded).** Each hour is one accessible element, ordered the same
  as the visual bars (Night = 9 PM → 4 AM).
  - Label: full unambiguous 12-hour form + count:
    `"{hour 12h with AM/PM}, {n} events"` — e.g. `"6 PM, 4 events"`, `"9 PM, 0 events"`,
    `"12 AM, 1 event"`, `"5 AM, 0 events"`. The visual axis uses terse 24-hour numbers,
    but VoiceOver always speaks the full form so there is no ambiguity for assistive
    tech. Format with a fixed `DateFormatter` (`"h a"`) or a hand-rolled 12-hour map;
    use `"event"` / `"events"` singular/plural correctly.
  - Trait: none beyond static text — hourly bars are read-only (no drill below hour).
- **State-change announcement.** On expand and on collapse, post a
  `UIAccessibility.post(notification: .screenChanged, argument:)` (or
  `.announcement`) with the text `"Showing hourly breakdown for {Period}"` on expand
  and `"Showing time-of-day overview"` on collapse, so a VoiceOver user knows the
  chart content swapped under them.

#### Outcome Capture (VoiceOver)

**Confirmation banner (Surface A).**

- **Status group** is one combined element. In State 1 its label is `"Logged"`; in
  State 2 it is `"Gave In"`. No `.isButton` trait (it is not interactive). Because the
  banner is a transient overlay VoiceOver may not focus on its own, the result is also
  posted as an announcement (see below).
- **Gave in control:** `.accessibilityLabel("Gave in")`, trait `.isButton`, hint
  `"Changes this log's outcome to gave in."` On activate: performs the flip. Present
  only in State 1.
- **Undo control:** `.accessibilityLabel("Undo last log")` (unchanged), trait
  `.isButton`, hint `"Deletes this log."` (added to make it unmistakably distinct from
  the Gave-in edit for non-visual users — one deletes, the other edits). Present in
  both states.
- **Announcements.**
  - On log (existing): `UIAccessibility.post(.announcement, "Temptation logged")`.
  - On **Gave in** flip: post `UIAccessibility.post(.announcement, "Outcome changed to
    gave in")` so a VoiceOver user hears the correction registered (the banner content
    changed under them). Do not re-announce on Undo — the event is gone; the natural
    focus change after dismissal suffices.

**History event-detail picker (Surface C).**

- The Outcome `Picker` is natively accessible as a menu control. Provide
  `.accessibilityLabel("Outcome")`; its value is the current outcome display name
  (`"Resisted"` / `"Gave In"` / `"Not recorded"`), spoken automatically by the menu
  picker. Each option row is a `Label` (icon + text), so VoiceOver reads the full
  outcome name — no icon-only ambiguity.
- No custom announcement is needed: the picker's own selection feedback covers the
  change. The conditional absence of "Not recorded" is simply fewer rows in the menu;
  nothing special to announce.

#### Quick-Log Widget (VoiceOver)

Each state collapses to **one** combined accessibility element
(`.accessibilityElement(children: .combine)` over the card content), because the whole
card is the unit of meaning (and, in loggable states, the single tap target). The
loggable states carry `.isButton`; the non-loggable states do not.

| State | Label | Trait | Hint |
|-------|-------|-------|------|
| (a) Configured / at-rest | `"{Habit}, {n} logged today"` (use `"1 logged today"` / `"0 logged today"`) | `.isButton` | `"Logs a resisted temptation."` |
| (b) Unconfigured | `"No habit selected. Choose a habit in Edit Widget."` | none | `"Long press to edit this widget."` |
| (c) Needs-reconfiguration | `"Habit unavailable. Edit widget to choose another."` | none | `"Long press to edit this widget."` |
| (d) Store-unavailable | `"{Habit}, count unavailable"` | `.isButton` | `"Logs a resisted temptation. Count updates later."` |

Notes:
- The label always speaks the full unambiguous form. On small, where the visual count
  is the terse `{n} today`, VoiceOver still speaks `"{n} logged today"` (the medium
  form), so assistive tech never loses clarity — same principle as the time-of-day
  hourly labels.
- States (b) and (c) carry **no `.isButton` trait** and **no "logs" hint**, because a
  tap there does not log; labeling them as a log action would mislead a non-visual
  user into thinking they had logged. Their hint points at the only available action:
  the system long-press → Edit Widget.
- State (d) keeps `.isButton` and the "logs" hint (the tap *does* log); its label says
  the count is unavailable rather than reading a stale or false number. Do not speak a
  `0` or `ellipsis` as the count.
- The widget extension **cannot post `UIAccessibility` announcements** (no app-process
  accessibility API from a widget). The only feedback after a log is the count change
  on the next timeline reload, which VoiceOver re-reads when the user re-focuses the
  widget. This is an accepted limitation, parallel to the no-haptic and no-banner
  constraints — do not attempt an announcement workaround.

### Dynamic Type

- All text uses SwiftUI text styles (no hardcoded sizes)
- Confirmation banner controls use text styles (`.subheadline`); the banner row has no
  fixed height, so at large Dynamic Type the controls grow and the row grows with them.
  At very large sizes "Gave in" · "Undo" may crowd the status word — allow the status
  label to truncate before the controls (controls are the actionable content); do not
  set a fixed banner height that would clip either. The vertical divider uses a
  text-relative `.frame(height: 20)`; acceptable to let it scale or stay fixed, but
  never let it force-clip the buttons.
- Long habit names wrap, never truncate
- Stat cards stack vertically at accessibility sizes
- Context tag grid reflows
- Intensity circles remain 44pt minimum
- Time of Day card title (`"Time of Day · Evening"`) wraps to a second line at large
  Dynamic Type — no `lineLimit(1)`, no fixed card height that would clip it
- Hourly x-axis labels use `.caption2` and may thin (every other bar) at large sizes;
  bars themselves never clip — the 150pt chart frame is fixed but the bars scale
  within it
- Test at: Default, Large, AX3, AX5

### Reduce Motion

When enabled:
- Confirmation banner: crossfade instead of slide
- Confirmation banner outcome flip (State 1 → 2): instant swap — no symbol-replace
  effect, no label cross-fade, no Gave-in/divider opacity or width animation (mutate
  state outside `withAnimation`)
- Habit card drag: snap immediately instead of spring
- Sheet presentation: system automatic
- Time of Day expand/collapse and filter-driven recompute: instant chart swap, no
  cross-fade or bar-height interpolation (no `withAnimation`)

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

**Quick-Log Widget (WidgetKit)** — Configurable, single-habit Home Screen widget
that logs a resisted temptation in one tap without opening the app (interactive
App Intent, iOS 17+). Shows the bound habit's icon, name, and today's count at
rest. Each placed widget is bound to one habit via `WidgetConfigurationIntent`;
multiple widgets, one per habit. No confirmation/undo in the widget — correction
happens in History. Full brief: User Flows → Flow 5 and Screens → W1. **Scope this
pass: small + medium configurable Home Screen widget only. Out/Later:** Lock
Screen widgets, Control Center controls (iOS 18), multi-habit-in-one-widget, and
showing today's count for a non-configured "default" habit are all deferred (the
configurable single-habit model is the chosen design).

**Apple Watch App (WatchKit)** — Logging only. Complication shows today's count. Outcome selection. Syncs via iCloud.

### Tier 3: Future Consideration

- ~~Custom context tags (user-defined beyond preset 8)~~ — Done: `ContextTag` SwiftData model with inline management
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
| Context tags | User-defined, multiple allowed | Single tag too limiting; hardcoded set too rigid |
| Intensity default | Nil (not 3) | Nil = didn't engage, preserves data integrity |
| Banner timing | After all sheets dismiss, 4s with undo | Was hidden behind sheets; undo prevents accidental logs |
| Default habit | User-settable via context menu | Core for fast logging |
| Time zones | Store UTC, display local | Standard practice |
| Time-of-day drill-down | Tap a period to expand to hourly bars in place | Sparse data makes 24 bars up front noise; detail on demand only |
| Drill-down granularity floor | Hourly for first pass; half-hour deferred | Hourly is enough to locate a spike; finer resolution is "later" |
| Drill-down navigation | In-place expansion, not a pushed screen | Honors max-one-level-deep rule |
| Drill-down filter change while expanded | Recompute hourly bars, stay expanded (don't collapse) | Filter change is a follow-up to the same question; collapsing loses the user's place |
| Drill-down collapse affordance | Explicit `chevron.up.circle` in card header; tapping hourly bars does nothing | Overview bars are gone when expanded, so "tap same to collapse" is ambiguous |
| Drill-down tap target | Whole period bar's full-height x-band (chartOverlay hit test), not a chevron | Keeps the overview clean; zero-count bars stay tappable |
| Hourly axis label format | Bare hour number (24h: `5`…`21,22,23,0`…`4`); VoiceOver speaks full 12h AM/PM | Most compact unambiguous visual label; assistive tech keeps full clarity |
| New-event default outcome | `resisted` (was `unknown`) | "Resisted" is the common case; recording it by default removes the need for an up-front outcome step and keeps logging one tap |
| Outcome capture model | Default to resisted, correct to gave-in after the fact; never a fork before/while logging | Preserves single-tap speed; correction is the rare path and belongs after the log |
| "Gave in" correction depth | Pure one-tap outcome flip; no intensity/context/note re-prompt | The correction is about accuracy, not re-entering the whole event |
| Banner dwell | 5s (was 4s) | A 4s window is too tight to read "Logged", recognize the outcome was wrong, and tap "Gave in"; 5s is the minimum credible correction window without leaving the banner lingering |
| "Unknown" / "Not recorded" settability | Not newly settable from the Log banner; in History, offered only when the event is already `unknown` | `unknown` is a legacy state for pre-capture data; never invite users to downgrade a real outcome to "Not recorded" |
| Outcome correction surfaces | Banner (in the moment) + History detail picker (after the fact); no third surface | Two surfaces cover both timing windows without adding navigation depth |
| Banner Gave-in vs Undo disambiguation | Gave in = inner, orange, semibold; vertical divider; Undo = outer/trailing, secondary, regular weight | Color + weight + position separate the edit from the destructive delete; destructive action sits furthest from thumb's post-log sweep |
| Banner after Gave-in tap | Recolors to orange `xmark.circle.fill` + "Gave In", removes Gave-in button + divider, re-arms 5s timer, keeps Undo | Confirms the correction registered, gives time to verify/Undo, removes the now-meaningless re-tap of Gave in |
| Banner outcome word | "Logged" (State 1), "Gave In" (State 2) — not "Resisted" | Banner confirms the log action; surfacing "Resisted" would imply a choice the user didn't make |
| History outcome picker style | Inline `.menu`-style `Picker` (icon+text rows), not segmented | Conditional option count (2 vs 3) makes a sometimes-3-segment control unstable; menu keeps the collapsed row identical to other read-only rows |
| Banner control haptics | None | Haptic policy: only the log tap gets haptic; secondary actions get none |
| Quick-log widget binding | Configurable, one habit per widget (`WidgetConfigurationIntent` + `AppEntity` over non-archived habits) | Avoids a tap-time picker; keeps one tap = one log; user places multiple widgets for multiple habits |
| Quick-log widget action | One tap writes one `resisted` event (intensity nil, no tags) via interactive App Intent; no app launch | Mirrors the in-app single-tap default (UC-O1); removes the open-app friction in the urge moment |
| Quick-log widget correction/undo | None in widget; correct outcome and delete in History (UC-O4) | A widget cannot show transient banner/undo UI; editing already lives in the app |
| Quick-log widget vs notifications ban | No collision; a widget is passive Home Screen content, not a push/alert | The ban is on interruptive notifications; the widget never alerts, schedules, or pushes |
| Quick-log widget scope | Small + medium configurable Home Screen widget only | Lock Screen, Control Center (iOS 18), multi-habit, and default-habit display deferred; configurable single-habit is the chosen model |
| Quick-log widget data sharing | App Group–shared SwiftData + CloudKit store; additive only | Widget extension and app must share one container; no schema change — event shape already exists |
| Quick-log widget at-rest count form | Medium `Today: {n} logged` (full canonical string); small `{n} today` | Small cannot fit the long form alongside the habit name at large Dynamic Type without truncating the name; the short form preserves the name |
| Quick-log widget tap target | Whole card is one `Button(intent:)` in loggable states; no `Button` in (b)/(c) | The card is the affordance (matches in-app habit card); removing the button in non-loggable states guarantees a tap cannot write a stray event |
| Quick-log widget tap affordance | Filled habit-color-tinted card + icon token; system touch-down dim only; no hint text, no custom motion | A widget cannot animate a cue and clinical tone forbids "tap to log"; a filled tinted card vs flat secondary card is the loggable/not-loggable signal |
| Quick-log widget non-loggable visuals | (b)/(c) drop the habit-color tint and use a muted `square.dashed` / `exclamationmark.triangle` glyph in `.secondary`, no `Button` | The card must not *look* like a primed log button when a tap won't log; `.secondary` (not `.red`) keeps a setup condition calm and clinical |
| Quick-log widget store-unavailable | Keeps the tap (write enqueues + syncs later), replaces the count with `Count unavailable` / `ellipsis`, keeps habit tint | UC-W5 requires offline writes to persist; only the count *display* is unavailable, so the card stays loggable and never shows a false `0` |
| Quick-log widget haptics / motion / announcements | None — platform-limited in a widget extension | Widgets can't fire haptics, animate timeline reloads, or post `UIAccessibility` announcements; the count change on reload is the only feedback |
