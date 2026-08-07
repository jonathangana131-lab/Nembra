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
        let confirmedLightOn = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "Light", "On")
        ).firstMatch
        XCTAssertTrue(
            confirmedLightOn.waitForExistence(timeout: 3),
            "The light control must expose the scooter-confirmed On state after acknowledgement."
        )

        let drive = app.buttons["home.mode.drive"]
        XCTAssertTrue(drive.exists)
        drive.tap()

        let confirmedDriveMetric = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier == %@ AND value == %@",
                "home.metric.mode",
                "Drive"
            )
        ).firstMatch
        XCTAssertTrue(
            confirmedDriveMetric.waitForExistence(timeout: 3),
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
    func testReconnectDoesNotPromoteCachedBatteryToLive() {
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launch(scenario: "scooter-unavailable", orientation: .portrait)

        XCTAssertTrue(app.staticTexts["Scooter not found"].waitForExistence(timeout: 3))
        let reconnect = app.buttons["Reconnect scooter"]
        XCTAssertTrue(reconnect.exists)
        reconnect.tap()
        XCTAssertTrue(app.staticTexts["Connected"].waitForExistence(timeout: 4))

        XCUIDevice.shared.orientation = .landscapeRight
        let cockpit = app.descendants(matching: .any)["dashboard.cockpit"]
        XCTAssertTrue(cockpit.waitForExistence(timeout: 4))

        let battery = app.buttons["dashboard.battery"]
        XCTAssertTrue(battery.waitForExistence(timeout: 4))
        if (battery.value as? String)?.contains("Estimated range unavailable") == true {
            battery.tap()
        }
        XCTAssertTrue(
            waitForValue("71 percent, last known vehicle data", element: battery),
            "Reconnect must not promote cached 71% charge into live battery truth before field-specific current evidence exists."
        )
        keepScreenshot(named: "Dashboard Reconnected Cached Battery Landscape")
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
    func testLandscapeDashboardBatteryReadoutToggleFailsClosedWithoutRangeEstimate() {
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launch(scenario: "connected-stopped", orientation: .landscapeRight)

        let battery = app.buttons["dashboard.battery"]
        XCTAssertTrue(battery.waitForExistence(timeout: 4))
        assertMinimumTouchTarget(battery, named: "Dashboard battery")

        // AppStorage deliberately remembers this user-facing preference across
        // launches. Normalize the starting presentation without assuming test
        // execution order, then prove range mode fails closed when no estimate
        // has been supplied by the app integration. VehicleState battery does
        // not carry field-specific freshness yet, so it remains last-known even
        // in a connected fixture until the accepted battery live-truth bridge exists.
        if (battery.value as? String)?.contains("Estimated range unavailable") == true {
            battery.tap()
            XCTAssertTrue(waitForValue("92 percent, last known vehicle data", element: battery))
        } else {
            XCTAssertTrue(waitForValue("92 percent, last known vehicle data", element: battery))
        }

        battery.tap()
        XCTAssertTrue(
            waitForValue(
                "Estimated range unavailable, battery charge is last known vehicle data",
                element: battery
            ),
            "Range mode must not synthesize mileage or promote unqualified battery data into live truth."
        )
        keepScreenshot(named: "Dashboard Estimated Range Unavailable Landscape")

        // Prove the user-facing choice is actually durable, not merely local
        // SwiftUI state. Relaunching the same installed app must preserve range
        // mode through AppStorage.
        app.terminate()
        app.launch()
        let relaunchedBattery = app.buttons["dashboard.battery"]
        XCTAssertTrue(relaunchedBattery.waitForExistence(timeout: 4))
        XCTAssertTrue(
            waitForValue(
                "Estimated range unavailable, battery charge is last known vehicle data",
                element: relaunchedBattery
            ),
            "The stored battery/range presentation preference must survive app relaunch without changing battery currentness."
        )

        // Restore the stable percentage preference for following UI tests.
        relaunchedBattery.tap()
        XCTAssertTrue(waitForValue("92 percent, last known vehicle data", element: relaunchedBattery))
    }

    @MainActor
    func testLandscapeDashboardRetainedBatteryIsAnnouncedAsLastKnown() {
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launch(scenario: "scooter-unavailable", orientation: .landscapeRight)

        let battery = app.buttons["dashboard.battery"]
        XCTAssertTrue(battery.waitForExistence(timeout: 4))

        // The unavailable-scooter fixture intentionally retains the last
        // confirmed 71% vehicle state. Presentation preference is persistent,
        // so normalize to percentage before validating stale-data wording.
        if (battery.value as? String)?.contains("Estimated range unavailable") == true {
            battery.tap()
        }
        XCTAssertTrue(
            waitForValue("71 percent, last known vehicle data", element: battery),
            "Retained battery charge must never be announced as live telemetry."
        )

        battery.tap()
        XCTAssertTrue(
            waitForValue(
                "Estimated range unavailable, battery charge is last known vehicle data",
                element: battery
            ),
            "Range mode must preserve retained-battery provenance while remaining unavailable."
        )

        // Restore percentage for deterministic following tests.
        battery.tap()
        XCTAssertTrue(waitForValue("71 percent, last known vehicle data", element: battery))
    }

    @MainActor
    func testLandscapeDashboardBatteryControlDisablesWithoutDisplaySOC() {
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launch(scenario: "cold-disconnected", orientation: .landscapeRight)

        let battery = app.buttons["dashboard.battery"]
        XCTAssertTrue(battery.waitForExistence(timeout: 4))
        XCTAssertFalse(
            battery.isEnabled,
            "With no legitimate display SoC, the readout must not offer a meaningless percentage/range toggle."
        )

        let value = battery.value as? String
        XCTAssertTrue(
            value == "Unavailable" || value == "Estimated range unavailable",
            "A no-SoC state must remain explicitly unavailable regardless of the persisted presentation preference."
        )
        keepScreenshot(named: "Dashboard Battery Unavailable Landscape")
    }

    @MainActor
    func testLandscapeDashboardLowBatteryWarningRemainsAccessibleInBothModes() {
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launch(scenario: "low-battery", orientation: .landscapeRight)

        let battery = app.buttons["dashboard.battery"]
        XCTAssertTrue(battery.waitForExistence(timeout: 4))

        if (battery.value as? String)?.contains("Estimated range unavailable") == true {
            battery.tap()
        }
        XCTAssertTrue(
            waitForValue("14 percent, last known vehicle data, low battery", element: battery),
            "The low-battery warning must remain accessible without promoting legacy VehicleState charge into verified-live truth."
        )

        battery.tap()
        XCTAssertTrue(
            waitForValue(
                "Estimated range unavailable, battery charge is last known vehicle data, low battery",
                element: battery
            ),
            "Range mode must retain both the fail-closed currentness qualifier and low-battery warning."
        )
        keepScreenshot(named: "Dashboard Low Battery Range Unavailable Landscape")

        battery.tap()
        XCTAssertTrue(waitForValue("14 percent, last known vehicle data, low battery", element: battery))
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
