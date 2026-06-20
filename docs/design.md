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
8. Confirmation banner slides down with "Undo" option, auto-hides after 4s.

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

**Confirmation Banner:** Green checkmark + "Logged" on left, subtle "Undo" text button on right. Full-width with horizontal padding. System background, 12pt corner radius, subtle shadow. Slides from top, auto-hides 4s. Undo deletes the last logged event and immediately dismisses the banner.

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
- Left side: green checkmark + "Logged". Right side: subtle "Undo" text button (secondary color)
- Full-width layout with 24pt horizontal padding
- `.overlay(alignment: .top)` with `.transition(.move(edge: .top).combined(with: .opacity))`
- Auto-hides after 4s via cancellable `DispatchWorkItem`
- Undo deletes `lastLoggedEvent` from the model context and immediately dismisses the banner
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
- "Logged" confirmation with "Undo" option
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

### Dynamic Type

- All text uses SwiftUI text styles (no hardcoded sizes)
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

**Home Screen Widget (WidgetKit)** — Today's count for default habit. Small/medium/large sizes. No logging from widget.

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
