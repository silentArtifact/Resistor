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
        // Bring the Time of Day card into the middle of the screen. It sits
        // below the Daily Trend chart; one slow swipe from the top reveals it
        // without pushing it off the top edge, so the expanded chart stays
        // fully visible in the capture.
        scroll.swipeUp(velocity: .slow)

        // The real expand interaction is a `chartOverlay` spatial-tap hit test
        // on the chart plot. The mirrored accessibility buttons are zero-height
        // proxies whose frames don't track the chart, so we tap the chart plot
        // directly by normalized position within the scroll view. The four
        // period bands run left→right (Morning, Afternoon, Evening, Night); dy
        // sits on the bars, above the x-axis labels.
        func tapPeriod(dx: CGFloat) {
            scroll.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: 0.63)).tap()
        }

        // Evening — the simple 4-bar case (3rd of 4 bands).
        tapPeriod(dx: 0.60)
        if app.buttons["Collapse hourly breakdown"].waitForExistence(timeout: 2) {
            snapshot(app, name: "02-Insights-tod-evening\(sfx)")
            collapseTimeOfDay(app)
        }

        // Night — the dense 8-bar across-midnight case (21,22,23,0,1,2,3,4),
        // 4th of 4 bands.
        tapPeriod(dx: 0.82)
        if app.buttons["Collapse hourly breakdown"].waitForExistence(timeout: 2) {
            snapshot(app, name: "02-Insights-tod-night\(sfx)")
            collapseTimeOfDay(app)
        }

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

    /// Captures a full-screen screenshot and attaches it under `name`.
    private func snapshot(_ app: XCUIApplication, name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
