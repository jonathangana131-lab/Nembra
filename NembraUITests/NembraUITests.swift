import XCTest

final class NembraUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testColdLaunchShowsSimulatorVehicle() {
        let app = launch(scenario: "connected-stopped")

        XCTAssertTrue(app.staticTexts["Nembra Simulator"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Connected"].exists)
        keepScreenshot(named: "Cold Launch Connected")
    }

    @MainActor
    func testBluetoothOffBlocksReconnectWithoutInventingLiveState() {
        let app = launch(scenario: "bluetooth-off")

        XCTAssertTrue(app.staticTexts["Bluetooth is off"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Reconnect scooter"].exists)
        keepScreenshot(named: "Bluetooth Off")
    }

    @MainActor
    func testPermissionDeniedOffersSettingsInsteadOfFakeReconnect() {
        let app = launch(scenario: "permission-denied")

        XCTAssertTrue(app.staticTexts["Bluetooth access is off"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Open Nembra settings"].exists)
        XCTAssertFalse(app.buttons["Reconnect scooter"].exists)
    }

    @MainActor
    func testUnavailableScooterCanRecoverWithoutInventingLiveState() {
        let app = launch(scenario: "scooter-unavailable")

        XCTAssertTrue(app.staticTexts["Scooter not found"].waitForExistence(timeout: 3))
        let reconnect = app.buttons["Reconnect scooter"]
        XCTAssertTrue(reconnect.exists)
        reconnect.tap()
        XCTAssertTrue(app.staticTexts["Connected"].waitForExistence(timeout: 4))
    }

    @MainActor
    func testLandscapeDashboardIsDedicatedCockpitAndHidesMovingControls() {
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launch(scenario: "riding", orientation: .landscapeRight)

        let cockpit = app.descendants(matching: .any)["dashboard.cockpit"]
        XCTAssertTrue(cockpit.waitForExistence(timeout: 4))
        XCTAssertFalse(app.tabBars.firstMatch.exists, "Landscape ride state should be a dedicated cockpit, not tab chrome.")

        let speed = app.descendants(matching: .any)["dashboard.speed"]
        XCTAssertTrue(speed.waitForExistence(timeout: 2))
        let speedValue = speed.value as? String ?? ""
        XCTAssertTrue(
            speedValue.localizedCaseInsensitiveContains("mph") || speedValue.localizedCaseInsensitiveContains("km/h"),
            "Speed accessibility value should include its unit."
        )
        XCTAssertTrue(app.staticTexts["RIDING"].exists)
        XCTAssertFalse(app.buttons["dashboard.control.lock"].exists)
        XCTAssertFalse(app.buttons["dashboard.control.light"].exists)

        keepScreenshot(named: "Dashboard Riding Landscape")
    }

    @MainActor
    func testLandscapeDashboardDisconnectedCachedSpeedProjectsUnavailable() {
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launch(
            scenario: "reconnecting",
            orientation: .landscapeRight,
            extraEnvironment: ["NEMBRA_SIMULATION_AUTOCONNECT": "0"]
        )

        let cockpit = app.descendants(matching: .any)["dashboard.cockpit"]
        XCTAssertTrue(cockpit.waitForExistence(timeout: 4))

        let speed = app.descendants(matching: .any)["dashboard.speed"]
        XCTAssertTrue(speed.waitForExistence(timeout: 2))
        XCTAssertTrue(
            (speed.value as? String ?? "").localizedCaseInsensitiveContains("unavailable"),
            "A disconnected cached speed must not remain display-authoritative."
        )
        XCTAssertTrue(
            app.staticTexts["NO LIVE SPEED"].waitForExistence(timeout: 2),
            "Disconnected transport must fail the field-specific speed projection closed."
        )
        XCTAssertFalse(app.staticTexts["READY"].exists)
        XCTAssertFalse(app.staticTexts["RIDING"].exists)
        XCTAssertFalse(app.buttons["dashboard.control.lock"].exists)
        XCTAssertFalse(app.buttons["dashboard.control.light"].exists)

        keepScreenshot(named: "Dashboard Disconnected Cached Speed Landscape")
    }

    @MainActor
    func testLandscapeDashboardNeverObservedSpeedIsUnavailableAndCapturable() {
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launch(scenario: "cold-disconnected", orientation: .landscapeRight)

        let cockpit = app.descendants(matching: .any)["dashboard.cockpit"]
        XCTAssertTrue(
            cockpit.waitForExistence(timeout: 4),
            "Landscape must still render the real Cockpit before any speed evidence exists."
        )

        let speed = app.descendants(matching: .any)["dashboard.speed"]
        XCTAssertTrue(speed.waitForExistence(timeout: 2))
        XCTAssertTrue(
            (speed.value as? String ?? "").localizedCaseInsensitiveContains("unavailable"),
            "No accepted speed evidence must remain explicitly unavailable rather than becoming zero."
        )
        XCTAssertTrue(
            app.staticTexts["NO LIVE SPEED"].waitForExistence(timeout: 2),
            "The Cockpit must not manufacture a numeric speed before any accepted source evidence exists."
        )
        XCTAssertFalse(app.staticTexts["LAST KNOWN"].exists)

        let vehicleStatus = app.descendants(matching: .any)["dashboard.vehicle-status"]
        XCTAssertTrue(vehicleStatus.waitForExistence(timeout: 2))
        let vehicleData = vehicleStatus.staticTexts["Vehicle data"]
        XCTAssertTrue(
            vehicleData.waitForExistence(timeout: 2),
            "Cold disconnected launch must expose the vehicle-data semantic status."
        )
        XCTAssertTrue(
            (vehicleData.value as? String ?? "").localizedCaseInsensitiveContains("no confirmed scooter telemetry"),
            "Cold disconnected launch must expose the no-telemetry vehicle state through the designed accessibility semantic."
        )
        XCTAssertFalse(app.buttons["dashboard.control.lock"].exists)
        XCTAssertFalse(app.buttons["dashboard.control.light"].exists)

        keepScreenshot(named: "Dashboard No Speed Evidence Landscape")
    }

    @MainActor
    func testLandscapeDashboardStoppedControlsConfirmEveryModePersonality() {
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launch(scenario: "connected-stopped", orientation: .landscapeRight)

        let cockpit = app.descendants(matching: .any)["dashboard.cockpit"]
        XCTAssertTrue(cockpit.waitForExistence(timeout: 4))

        let light = app.buttons["dashboard.control.light"]
        let lock = app.buttons["dashboard.control.lock"]
        assertMinimumTouchTarget(light, named: "Dashboard light")
        assertMinimumTouchTarget(lock, named: "Dashboard lock")

        let modeIdentifiers = [
            "dashboard.mode.walk",
            "dashboard.mode.eco",
            "dashboard.mode.drive",
            "dashboard.mode.sport"
        ]
        let expectedValues = ["Walk", "Eco", "Drive", "Sport"]
        for (identifier, expected) in zip(modeIdentifiers, expectedValues) {
            let button = app.buttons[identifier]
            XCTAssertTrue(button.waitForExistence(timeout: 2))
            button.tap()

            let mode = app.descendants(matching: .any)["dashboard.mode"]
            let predicate = NSPredicate(format: "value == %@", expected)
            expectation(for: predicate, evaluatedWith: mode)
            waitForExpectations(timeout: 2)
            keepScreenshot(named: "Dashboard \(expected) Landscape")
        }
    }

    @MainActor
    func testLandscapeDashboardRetainedSpeedTruthIsVisibleAndCapturable() {
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launch(
            scenario: "connected-stopped",
            orientation: .landscapeRight,
            extraEnvironment: ["NEMBRA_SIMULATION_SPEED_EVIDENCE_GAP": "1"]
        )

        let cockpit = app.descendants(matching: .any)["dashboard.cockpit"]
        XCTAssertTrue(cockpit.waitForExistence(timeout: 4))

        let speed = app.descendants(matching: .any)["dashboard.speed"]
        XCTAssertTrue(speed.waitForExistence(timeout: 2))
        XCTAssertTrue(
            (speed.value as? String ?? "").localizedCaseInsensitiveContains("last known"),
            "Retained source speed must be announced explicitly as last known."
        )
        XCTAssertTrue(app.staticTexts["LAST KNOWN"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["READY"].exists)
        XCTAssertFalse(app.staticTexts["RIDING"].exists)
        XCTAssertFalse(app.buttons["dashboard.control.lock"].exists)
        XCTAssertFalse(app.buttons["dashboard.control.light"].exists)

        keepScreenshot(named: "Dashboard Retained Speed Landscape")
    }

    @MainActor
    func testLandscapeDashboardLaunchPerformance() throws {
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launch(scenario: "connected-stopped", orientation: .landscapeRight, launchImmediately: false)

        measure(metrics: [XCTApplicationLaunchMetric()]) {
            app.launch()
            XCTAssertTrue(app.descendants(matching: .any)["dashboard.cockpit"].waitForExistence(timeout: 4))
            app.terminate()
        }
    }

    private func assertMinimumTouchTarget(_ element: XCUIElement, named name: String) {
        XCTAssertTrue(element.waitForExistence(timeout: 2), "\(name) control should exist")
        XCTAssertGreaterThanOrEqual(element.frame.width, 44, "\(name) must be at least 44pt wide")
        XCTAssertGreaterThanOrEqual(element.frame.height, 44, "\(name) must be at least 44pt high")
    }

    @MainActor
    private func launch(
        scenario: String,
        orientation: UIDeviceOrientation = .portrait,
        extraEnvironment: [String: String] = [:],
        launchImmediately: Bool = true
    ) -> XCUIApplication {
        XCUIDevice.shared.orientation = orientation
        let app = XCUIApplication()
        app.launchEnvironment["NEMBRA_SIMULATION"] = scenario
        app.launchEnvironment["NEMBRA_SIMULATION_STORAGE_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["NEMBRA_SIMULATION_AUTOCONNECT"] = "1"
        for (key, value) in extraEnvironment {
            app.launchEnvironment[key] = value
        }
        if launchImmediately {
            app.launch()
        }
        return app
    }

    private func keepScreenshot(named name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

final class RideUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAutomaticRideSurvivesProcessRelaunchWithSameDurableIdentity() {
        let namespace = UUID().uuidString
        let app = launchRideApp(namespace: namespace, autoComplete: false)

        XCTAssertTrue(app.descendants(matching: .any)["home.ride-status"].waitForExistence(timeout: 5))
        let activeStatus = app.descendants(matching: .any)["home.ride-status"]
        let activePredicate = NSPredicate(format: "value == %@", "Riding automatically")
        expectation(for: activePredicate, evaluatedWith: activeStatus)
        waitForExpectations(timeout: 3)
        keepScreenshot(named: "Automatic Ride Active Home")

        app.terminate()
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["home.ride-status"].waitForExistence(timeout: 5))
        let recoveredStatus = app.descendants(matching: .any)["home.ride-status"]
        let recoveredPredicate = NSPredicate(format: "value == %@", "Ride resumed")
        expectation(for: recoveredPredicate, evaluatedWith: recoveredStatus)
        waitForExpectations(timeout: 3)
        keepScreenshot(named: "Automatic Ride Recovered Home")
    }

    @MainActor
    func testCompletedRideAppearsWithDurableRouteThroughRealRidePipeline() {
        let namespace = UUID().uuidString
        let app = launchRideApp(namespace: namespace, autoComplete: true)

        let ridesTab = app.buttons["Rides"]
        XCTAssertTrue(ridesTab.waitForExistence(timeout: 5))
        ridesTab.tap()

        let completedRide = app.descendants(matching: .any)["rides.completed-row"]
        XCTAssertTrue(completedRide.waitForExistence(timeout: 8))
        keepScreenshot(named: "Completed Ride History")
        completedRide.tap()

        XCTAssertTrue(app.descendants(matching: .any)["rides.detail"].waitForExistence(timeout: 3))
        let odometer = app.descendants(matching: .any)["rides.evidence.odometer"]
        XCTAssertTrue(odometer.exists)
        XCTAssertFalse((odometer.value as? String ?? "").isEmpty)

        let routeMap = app.descendants(matching: .any)["rides.route-map"]
        XCTAssertTrue(routeMap.waitForExistence(timeout: 3))
        XCTAssertFalse(app.descendants(matching: .any)["rides.route-unavailable"].exists)
        keepScreenshot(named: "Completed Ride Details With Route")
    }

    @MainActor
    private func launchRideApp(namespace: String, autoComplete: Bool) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["NEMBRA_SIMULATION"] = "riding"
        app.launchEnvironment["NEMBRA_SIMULATION_STORAGE_NAMESPACE"] = namespace
        app.launchEnvironment["NEMBRA_SIMULATION_AUTOCONNECT"] = "1"
        app.launchEnvironment["NEMBRA_SIMULATION_AUTOCOMPLETE_RIDE"] = autoComplete ? "1" : "0"
        app.launch()
        return app
    }

    private func keepScreenshot(named name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
