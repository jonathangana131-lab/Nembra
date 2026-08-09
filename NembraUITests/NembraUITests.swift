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
    func testCaptureCriticalSimulatorStatesPassSystemAccessibilityAudit() throws {
        let scenarios = [
            "stationaryPreflight",
            "observationHorizonReady",
            "captureComplete",
            "foregroundInterrupted"
        ]

        for scenario in scenarios {
            let app = XCUIApplication()
            app.launchArguments = [
                "--es80-passive-capture-simulator-qa",
                "--es80-capture-qa-scenario=\(scenario)"
            ]
            app.launch()

            let expectedRootIdentifier = scenario == "stationaryPreflight"
                ? "es80.capture.stationary-preflight"
                : "es80.capture-shell"
            XCTAssertTrue(
                app.descendants(matching: .any)[expectedRootIdentifier].waitForExistence(timeout: 5),
                "Capture accessibility audit scenario \(scenario) must render its real Capture root."
            )
            XCTAssertTrue(
                app.descendants(matching: .any)["es80.capture.simulator-qa"].waitForExistence(timeout: 3),
                "Capture accessibility audit scenario \(scenario) must remain visibly synthetic and non-authorizing."
            )

            try app.performAccessibilityAudit()

            if scenario == "stationaryPreflight" {
                let chargerDisconnected = app.buttons["es80.capture.preflight.charger-disconnected"]
                XCTAssertTrue(
                    chargerDisconnected.waitForExistence(timeout: 2),
                    "Stationary preflight must expose the explicit charger-disconnected declaration."
                )
                chargerDisconnected.tap()

                let continueButton = app.buttons["es80.capture.preflight.continue"]
                XCTAssertTrue(continueButton.waitForExistence(timeout: 2))
                XCTAssertTrue(
                    continueButton.isEnabled,
                    "Declaring charger disconnected must unlock the stationary preflight continuation."
                )
                continueButton.tap()

                XCTAssertTrue(
                    app.descendants(matching: .any)["es80.capture-shell"].waitForExistence(timeout: 3),
                    "Stationary preflight must hand off into the real Capture shell."
                )
                XCTAssertTrue(
                    app.descendants(matching: .any)["es80.capture.simulator-qa"].waitForExistence(timeout: 2),
                    "The selected synthetic QA snapshot must survive the preflight-to-shell handoff."
                )

                let confirmSetup = app.buttons["es80.capture.confirm-setup"]
                XCTAssertTrue(
                    confirmSetup.waitForExistence(timeout: 2),
                    "The retained stationary fixture must map to the OFF 1 setup-confirmation phase."
                )
                confirmSetup.tap()

                let beginOff1 = app.buttons["es80.capture.begin-window"]
                XCTAssertTrue(beginOff1.waitForExistence(timeout: 2))
                XCTAssertEqual(
                    beginOff1.label,
                    "Begin OFF 1 check",
                    "After the setup declaration, the retained fixture must expose OFF 1 rather than a generic locked shell."
                )

                try app.performAccessibilityAudit()
                keepScreenshot(named: "Capture Stationary Preflight to OFF 1 Synthetic")
            }

            app.terminate()
        }
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
        for identifier in modeIdentifiers {
            assertMinimumTouchTarget(app.buttons[identifier], named: identifier)
        }

        let confirmedMode = app.descendants(matching: .any)["dashboard.mode"]
        XCTAssertTrue(confirmedMode.waitForExistence(timeout: 2))
        XCTAssertTrue(waitForValue("Sport", element: confirmedMode))
        keepScreenshot(named: "Dashboard Sport Landscape")

        selectDashboardMode(
            identifier: "dashboard.mode.walk",
            expectedValue: "Walk",
            screenshotName: "Dashboard Walk Landscape",
            in: app,
            confirmedMode: confirmedMode
        )
        selectDashboardMode(
            identifier: "dashboard.mode.eco",
            expectedValue: "Eco",
            screenshotName: "Dashboard Eco Landscape",
            in: app,
            confirmedMode: confirmedMode
        )
        selectDashboardMode(
            identifier: "dashboard.mode.drive",
            expectedValue: "Drive",
            screenshotName: "Dashboard Drive Landscape",
            in: app,
            confirmedMode: confirmedMode
        )
        selectDashboardMode(
            identifier: "dashboard.mode.sport",
            expectedValue: "Sport",
            screenshotName: "Dashboard Sport Confirmed Landscape",
            in: app,
            confirmedMode: confirmedMode
        )
    }

    @MainActor
    private func selectDashboardMode(
        identifier: String,
        expectedValue: String,
        screenshotName: String,
        in app: XCUIApplication,
        confirmedMode: XCUIElement
    ) {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitForExistence(timeout: 2))
        button.tap()
        XCTAssertTrue(
            waitForValue(expectedValue, element: confirmedMode),
            "Dashboard personality must follow the scooter-confirmed \(expectedValue) mode, not the tapped button alone."
        )
        keepScreenshot(named: screenshotName)
    }

    @MainActor
    private func assertMinimumTouchTarget(
        _ element: XCUIElement,
        named name: String,
        minimum: CGFloat = 44,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(element.waitForExistence(timeout: 2), "\(name) control must exist.", file: file, line: line)
        XCTAssertGreaterThanOrEqual(
            element.frame.width,
            minimum,
            "\(name) touch target width must be at least \(minimum) pt.",
            file: file,
            line: line
        )
        XCTAssertGreaterThanOrEqual(
            element.frame.height,
            minimum,
            "\(name) touch target height must be at least \(minimum) pt.",
            file: file,
            line: line
        )
    }

    @MainActor
    private func launch(
        scenario: String,
        orientation: UIDeviceOrientation
    ) -> XCUIApplication {
        XCUIDevice.shared.orientation = orientation
        let app = XCUIApplication()
        app.launchEnvironment["NEMBRA_SIMULATION_SCENARIO"] = scenario
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
