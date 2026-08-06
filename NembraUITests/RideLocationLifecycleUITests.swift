import XCTest

final class RideLocationLifecycleUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        executionTimeAllowance = 120
    }

    @MainActor
    func testCompletedRideShowsVisiblyNonzeroGPSAndDurableRoute() {
        XCUIDevice.shared.orientation = .portrait

        let app = XCUIApplication()
        app.launchEnvironment["NEMBRA_SIMULATION_SCENARIO"] = "riding"
        app.launchEnvironment["NEMBRA_SIMULATION_STORAGE_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["NEMBRA_SIMULATION_AUTOCOMPLETE_RIDE"] = "1"
        app.launch()

        let ridesTab = app.tabBars.buttons["Rides"]
        XCTAssertTrue(ridesTab.waitForExistence(timeout: 5))
        ridesTab.tap()

        let row = app.descendants(matching: .any)["rides.completed-row"]
        XCTAssertTrue(
            row.waitForExistence(timeout: 12),
            "The deterministic QA ride must complete through RideEngine before GPS/route presentation is inspected."
        )
        row.tap()

        let detail = app.descendants(matching: .any)["rides.detail"]
        XCTAssertTrue(detail.waitForExistence(timeout: 3))

        let gps = app.descendants(matching: .any)["rides.evidence.gps"]
        XCTAssertTrue(gps.waitForExistence(timeout: 3))
        let gpsSemantics = "\(gps.label) \(gps.value as? String ?? "")"
        XCTAssertTrue(
            gpsSemantics.contains("mi") || gpsSemantics.contains("km"),
            "GPS evidence must expose a localized distance unit."
        )
        XCTAssertFalse(
            gpsSemantics.contains("0.0"),
            "Valid screened GPS evidence must be visually nonzero, not merely present internally and rounded away."
        )

        let routeMap = app.descendants(matching: .any)["rides.route-map"]
        if !routeMap.waitForExistence(timeout: 3) {
            app.swipeUp()
        }
        XCTAssertTrue(routeMap.waitForExistence(timeout: 3))
        XCTAssertFalse(app.descendants(matching: .any)["rides.route-unavailable"].exists)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Completed Ride Visible GPS And Route"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
