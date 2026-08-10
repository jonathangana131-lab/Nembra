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

        XCTAssertTrue(app.staticTexts["Nembra Simulator"].waitForExistence(timeout: 3))

        let light = button(containing: "Light", in: app)
        XCTAssertTrue(light.waitForExistence(timeout: 2))
        XCTAssertTrue(light.label.contains("Off"))
        light.tap()

        // XCUIElement may retain the pre-command accessibility snapshot after
        // SwiftUI replaces the button label. Re-query the semantic post-command
        // state instead of weakening confirmation with a sleep or stale handle.
        let enabledLight = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "Light", "On")
        ).firstMatch
        XCTAssertTrue(
            enabledLight.waitForExistence(timeout: 3),
            "The light control must expose the simulator-confirmed On state after acknowledgement."
        )

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
    func testLandscapeDashboardIsDedicatedCockpitAndHidesMovingControls() {
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launch(scenario: "riding", orientation: .landscapeRight)

        let cockpit = app.descendants(matching: .any)["dashboard.cockpit"]
        XCTAssertTrue(cockpit.waitForExistence(timeout: 4))

        let speed = app.descendants(matching: .any)["dashboard.speed"]
        XCTAssertTrue(speed.waitForExistence(timeout: 3))
        XCTAssertFalse((speed.value as? String ?? "").isEmpty)

        assertEnergyRailValue(
            containing: "356 watts",
            in: app,
            message: "Simulator riding power must reach the mounted Energy Rail as accepted Simulator-only semantic truth."
        )

        XCTAssertTrue(app.staticTexts["Controls available when stopped"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["dashboard.control.lock"].exists)
        XCTAssertFalse(app.buttons["dashboard.control.light"].exists)

        keepScreenshot(named: "Dashboard Riding Landscape")
    }

    @MainActor
    func testLandscapeDashboardRetainedSpeedTruthIsVisibleAndCapturable() {
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launch(
            scenario: "connected-stopped",
            orientation: .landscapeRight,
            environment: ["NEMBRA_SIMULATION_SPEED_EVIDENCE_GAP": "1"]
        )

        let cockpit = app.descendants(matching: .any)["dashboard.cockpit"]
        XCTAssertTrue(
            cockpit.waitForExistence(timeout: 4),
            "Landscape must keep the real Cockpit visible while speed evidence is retained."
        )

        let speed = app.descendants(matching: .any)["dashboard.speed"]
        XCTAssertTrue(speed.waitForExistence(timeout: 2))
        XCTAssertTrue(
            (speed.value as? String ?? "").localizedCaseInsensitiveContains("last known"),
            "A connected source gap must present the accepted speed as last-known, not live or unavailable."
        )
        XCTAssertTrue(
            app.staticTexts["LAST KNOWN"].waitForExistence(timeout: 2),
            "Retained speed evidence must carry an explicit last-known visual qualifier."
        )
        XCTAssertFalse(app.staticTexts["READY"].exists)
        XCTAssertFalse(app.staticTexts["RIDING"].exists)
        XCTAssertTrue(
            app.descendants(matching: .any)["dashboard.controls-speed-unavailable-message"]
                .waitForExistence(timeout: 2),
            "A connected speed gap must retire stopped-control authority while preserving retained presentation."
        )

        // Speed currentness is deliberately independent from propulsion currentness.
        // This fixture gaps only speed, so the accepted connected Simulator power
        // observation remains a separately current zero-watt measurement.
        assertEnergyRailValue(
            containing: "0 watts",
            in: app,
            message: "A retained speed sample must not falsely demote independently live Simulator power."
        )

        XCTAssertFalse(app.buttons["dashboard.control.lock"].exists)
        XCTAssertFalse(app.buttons["dashboard.control.light"].exists)

        keepScreenshot(named: "Dashboard Retained Speed Landscape")
    }

    @MainActor
    func testLandscapeDashboardRetainedPowerAfterReconnectIsExplicitLastKnown() {
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launch(
            scenario: "riding",
            orientation: .landscapeRight,
            environment: ["NEMBRA_SIMULATION_RETAINED_POWER_AFTER_RECONNECT": "1"]
        )

        let cockpit = app.descendants(matching: .any)["dashboard.cockpit"]
        XCTAssertTrue(
            cockpit.waitForExistence(timeout: 4),
            "The real Cockpit must remain mounted across the retained-power reconnect fixture."
        )

        // The visual subtree is intentionally replaced by one stable accessibility
        // representation, so automation asserts the semantic last-known contract
        // here and the keep-always screenshot is the visual acceptance evidence.
        assertEnergyRailValue(
            containing: "356 watts, last known",
            in: app,
            message: "Reconnect without a new source power receipt must preserve exact 356 W evidence as retained, never live."
        )

        keepScreenshot(named: "Dashboard Retained Power Landscape")
    }

    @MainActor
    func testLandscapeDashboardDisconnectedCachedSpeedProjectsUnavailable() {
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launch(scenario: "scooter-unavailable", orientation: .landscapeRight)

        let cockpit = app.descendants(matching: .any)["dashboard.cockpit"]
        XCTAssertTrue(
            cockpit.waitForExistence(timeout: 4),
            "Landscape must still render the real Cockpit when transport is unavailable."
        )

        let speed = app.descendants(matching: .any)["dashboard.speed"]
        XCTAssertTrue(speed.waitForExistence(timeout: 2))
        XCTAssertTrue(
            (speed.value as? String ?? "").localizedCaseInsensitiveContains("unavailable"),
            "A disconnected cached speed must not bypass app projection and become retained/current speed authority."
        )
        XCTAssertTrue(
            app.staticTexts["NO LIVE SPEED"].waitForExistence(timeout: 2),
            "Disconnected transport must fail the field-specific speed projection closed."
        )
        assertEnergyRailValue(
            containing: "Unavailable",
            in: app,
            message: "Disconnected cached aggregate state must not manufacture source-owned power or a numeric zero."
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

        assertEnergyRailValue(
            containing: "Unavailable",
            in: app,
            message: "No observed propulsion evidence must keep the Energy Rail explicitly unavailable."
        )

        let vehicleStatus = app.descendants(matching: .any)["dashboard.vehicle-status"]
        XCTAssertTrue(vehicleStatus.waitForExistence(timeout: 2))
        let dataStatus = vehicleStatus.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", "Vehicle data")
        ).firstMatch
        XCTAssertTrue(
            dataStatus.waitForExistence(timeout: 2),
            "Cold disconnected launch must expose the no-telemetry vehicle-data semantic."
        )
        XCTAssertTrue(
            (dataStatus.value as? String ?? "")
                .localizedCaseInsensitiveContains("no confirmed scooter telemetry"),
            "Cold disconnected launch must identify vehicle telemetry as not yet confirmed."
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
    func testLandscapeDashboardLaunchPerformance() {
        defer { XCUIDevice.shared.orientation = .portrait }
        XCUIDevice.shared.orientation = .landscapeRight

        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)]) {
            let app = XCUIApplication()
            app.launchEnvironment["NEMBRA_SIMULATION_SCENARIO"] = "connected-stopped"
            app.launch()

            XCTAssertTrue(
                app.descendants(matching: .any)["dashboard.cockpit"].waitForExistence(timeout: 4),
                "Launch measurement is valid only when the real landscape Cockpit becomes responsive."
            )
            app.terminate()
        }
    }

    @MainActor
    func testLandscapeDashboardSustainedSpeedPowerStressMetrics() {
        defer { XCUIDevice.shared.orientation = .portrait }
        XCUIDevice.shared.orientation = .landscapeRight

        let app = XCUIApplication()
        app.launchEnvironment["NEMBRA_SIMULATION_SCENARIO"] = "riding"
        app.launchEnvironment["NEMBRA_SIMULATION_DASHBOARD_STRESS"] = "1"
        app.launchEnvironment["NEMBRA_SIMULATION_STORAGE_NAMESPACE"] = "dashboard-performance-stress"
        app.launch()

        let cockpit = app.descendants(matching: .any)["dashboard.cockpit"]
        XCTAssertTrue(
            cockpit.waitForExistence(timeout: 4),
            "Sustained performance evidence is valid only when the real landscape Cockpit is mounted."
        )

        let energyRail = app.descendants(matching: .any)["dashboard.energy-rail"]
        XCTAssertTrue(
            energyRail.waitForExistence(timeout: 2),
            "The sustained performance run must exercise the real mounted Energy Rail."
        )
        let initialPowerValue = energyRail.value as? String ?? ""
        let sourceMoved = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value != %@", initialPowerValue),
            object: energyRail
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [sourceMoved], timeout: 2),
            .completed,
            "The performance window must begin only after fresh synthetic speed/power source receipts are actively retargeting the cockpit."
        )

        let options = XCTMeasureOptions()
        // XCTest executes one warm-up plus one recorded iteration when this is 1.
        // The app stress fixture runs long enough to cover both 3-second windows.
        options.iterationCount = 1

        measure(
            metrics: [
                XCTHitchMetric(application: app),
                XCTCPUMetric(application: app),
                XCTMemoryMetric(application: app)
            ],
            options: options
        ) {
            Thread.sleep(forTimeInterval: 3)
        }

        XCTAssertTrue(
            energyRail.exists,
            "The measured cockpit must remain mounted for the whole sustained stress interval."
        )
        keepScreenshot(named: "Dashboard Sustained Stress Landscape")
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
    private func assertEnergyRailValue(
        containing expectedFragment: String,
        in app: XCUIApplication,
        message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let energyRail = app.descendants(matching: .any)["dashboard.energy-rail"]
        XCTAssertTrue(
            energyRail.waitForExistence(timeout: 2),
            "The Energy Rail accessibility surface must be mounted in the real Dashboard cockpit.",
            file: file,
            line: line
        )
        XCTAssertTrue(
            waitForValueContaining(expectedFragment, element: energyRail),
            message,
            file: file,
            line: line
        )
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
        orientation: UIDeviceOrientation,
        environment: [String: String] = [:]
    ) -> XCUIApplication {
        XCUIDevice.shared.orientation = orientation
        let app = XCUIApplication()
        app.launchEnvironment["NEMBRA_SIMULATION_SCENARIO"] = scenario
        for (key, value) in environment {
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
    private func waitForValue(_ value: String, element: XCUIElement, timeout: TimeInterval = 3) -> Bool {
        let predicate = NSPredicate(format: "value == %@", value)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    private func waitForValueContaining(
        _ fragment: String,
        element: XCUIElement,
        timeout: TimeInterval = 3
    ) -> Bool {
        let predicate = NSPredicate(format: "value CONTAINS[c] %@", fragment)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}