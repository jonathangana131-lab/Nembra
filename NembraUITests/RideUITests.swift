import XCTest

final class RideUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        executionTimeAllowance = 120
    }

    @MainActor
    func testAutomaticRideSurvivesProcessRelaunchWithSameDurableIdentity() {
        XCUIDevice.shared.orientation = .portrait

        let app = XCUIApplication()
        app.launchEnvironment["NEMBRA_SIMULATION_SCENARIO"] = "riding"
        app.launchEnvironment["NEMBRA_SIMULATION_STORAGE_NAMESPACE"] = UUID().uuidString
        app.launch()

        let rideStatus = app.descendants(matching: .any)["home.ride-status"]
        XCTAssertTrue(rideStatus.waitForExistence(timeout: 5))
        XCTAssertTrue(
            waitForValue("Riding automatically", element: rideStatus, timeout: 5),
            "A fresh authoritative Simulator packet should drive the real automatic ride path."
        )
        keepScreenshot(named: "Automatic Ride Active Home")

        app.terminate()
        app.launch()

        let recoveredStatus = app.descendants(matching: .any)["home.ride-status"]
        XCTAssertTrue(recoveredStatus.waitForExistence(timeout: 5))
        XCTAssertTrue(
            waitForValue("Ride resumed", element: recoveredStatus, timeout: 6),
            "A process relaunch must restore the durable ride and resume it after fresh evidence."
        )
        keepScreenshot(named: "Automatic Ride Recovered Home")
    }

    @MainActor
    func testCompletedRideAppearsInHistoryThroughRealRidePipeline() {
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
            row.waitForExistence(timeout: 8),
            "The explicit QA auto-completion must flow through RideEngine, durable history commit, and the real Rides surface."
        )
        keepScreenshot(named: "Completed Ride History")

        row.tap()
        let detail = app.descendants(matching: .any)["rides.detail"]
        XCTAssertTrue(detail.waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["rides.evidence.odometer"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["rides.route-unavailable"].exists)
        keepScreenshot(named: "Completed Ride Details")
    }

    @MainActor
    private func waitForValue(
        _ value: String,
        element: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        let predicate = NSPredicate(format: "value == %@", value)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    private func keepScreenshot(named name: String) {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
