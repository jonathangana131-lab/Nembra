import XCTest

/// V14 physical-safety acceptance for the current field build.
///
/// The product may preview Capture structure while Experiment One is NO-GO, but it
/// must not expose an actionable control that starts OFF1/ON1/OFF2/ON2 against a
/// real scooter. Simulator/demo fixtures can exercise that UX only through a
/// separately explicit synthetic path; the default field launch remains locked.
final class ES80PhysicalNoGoGateUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        executionTimeAllowance = 120
    }

    @MainActor
    func testDefaultResearchFieldLaunchCannotBeginPhysicalPowerCycleWhileNoGo() {
        let app = XCUIApplication()
        app.launchArguments = ["--es80-passive-capture"]
        app.launch()

        XCTAssertTrue(
            app.navigationBars["Nembra Capture"].waitForExistence(timeout: 5),
            "The explicit research launch must open the dedicated Capture surface."
        )
        XCTAssertTrue(
            app.staticTexts["Physical Experiment One locked"].waitForExistence(timeout: 3),
            "The field build must make the package-owned physical NO-GO state visible."
        )

        let beginWindow = app.buttons["es80.capture.begin-window"]
        XCTAssertFalse(
            beginWindow.exists,
            "NO-GO must mechanically withhold the actionable OFF/ON experiment control; lock copy beside a runnable button is contradictory physical authority."
        )

        XCTAssertFalse(
            app.buttons["Begin OFF/ON window"].exists,
            "A differently-addressed or fallback-labeled physical correlation action must not bypass NO-GO."
        )
        XCTAssertFalse(
            app.buttons["Start passive capture"].exists,
            "The field build must not bypass the physical gate through the legacy capture entry."
        )
        XCTAssertFalse(
            app.buttons["Finish Capture"].exists,
            "No terminal action is available while the physical procedure and final controller binding are locked."
        )

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Nembra Capture V14 — Mechanical Physical NO-GO"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
