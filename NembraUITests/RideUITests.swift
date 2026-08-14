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
    func testCompletedRideAppearsWithDurableRouteThroughRealRidePipeline() {
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

        let rowValue = row.value as? String ?? ""
        XCTAssertTrue(
            row.label.localizedCaseInsensitiveContains("Ride on"),
            "A completed ride row must expose one concise Nembra-owned ride identity."
        )
        XCTAssertFalse(
            rowValue.localizedCaseInsensitiveContains("Completed ride"),
            "A normal completed ride must not repeat its identity inside the accessibility value."
        )
        XCTAssertFalse(
            rowValue.localizedCaseInsensitiveContains("recovered after relaunch"),
            "The uninterrupted QA ride must not claim recovered continuity."
        )
        keepScreenshot(named: "Completed Ride History")

        row.tap()
        let detail = app.descendants(matching: .any)["rides.detail"]
        XCTAssertTrue(detail.waitForExistence(timeout: 3))

        let odometer = app.descendants(matching: .any)["rides.evidence.odometer"]
        XCTAssertTrue(odometer.exists)
        let odometerSemantics = "\(odometer.label) \(odometer.value as? String ?? "")"
        XCTAssertTrue(
            odometerSemantics.contains("mi") || odometerSemantics.contains("km"),
            "The completed ride must expose measured odometer distance evidence in the active locale."
        )
        XCTAssertFalse(
            odometerSemantics.contains("0.0"),
            "The end-to-end QA fixture must establish the ride baseline before advancing odometer evidence."
        )

        let routeMap = app.descendants(matching: .any)["rides.route-map"]
        if !routeMap.waitForExistence(timeout: 3) {
            app.swipeUp()
        }
        XCTAssertTrue(
            routeMap.waitForExistence(timeout: 3),
            "The explicit QA route fixture must pass through RideRouteRecorder, exact durable route storage, and MapKit presentation."
        )
        XCTAssertEqual(
            routeMap.label,
            "Recorded ride route",
            "The persisted route visualization must expose the Nembra-owned route identity instead of relying on MapKit internals."
        )
        let routeSemantics = routeMap.value as? String ?? ""
        XCTAssertTrue(
            routeSemantics.localizedCaseInsensitiveContains("Route coverage partial"),
            "This fixture starts route recording after ride activation, so accessibility must preserve partial-coverage truth."
        )
        XCTAssertTrue(
            routeSemantics.localizedCaseInsensitiveContains("4 recorded points"),
            "Route accessibility must report the four points actually persisted by the explicit QA fixture."
        )
        XCTAssertTrue(
            routeSemantics.localizedCaseInsensitiveContains("no known route gaps recorded"),
            "Partial coverage without an explicit internal segment gap must not invent a known route gap."
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["rides.route-unavailable"].exists,
            "A ride with verified persisted route geometry must not fall back to the no-route state."
        )
        keepScreenshot(named: "Completed Ride Details With Route")
    }

    @MainActor
    func testCompletedRideDetailDarkAppearancePreservesRouteAndBottomControl() {
        let previousAppearance = XCUIDevice.shared.appearance
        defer {
            XCUIDevice.shared.appearance = previousAppearance
            XCUIDevice.shared.orientation = .portrait
        }

        XCUIDevice.shared.orientation = .portrait
        XCUIDevice.shared.appearance = .dark

        let app = XCUIApplication()
        app.launchEnvironment["NEMBRA_SIMULATION_SCENARIO"] = "riding"
        app.launchEnvironment["NEMBRA_SIMULATION_STORAGE_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["NEMBRA_SIMULATION_AUTOCOMPLETE_RIDE"] = "1"
        app.launch()

        let ridesTab = app.tabBars.buttons["Rides"]
        XCTAssertTrue(ridesTab.waitForExistence(timeout: 5))
        ridesTab.tap()

        let row = app.descendants(matching: .any)["rides.completed-row"]
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        row.tap()

        let detail = app.descendants(matching: .any)["rides.detail"]
        XCTAssertTrue(detail.waitForExistence(timeout: 3))

        let routeMap = app.descendants(matching: .any)["rides.route-map"]
        if !routeMap.waitForExistence(timeout: 3) {
            app.swipeUp()
        }
        XCTAssertTrue(routeMap.waitForExistence(timeout: 3))
        XCTAssertEqual(routeMap.label, "Recorded ride route")
        XCTAssertTrue(
            (routeMap.value as? String ?? "").localizedCaseInsensitiveContains("Route coverage partial"),
            "Dark appearance must preserve the same accepted partial-route semantics as light appearance."
        )
        XCTAssertFalse(app.descendants(matching: .any)["rides.route-unavailable"].exists)
        keepScreenshot(named: "Completed Ride Details Dark")

        let recordingDetails = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", "Recording details")
        ).firstMatch
        if !recordingDetails.waitForExistence(timeout: 2) || !recordingDetails.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(
            recordingDetails.waitForExistence(timeout: 3),
            "The final Ride Details control must remain reachable in dark appearance."
        )
        XCTAssertTrue(
            recordingDetails.isHittable,
            "The floating shell chrome must not make the final Ride Details control inoperable."
        )
        keepScreenshot(named: "Completed Ride Details Dark Bottom")
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
