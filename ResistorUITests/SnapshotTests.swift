import XCTest

/// Drives the app through its main screens and captures a named screenshot of
/// each, saved as `.keepAlways` attachments. The `scripts/ui-shots.sh` harness
/// runs this test and exports the attachments to flat PNG files that Claude can
/// read.
///
/// The app is launched with `-uiTestMode`, which boots a clean in-memory store
/// seeded with deterministic sample data (see `UITestSeed`), so every run
/// produces identical content and never touches the real CloudKit store.
final class SnapshotTests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    /// Light-appearance capture → `01-Log.png`, `02-Insights.png`, …
    func testCaptureAllScreens() {
        captureAllScreens(dark: false)
    }

    /// Dark-appearance capture → `01-Log-dark.png`, `02-Insights-dark.png`, …
    /// Launches with `-uiTestDarkMode`, which forces `.dark` at the app root so
    /// hardcoded (non-adaptive) colors show up exactly as a dark-mode user sees
    /// them.
    func testCaptureAllScreensDark() {
        captureAllScreens(dark: true)
    }

    /// First-run onboarding intro capture → `00-Onboarding.png` /
    /// `00-Onboarding-dark.png`. Launches with `-uiTestOnboarding`, which boots
    /// an empty store with onboarding incomplete and a nil accent (system blue),
    /// so ContentView routes to the new intro premise screen.
    func testCaptureOnboardingIntro() {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestMode", "-uiTestOnboarding"]
        app.launch()
        _ = app.staticTexts["Resistor"].waitForExistence(timeout: 5)
        snapshot(app, name: "00-Onboarding")
    }

    func testCaptureOnboardingIntroDark() {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestMode", "-uiTestOnboarding", "-uiTestDarkMode"]
        app.launch()
        _ = app.staticTexts["Resistor"].waitForExistence(timeout: 5)
        snapshot(app, name: "00-Onboarding-dark")
    }

    /// Onboarding intro at an accessibility (XXXL) Dynamic Type size, to verify
    /// the premise text and Continue button reflow/scroll rather than clip.
    func testCaptureOnboardingIntroLargeText() {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestMode", "-uiTestOnboarding"]
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        _ = app.staticTexts["Resistor"].waitForExistence(timeout: 5)
        snapshot(app, name: "00-Onboarding-large")
        // Scroll to the bottom to confirm the Continue button is reachable and
        // not clipped at the largest Dynamic Type size.
        app.swipeUp(velocity: .slow)
        app.swipeUp(velocity: .slow)
        snapshot(app, name: "00-Onboarding-large-b")
    }

    /// Walks every screen and captures a named screenshot of each. When `dark`
    /// is true the app is launched in forced dark mode and each screenshot name
    /// gets a `-dark` suffix so light and dark captures coexist on disk.
    private func captureAllScreens(dark: Bool) {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestMode"]
        if dark { app.launchArguments += ["-uiTestDarkMode"] }
        app.launch()
        let sfx = dark ? "-dark" : ""

        // 1. Log (launch screen)
        snapshot(app, name: "01-Log\(sfx)")

        // 1a. Confirmation banner (transient, ~5s after a log). Tap the habit
        // card to log, which slides the banner down in State 1 (Logged · Gave in
        // · Undo). Then tap "Gave in" to capture State 2 (Gave In · Undo).
        captureConfirmationBanner(app, sfx: sfx)

        // 2. Insights
        if app.tabBars.buttons["Insights"].waitForExistence(timeout: 5) {
            app.tabBars.buttons["Insights"].tap()
            snapshot(app, name: "02-Insights\(sfx)")

            // Scrolled captures so the below-the-fold sections can be reviewed.
            let scroll = app.scrollViews.firstMatch
            if scroll.waitForExistence(timeout: 3) {
                scroll.swipeUp(velocity: .slow)
                snapshot(app, name: "02-Insights-b\(sfx)")
                scroll.swipeUp(velocity: .slow)
                snapshot(app, name: "02-Insights-c\(sfx)")
                scroll.swipeUp(velocity: .slow)
                snapshot(app, name: "02-Insights-d\(sfx)")
                // Return to top for the History leg below.
                scroll.swipeDown(velocity: .fast)
                scroll.swipeDown(velocity: .fast)
                scroll.swipeDown(velocity: .fast)
            }

            // Time-of-Day drill-down: expand a period into its hourly bars and
            // capture both a typical window (Evening, 4 bars) and the densest
            // window (Night, 8 bars across midnight) so the label-thinning and
            // across-midnight order can be reviewed visually. The whole period
            // bar's x-band is the tap target (chartOverlay hit test), so we tap
            // the chart plot at the period's horizontal position.
            captureTimeOfDayDrilldown(app, scroll: scroll, sfx: sfx)

            // 3. History — pushed from Insights via "View History".
            let history = app.buttons["View History"]
            if history.waitForExistence(timeout: 3) {
                history.tap()
                _ = app.navigationBars.firstMatch.waitForExistence(timeout: 3)
                snapshot(app, name: "03-History\(sfx)")

                // Event detail sheet — open the first event's .medium-detent
                // detail sheet (whose Outcome row is now an inline menu Picker)
                // and capture it.
                captureEventDetailSheet(app, sfx: sfx)

                // Back to Insights for the next leg.
                if app.navigationBars.buttons.firstMatch.exists {
                    app.navigationBars.buttons.firstMatch.tap()
                }
            }
        }

        // 4. Habits & Settings
        if app.tabBars.buttons["Habits"].waitForExistence(timeout: 5) {
            app.tabBars.buttons["Habits"].tap()
            snapshot(app, name: "04-Habits\(sfx)")

            // 5. New Habit sheet & 6. Edit Habit sheet — both use the same form,
            // whose color/icon pickers carry the selection-ring rendering we want
            // to verify isn't clipped. Captured before scrolling the list so the
            // add button and the first habit row are both on screen.
            captureHabitFormSheet(
                app, open: { app.buttons["addHabitButton"].tap() },
                title: "New Habit", namePrefix: "05-NewHabit", sfx: sfx
            )
            captureHabitFormSheet(
                app, open: { app.staticTexts["Sugar"].tap() },
                title: "Edit Habit", namePrefix: "06-EditHabit", sfx: sfx
            )

            // Scrolled captures so the Settings / Context Tags sections below
            // the fold can be reviewed. An inset-grouped List surfaces as a
            // collectionView/table rather than a plain scrollView.
            var scroll = app.collectionViews.firstMatch
            if !scroll.exists { scroll = app.tables.firstMatch }
            if !scroll.exists { scroll = app.scrollViews.firstMatch }
            if scroll.waitForExistence(timeout: 3) {
                scroll.swipeUp(velocity: .slow)
                snapshot(app, name: "04-Habits-b\(sfx)")
                scroll.swipeUp(velocity: .slow)
                snapshot(app, name: "04-Habits-c\(sfx)")
            }
        }
    }

    /// Logs a temptation by tapping the habit card, captures the confirmation
    /// banner in State 1 (Logged · Gave in · Undo), then taps "Gave in" to
    /// capture State 2 (Gave In · Undo). The banner auto-dismisses after 5s, so
    /// each capture happens immediately after the triggering tap. Finally taps
    /// Undo to clear the just-logged event so it doesn't pollute later screens.
    private func captureConfirmationBanner(_ app: XCUIApplication, sfx: String) {
        // The Log habit card is a combined accessibility button labelled
        // "Log temptation for <habit>". Sugar is the seeded default habit.
        let card = app.buttons["Log temptation for Sugar"]
        guard card.waitForExistence(timeout: 5) else { return }
        card.tap()

        // State 1 — the banner shows "Logged", a "Gave in" control and "Undo".
        let gaveIn = app.buttons["Gave in"]
        guard gaveIn.waitForExistence(timeout: 3) else { return }
        snapshot(app, name: "01-Log-banner1\(sfx)")

        // State 2 — tapping "Gave in" flips the outcome in place; the banner
        // morphs to "Gave In" with only "Undo" remaining.
        gaveIn.tap()
        let undo = app.buttons["Undo last log"]
        if undo.waitForExistence(timeout: 3) {
            snapshot(app, name: "01-Log-banner2\(sfx)")
            // Remove the just-logged event so it doesn't alter later captures.
            undo.tap()
        }
        // Let the banner fully dismiss before moving on.
        _ = app.buttons["Log temptation for Sugar"].waitForExistence(timeout: 2)
    }

    /// Scrolls the Time of Day card into view and drives the drill-down by
    /// tapping the chart plot at a given period's horizontal band, capturing the
    /// resulting expanded (hourly) state. Captures Evening (4 bars) and Night
    /// (8 bars wrapping midnight) so the dense-label case can be judged, then
    /// collapses via the chevron control.
    private func captureTimeOfDayDrilldown(_ app: XCUIApplication, scroll: XCUIElement, sfx: String) {
        // Bring the Time of Day card into the middle of the screen. Swipe until
        // the title is actually on screen rather than a fixed number of times —
        // the cards above it change height whenever Insights gains a section,
        // and a hardcoded swipe count silently lands the tap on the wrong card.
        // Not just "visible": the tap lands 60pt *below* the title, so a title
        // sitting near the bottom edge puts the tap past the card entirely —
        // onto the next card, whose Top Locations rows navigate away to the map.
        // Scroll until the title is in the top 60% of the screen so the whole
        // plot is on screen too.
        let cardTitle = app.staticTexts["Time of Day"]
        func titleIsHighOnScreen() -> Bool {
            cardTitle.exists && cardTitle.isHittable && cardTitle.frame.maxY < app.frame.height * 0.6
        }
        func scrollTitleIntoPosition() {
            // Down first: the card can be *above* the viewport (an expand /
            // collapse changes its height and shifts everything), and swiping
            // up from there only pushes it further away.
            if !titleIsHighOnScreen() {
                scroll.swipeDown(velocity: .fast)
                scroll.swipeDown(velocity: .fast)
            }
            for _ in 0..<5 where !titleIsHighOnScreen() {
                scroll.swipeUp(velocity: .slow)
            }
        }
        scrollTitleIntoPosition()

        // The real expand interaction is a `chartOverlay` spatial-tap hit test
        // on the chart plot. The mirrored accessibility buttons are zero-height
        // proxies whose frames don't track the chart, so we tap the plot
        // directly — but anchored to the card's *title*, not to a normalized
        // offset in the scroll view. A normalized offset silently drifts onto a
        // neighbouring card whenever the content above changes height, and a
        // missed tap just skips the capture with no failure.
        let title = app.staticTexts["Time of Day"]
        guard title.waitForExistence(timeout: 3) else {
            XCTFail("Time of Day card never appeared — drill-down capture skipped")
            return
        }
        // The four period bands run left→right (Morning, Afternoon, Evening,
        // Night) across the card's width; `plotY` sits on the bars, below the
        // title and above the x-axis labels.
        //
        // The frame is re-read on every attempt rather than captured once:
        // expanding the card and collapsing it again changes its height, so a
        // frame taken before the first tap is stale by the second and the tap
        // lands 60pt below where the title now is.
        func tapPeriod(dx: CGFloat, named: String) {
            for _ in 0..<2 {
                scrollTitleIntoPosition()
                let frame = title.frame
                let plotY = frame.maxY + 60
                let x = frame.minX + (app.frame.width - frame.minX * 2) * dx
                app.coordinate(withNormalizedOffset: .zero)
                    .withOffset(CGVector(dx: x, dy: plotY))
                    .tap()
                if app.buttons["Collapse hourly breakdown"].waitForExistence(timeout: 2) { return }
            }
            XCTFail("Tapping the \(named) band did not expand the hourly drill-down")
        }

        // Evening — the simple 4-bar case (3rd of 4 bands).
        tapPeriod(dx: 0.60, named: "Evening")
        snapshot(app, name: "02-Insights-tod-evening\(sfx)")
        collapseTimeOfDay(app)

        // Night — the dense 8-bar across-midnight case (21,22,23,0,1,2,3,4),
        // 4th of 4 bands.
        tapPeriod(dx: 0.85, named: "Night")
        snapshot(app, name: "02-Insights-tod-night\(sfx)")
        collapseTimeOfDay(app)

        // Restore scroll position for any later legs.
        scroll.swipeDown(velocity: .fast)
        scroll.swipeDown(velocity: .fast)
    }

    /// Opens the first History event's detail sheet and captures it so the
    /// inline Outcome menu Picker row can be reviewed (icon tint, display name,
    /// menu chevron affordance). Dismisses via the Done button afterward.
    ///
    /// NOTE: History event rows use `.accessibilityElement(children: .combine)`
    /// with a custom `.onTapGesture` (not a real `Button`), so XCUITest cannot
    /// `.tap()` the reported row element (it is non-hittable). Tapping the
    /// enclosing List *cell* does dispatch the gesture, and `HistoryView` uses
    /// `.sheet(item:)` so the sheet always presents with its content bound.
    private func captureEventDetailSheet(_ app: XCUIApplication, sfx: String) {
        // The first List cell (index 0) is the date-section header; the first
        // event row is cell index 1. Cells are hittable even though the inner
        // combined element is not.
        let eventCell = app.cells.element(boundBy: 1)
        guard eventCell.waitForExistence(timeout: 3) else { return }
        if eventCell.isHittable { eventCell.tap() }

        // Wait for the sheet's content to render (its Done button), then capture.
        let done = app.buttons["Done"]
        guard done.waitForExistence(timeout: 5) else { return }
        snapshot(app, name: "03-History-detail\(sfx)")
        done.tap()
        _ = app.navigationBars["Sugar History"].waitForExistence(timeout: 5)
    }

    private func collapseTimeOfDay(_ app: XCUIApplication) {
        let chevron = app.buttons["Collapse hourly breakdown"]
        if chevron.waitForExistence(timeout: 2) {
            chevron.tap()
        }
    }

    /// Opens the add/edit habit form sheet, captures the top (name + Color
    /// picker) and a scrolled view (Icon picker + Preview), then cancels back
    /// out. `open` performs the gesture that presents the sheet; `title` is the
    /// sheet's navigation-bar title used to confirm it appeared and to dismiss.
    private func captureHabitFormSheet(
        _ app: XCUIApplication,
        open: () -> Void,
        title: String,
        namePrefix: String,
        sfx: String
    ) {
        open()
        guard app.navigationBars[title].waitForExistence(timeout: 3) else { return }
        snapshot(app, name: "\(namePrefix)\(sfx)")
        // A full-sheet Form scrolls with a window swipe; reveal the Icon picker.
        app.swipeUp(velocity: .slow)
        snapshot(app, name: "\(namePrefix)-b\(sfx)")
        let cancel = app.navigationBars[title].buttons["Cancel"]
        if cancel.exists { cancel.tap() }
    }

    /// The Log card is a swipeable page, so its size must not depend on which
    /// habit it shows — a card that resizes mid-slide shoves the rest of the
    /// column around. Every card therefore takes its height from the tallest
    /// description any habit has, laid out hidden behind the visible one.
    ///
    /// Two halves, and the second is what stops the old fixed two-line reserve
    /// coming back: a description-less habit's card must match a described one
    /// (uniformity), *and* adding a habit whose description runs longer than any
    /// existing one must grow every card (the height follows the real text, so
    /// an app with no descriptions has no dead band and a long one isn't cut
    /// off). Lives here rather than in its own file because the UITest target
    /// has an explicit file list, not a synchronized folder group.
    func testHabitCardSizeFollowsTheLongestDescription() {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestMode"]
        app.launch()

        let described = app.buttons["Log temptation for Sugar"]
        XCTAssertTrue(described.waitForExistence(timeout: 5), "seeded habit card not found")
        let seededSize = described.frame.size

        addHabit(app, name: "Bare", description: nil)
        let bare = app.buttons["Log temptation for Bare"]
        showCard(app, bare, "new habit card not reachable")

        XCTAssertEqual(bare.frame.width, seededSize.width, accuracy: 0.5)
        XCTAssertEqual(bare.frame.height, seededSize.height, accuracy: 0.5,
                       "a habit with no description must not get a shorter card")

        // Longer than either seeded description, so it has to lengthen the card.
        addHabit(app, name: "Wordy", description: String(repeating: "long enough ", count: 10))
        let wordy = app.buttons["Log temptation for Wordy"]
        showCard(app, wordy, "long-description card not reachable")
        // Read now — paging away leaves `wordy` out of the tree entirely, and
        // `frame` on a missing element fails rather than returning a stale value.
        let wordyHeight = wordy.frame.height

        XCTAssertGreaterThan(wordyHeight, seededSize.height,
                             "the card must grow to fit a description longer than the reserve")
        showCard(app, bare, "bare card not reachable after adding a longer description")
        XCTAssertEqual(bare.frame.height, wordyHeight, accuracy: 0.5,
                       "every card must match the tallest one")
    }

    /// Creates a habit from the Log screen's add sheet.
    private func addHabit(_ app: XCUIApplication, name: String, description: String?) {
        app.buttons["addHabitButtonLog"].tap()
        let nameField = app.textFields["Habit name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5), "add-habit sheet did not appear")
        nameField.tap()
        nameField.typeText(name)

        if let description {
            // `axis: .vertical` can surface as either, depending on the runtime.
            let field = app.textFields["Description (optional)"]
            let descriptionField = field.exists ? field : app.textViews["Description (optional)"]
            XCTAssertTrue(descriptionField.waitForExistence(timeout: 2), "description field not found")
            descriptionField.tap()
            descriptionField.typeText(description)
        }

        app.buttons["Save"].tap()
    }

    /// Pages the carousel until `card` is the one on screen. New habits take the
    /// next sortOrder, so they land at the end. Waits rather than testing
    /// `.exists` before each tap: right after a sheet dismisses, the card behind
    /// it isn't in the tree yet, and an instantaneous check sends the pager off
    /// on a lap it didn't need.
    private func showCard(_ app: XCUIApplication, _ card: XCUIElement, _ message: String) {
        for _ in 0..<8 {
            if card.waitForExistence(timeout: 1) { return }
            app.buttons["Next habit"].tap()
        }
        XCTFail(message)
    }

    /// "Edit" really puts the habits list into edit mode. `HabitsView` owns its
    /// own `isEditing` and installs `\.editMode` itself, because `EditButton`
    /// writes to the one the `NavigationStack` installs *below* `HabitsView` —
    /// where the rows can't read it to know when to hide their grip hint. Nothing
    /// else covers that binding, and if it broke the hint would show while
    /// dragging reordered nothing.
    ///
    /// Deliberately stops at "the grips exist". Whether a drag then rewrites
    /// `sortOrder`, and whether that moves the habit Log opens on, is pinned
    /// deterministically by `testMoveHabitsRewritesSortOrderDensely`,
    /// `testMoveHabitsPersists` and `testReorderingChangesWhichHabitOpens`. An
    /// earlier version of this test dragged one row onto another and asserted the
    /// Log screen followed; it passed locally and on one CI run, then failed on
    /// the next. All that half added over those unit tests was confirmation that
    /// UIKit delivers a synthesized drag to `.onMove` — Apple's code, via the one
    /// gesture XCUITest is least reliable at.
    func testEditModeActivatesReorderGrips() {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestMode"]
        app.launch()

        // Seeded order is Sugar, then Doomscrolling.
        XCTAssertTrue(app.buttons["Log temptation for Sugar"].waitForExistence(timeout: 5),
                      "Log screen should open on the first habit in display order")

        app.buttons["Habits"].tap()
        XCTAssertTrue(app.navigationBars["Habits"].waitForExistence(timeout: 5))
        app.navigationBars["Habits"].buttons["Edit"].tap()

        // UIKit draws these off the edit mode this view owns, so they exist only
        // if the binding reached the List. Waited for rather than checked with
        // `.exists`, which samples once and races the rows' layout on a slow runner.
        XCTAssertTrue(app.buttons["Reorder Sugar"].waitForExistence(timeout: 10),
                      "no reorder grip — edit mode did not reach the List")
        XCTAssertTrue(app.buttons["Reorder Doomscrolling"].waitForExistence(timeout: 10),
                      "no reorder grip — edit mode did not reach the List")
    }

    private func snapshot(_ app: XCUIApplication, name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
