import XCTest

final class NembraUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        // The xcode-27 hosted runner can spend ~40s establishing the very first
        // UI automation session. Keep assertion-level waits tight, but give the
        // test process enough total time so runner bootstrap is not mistaken for
        // an app hang.
        executionTimeAllowance = 120
    }

    @MainActor
    func testConnectedHomeControlsConfirmStateAndNavigate() {
        let app = launch(scenario: "connected-stopped", orientation: .portrait)

        XCTAssertTrue(app.staticTexts["MAXSHOT V1S Pro"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.descendants(matching: .any)["home.currentRide"].exists)

        let light = button(containing: "Light", in: app)
        XCTAssertTrue(light.waitForExistence(timeout: 2))
        XCTAssertTrue(light.label.contains("Off"))
        light.tap()
        XCTAssertTrue(waitForLabelFragment("On", element: light))

        let drive = app.buttons["home.mode.drive"]
        XCTAssertTrue(drive.exists)
        drive.tap()

        let confirmedDriveMetric = app.descendants(matching: .any)["home.metric.mode"]
        XCTAssertTrue(confirmedDriveMetric.waitForExistence(timeout: 3))
        XCTAssertTrue(
            waitForValue("Drive", element: confirmedDriveMetric),
            "The status metric must expose the scooter-confirmed Drive mode, not merely a tapped segment."
        )

        let lock = button(containing: "Lock", in: app)
        XCTAssertTrue(lock.exists)
        lock.tap()
        let confirmLock = app.sheets.buttons["Lock"]
        XCTAssertTrue(confirmLock.waitForExistence(timeout: 2))
        confirmLock.tap()

        let securedLock = button(containing: "Secured", in: app)
        XCTAssertTrue(
            securedLock.waitForExistence(timeout: 3),
            "The lock control must expose the scooter-confirmed secured state after acknowledgement."
        )

        let controls = app.buttons["Vehicle controls"]
        XCTAssertTrue(controls.exists)
        controls.tap()
        XCTAssertTrue(app.navigationBars["Vehicle Controls"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testHomeShowsCurrentRideOnlyAfterRideEngineConfirmsRawMovement() {
        let app = launch(
            scenario: "connected-stopped",
            orientation: .portrait,
            extraEnvironment: [
                "NEMBRA_RIDE_QA_SCRIPT": "active",
                "NEMBRA_RIDE_QA_NAMESPACE": "ui-active-\(UUID().uuidString)"
            ]
        )

        let currentRide = app.descendants(matching: .any)["home.currentRide"]
        XCTAssertTrue(
            currentRide.waitForExistence(timeout: 6),
            "Home should expose a current ride only after the real RideEngine confirms the QA raw packets."
        )
        XCTAssertTrue(waitForLabelFragment("Ride active", element: currentRide, timeout: 3))
        XCTAssertTrue(currentRide.label.contains("Tracking automatically"))

        keepScreenshot(named: "Home Active Ride")
    }

    @MainActor
    func testUnavailableScooterCanRecoverWithoutInventingLiveState() {
        let app = launch(scenario: "scooter-unavailable", orientation: .portrait)

        XCTAssertTrue(app.staticTexts["Scooter not found"].waitForExistence(timeout: 3))
        let reconnect = app.buttons["Reconnect scooter"]
        XCTAssertTrue(reconnect.exists)
        reconnect.tap()
        XCTAssertTrue(app.staticTexts["Connected"].waitForExistence(timeout: 4))
    }

    @MainActor
    func testPermissionDeniedOffersSettingsInsteadOfFakeReconnect() {
        let app = launch(scenario: "permission-denied", orientation: .portrait)
        XCTAssertTrue(app.staticTexts["Bluetooth access is off"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Open Nembra settings"].exists)
        XCTAssertFalse(app.buttons["Reconnect scooter"].exists)
    }

    @MainActor
    func testLandscapeDashboardIsDedicatedCockpitAndHidesMovingControls() {
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launch(scenario: "riding", orientation: .landscapeRight)

        let cockpit = app.descendants(matching: .any)["dashboard.cockpit"]
        XCTAssertTrue(cockpit.waitForExistence(timeout: 4))

        let speed = app.descendants(matching: .any)["dashboard.speed"]
        XCTAssertTrue(speed.waitForExistence(timeout: 3))
        XCTAssertFalse((speed.value as? String ?? "").isEmpty)

        XCTAssertTrue(app.staticTexts["Controls available when stopped"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["dashboard.control.lock"].exists)
        XCTAssertFalse(app.buttons["dashboard.control.light"].exists)

        keepScreenshot(named: "Dashboard Riding Landscape")
    }

    @MainActor
    func testLandscapeDashboardStoppedControlsConfirmMode() {
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launch(scenario: "connected-stopped", orientation: .landscapeRight)

        let cockpit = app.descendants(matching: .any)["dashboard.cockpit"]
        XCTAssertTrue(cockpit.waitForExistence(timeout: 4))

        let sport = app.buttons["dashboard.mode.sport"]
        XCTAssertTrue(sport.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["dashboard.control.light"].exists)
        XCTAssertTrue(app.buttons["dashboard.control.lock"].exists)

        sport.tap()
        let confirmedMode = app.descendants(matching: .any)["dashboard.mode"]
        XCTAssertTrue(confirmedMode.waitForExistence(timeout: 2))
        XCTAssertTrue(
            waitForValue("Sport", element: confirmedMode),
            "Dashboard mode must change only after the simulated scooter confirms Sport."
        )

        keepScreenshot(named: "Dashboard Stopped Landscape")
    }

    @MainActor
    private func launch(
        scenario: String,
        orientation: UIDeviceOrientation,
        extraEnvironment: [String: String] = [:]
    ) -> XCUIApplication {
        XCUIDevice.shared.orientation = orientation
        let app = XCUIApplication()
        app.launchEnvironment["NEMBRA_SIMULATION_SCENARIO"] = scenario
        for (key, value) in extraEnvironment {
            app.launchEnvironment[key] = value
        }
        app.launch()
        return app
    }

    @MainActor
    private func keepScreenshot(named name: String) {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    private func button(containing fragment: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", fragment)).firstMatch
    }

    @MainActor
    private func waitForLabelFragment(_ fragment: String, element: XCUIElement, timeout: TimeInterval = 3) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@", fragment)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    private func waitForValue(_ value: String, element: XCUIElement, timeout: TimeInterval = 3) -> Bool {
        let predicate = NSPredicate(format: "value == %@", value)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}
