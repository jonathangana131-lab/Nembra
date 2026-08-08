import Foundation
import XCTest

final class ES80ResearchCaptureUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        executionTimeAllowance = 120
    }

    @MainActor
    func testPassiveResearchLaunchShowsProductCaptureShellWithoutVehicleControls() {
        let app = XCUIApplication()
        app.launchArguments = ["--es80-passive-capture"]
        app.launch()

        XCTAssertTrue(
            app.navigationBars["Nembra Capture"].waitForExistence(timeout: 5),
            "The explicit research launch must open the dedicated passive capture shell."
        )
        XCTAssertTrue(
            app.staticTexts["Passive evidence only"].waitForExistence(timeout: 3),
            "The capture shell must keep its passive-only truth boundary visible."
        )
        XCTAssertTrue(
            app.staticTexts
                .matching(NSPredicate(format: "label CONTAINS[c] %@", "foreground"))
                .firstMatch
                .waitForExistence(timeout: 3),
            "Foreground-only capture continuity must be disclosed before any physical research session starts."
        )
        XCTAssertTrue(
            app.buttons["Scan for scooter"].waitForExistence(timeout: 3),
            "Stationary setup must expose one obvious scan action even when Simulator Bluetooth cannot perform a physical scan."
        )
        XCTAssertFalse(
            app.buttons["Advanced details"].exists,
            "The product shell must not expose the package research console because that console owns independent scan/connect/export controls outside the shell lifecycle guard."
        )
        XCTAssertFalse(
            app.buttons["Vehicle controls"].exists,
            "Research capture must not silently start or expose the normal vehicle-control experience."
        )

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Nembra ES80 Capture Shell"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
