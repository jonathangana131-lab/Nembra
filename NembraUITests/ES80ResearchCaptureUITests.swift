import Foundation
import XCTest

final class ES80ResearchCaptureUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        executionTimeAllowance = 120
    }

    @MainActor
    func testV14ResearchLaunchMechanicallyBlocksPhysicalExperimentWhilePackageIsNoGo() {
        let app = XCUIApplication()
        app.launchArguments = ["--es80-passive-capture"]
        app.launch()

        XCTAssertTrue(
            app.navigationBars["Nembra Capture"].waitForExistence(timeout: 5),
            "The explicit research launch must open the dedicated Nembra Capture surface."
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["es80.capture-shell"].waitForExistence(timeout: 3),
            "The dedicated package-owned Capture shell must be the active product surface."
        )
        XCTAssertTrue(
            app.staticTexts["NEMBRA CAPTURE"].waitForExistence(timeout: 3),
            "The V14 capture identity must remain visible."
        )
        XCTAssertTrue(
            app.staticTexts["Field procedure locked"].waitForExistence(timeout: 3),
            "The current package-owned NO-GO must be the primary status."
        )
        XCTAssertTrue(
            app.staticTexts["FIELD AUTHORITY"].waitForExistence(timeout: 3),
            "The lock must be explained as field authority rather than a generic Bluetooth failure."
        )
        XCTAssertTrue(
            app.staticTexts["This build is not authorized"].waitForExistence(timeout: 3),
            "The product must state plainly that this build cannot run the physical procedure."
        )
        XCTAssertTrue(
            app.staticTexts["PASSIVE / READ ONLY"].waitForExistence(timeout: 3),
            "The passive-only safety boundary must remain visible."
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["es80.capture.single-authority"].waitForExistence(timeout: 3),
            "The one-authority evidence explanation must remain in the locked shell."
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["es80.capture.experiment-progress"].waitForExistence(timeout: 3),
            "The Experiment One progress instrument must render without creating an executable action."
        )

        XCTAssertFalse(
            app.buttons["Confirm stationary setup"].exists,
            "The setup-declaration action is part of the physical Experiment One path and must remain unreachable while the package field gate is NO-GO."
        )
        XCTAssertFalse(
            app.buttons["Begin OFF 1 window"].exists,
            "A NO-GO build must not expose the first physical OFF/ON action."
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["es80.capture.begin-window"].exists,
            "No hidden or differently-labeled correlation-window action may bypass the package gate."
        )
        XCTAssertFalse(
            app.buttons["Confirm correlated target"].exists,
            "Target confirmation must not become reachable before field authorization."
        )
        XCTAssertFalse(
            app.buttons["Begin passive observation"].exists,
            "Connection and passive observation must remain unreachable while field authority is locked."
        )
        XCTAssertFalse(
            app.buttons["Scan for scooter"].exists,
            "The old generic manual-candidate scan must not become a fallback physical path."
        )
        XCTAssertFalse(
            app.buttons["Start passive capture"].exists,
            "Standalone capture cannot bypass field authorization or Experiment One authority binding."
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["es80.capture.start"].exists,
            "No hidden Start Capture action may bypass the Experiment One authority boundary."
        )
        XCTAssertFalse(
            app.buttons["Finish Capture"].exists,
            "Finish cannot exist before field authorization and accepted Horizon/seal authority."
        )
        XCTAssertFalse(
            app.buttons["Share Capture"].exists,
            "Final software export must not surface as a share action before a legitimate Experiment One artifact has been sealed."
        )
        XCTAssertFalse(
            app.buttons["Retry Share Preparation"].exists,
            "Share retry belongs only to a sealed-artifact completion state and must not become a NO-GO bypass."
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
        attachment.name = "Nembra Capture V14 — Package-Owned Physical NO-GO"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
