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

            // 3. History — pushed from Insights via "View History".
            let history = app.buttons["View History"]
            if history.waitForExistence(timeout: 3) {
                history.tap()
                _ = app.navigationBars.firstMatch.waitForExistence(timeout: 3)
                snapshot(app, name: "03-History\(sfx)")
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

    /// Captures a full-screen screenshot and attaches it under `name`.
    private func snapshot(_ app: XCUIApplication, name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
