import Foundation
import XCTest

final class ES80ResearchCaptureUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        executionTimeAllowance = 120
    }

    @MainActor
    func testV14ResearchLaunchShowsMechanicalCorrelationAndKeepsFinalSealLocked() {
        let app = XCUIApplication()
        app.launchArguments = ["--es80-passive-capture"]
        app.launch()

        XCTAssertTrue(
            app.navigationBars["Nembra Capture"].waitForExistence(timeout: 5),
            "The explicit research launch must open the dedicated Nembra Capture surface."
        )
        XCTAssertTrue(
            app.staticTexts["NEMBRA CAPTURE"].waitForExistence(timeout: 3),
            "The V14 capture identity must remain visible."
        )
        XCTAssertTrue(
            app.staticTexts["Physical Experiment One locked"].waitForExistence(timeout: 3),
            "The app must expose the physical NO-GO boundary instead of implying a runnable experiment."
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["es80.capture.correlation-progress"].waitForExistence(timeout: 3),
            "The primary workflow must expose the four-window OFF1/ON1/OFF2/ON2 correlation sequence."
        )
        XCTAssertTrue(
            app.buttons["es80.capture.begin-window"].waitForExistence(timeout: 3),
            "Preflight must lead to the first bounded OFF window instead of a generic manual candidate scan."
        )

        XCTAssertFalse(
            app.buttons["Scan for scooter"].exists,
            "The V13 generic manual-candidate scan must not remain the primary correlation path."
        )
        XCTAssertFalse(
            app.buttons["Start passive capture"].exists,
            "The app must not splice standalone correlation into a separately-issued capture authority."
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["es80.capture.start"].exists,
            "No hidden or differently-labeled Start Capture action may bypass the Experiment One authority boundary."
        )
        XCTAssertFalse(
            app.buttons["Finish Capture"].exists,
            "Finish must remain unavailable until the accepted Horizon/seal controller authority is app-visible."
        )
        XCTAssertFalse(
            app.buttons["Vehicle controls"].exists,
            "Research capture must not silently expose the normal vehicle-control experience."
        )
        XCTAssertFalse(
            app.buttons["Advanced details"].exists,
            "The control-capable package research console must not become a second acquisition workflow."
        )

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Nembra Capture V14 — Physical Run Locked"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
