import XCTest

final class ES80ResearchCaptureUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        executionTimeAllowance = 120
    }

    @MainActor
    func testPassiveResearchLaunchShowsOnlyTheExplicitCaptureSurface() {
        let app = XCUIApplication()
        app.launchArguments = ["--es80-passive-capture"]
        app.launch()

        XCTAssertTrue(
            app.navigationBars["ES80 Capture"].waitForExistence(timeout: 5),
            "The explicit research launch must open the passive ES80 capture surface."
        )
        XCTAssertTrue(
            app.staticTexts["Passive evidence only"].waitForExistence(timeout: 3),
            "The research shell must keep its passive-only truth boundary visible."
        )
        XCTAssertTrue(app.buttons["Start scan"].exists)
        XCTAssertFalse(
            app.buttons["Vehicle controls"].exists,
            "Research capture must not silently start or expose the normal vehicle-control experience."
        )

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "ES80 Passive Research Capture"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
