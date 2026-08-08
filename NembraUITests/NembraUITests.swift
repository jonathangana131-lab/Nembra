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
        XCTAssertTrue(
            waitForEnabled(drive),
            "Drive must become actionable after the prior confirmed command fully clears."
        )
        drive.tap()

        let confirmedDriveMetric = app.descendants(matching: .any)["home.metric.mode"]
        XCTAssertTrue(confirmedDriveMetric.waitForExistence(timeout: 3))
        XCTAssertTrue(
            waitForValue("Drive", element: confirmedDriveMetric),
            "The status metric must expose the scooter-confirmed Drive mode, not merely a tapped segment."
        )

        let lock = button(containing: "Lock", in: app)
        XCTAssertTrue(lock.exists)
        XCTAssertTrue(
            waitForEnabled(lock),
            "Lock must become actionable after the confirmed mode command fully clears."
        )
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
        XCTAssertTrue(app.staticTexts["Vehicle configuration"].waitForExistence(timeout: 2))
        assertMinimumTouchTarget(app.buttons["vehicle-controls.mode.drive"], named: "Vehicle Controls Drive mode")
        keepScreenshot(named: "Vehicle Controls Connected")
    }

    @MainActor
    func testVehicleControlsUnavailableVisualTruth() {
        let app = launch(scenario: "scooter-unavailable", orientation: .portrait)

        XCTAssertTrue(app.staticTexts["Scooter not found"].waitForExistence(timeout: 3))
        let controls = app.buttons["Vehicle controls"]
        XCTAssertTrue(controls.waitForExistence(timeout: 2))
        controls.tap()

        XCTAssertTrue(app.navigationBars["Vehicle Controls"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Vehicle configuration"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Scooter not found"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Last confirmed settings shown below"].waitForExistence(timeout: 2))

        let drive = app.buttons["vehicle-controls.mode.drive"]
        if drive.waitForExistence(timeout: 1) {
            XCTAssertFalse(drive.isEnabled, "Vehicle mode controls must stay unavailable while the scooter is not connected.")
            XCTAssertEqual(drive.value as? String, "Last confirmed selection")
        }

        keepScreenshot(named: "Vehicle Controls Scooter Unavailable")
    }

    @MainActor
    func testVehicleControlsPrimaryES80UnverifiedVisualTruth() {
        let app = launchProduction(orientation: .portrait)

        XCTAssertTrue(app.staticTexts["AOVOPRO ES80"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Scooter software not recognized"].waitForExistence(timeout: 3))

        let controls = app.buttons["Vehicle controls"]
        XCTAssertTrue(controls.waitForExistence(timeout: 2))
        controls.tap()

        XCTAssertTrue(app.navigationBars["Vehicle Controls"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["AOVOPRO ES80"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Vehicle configuration"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Controls unavailable"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["This vehicle configuration is not verified for control commands."].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["Reconnect"].exists, "Unverified ES80 production state must not offer a fake reconnect-to-controls path.")
        XCTAssertFalse(
            app.descendants(matching: .any)["vehicle-controls.retained-state"].exists,
            "An ordinary unverified ES80 launch has no confirmed vehicle session to label as retained."
        )

        let cruiseOn = app.buttons["vehicle-controls.cruise.on"]
        if cruiseOn.waitForExistence(timeout: 1) {
            XCTAssertFalse(cruiseOn.isEnabled, "Unverified ES80 cruise controls must remain read-only.")
        }
        let zeroStart = app.buttons["vehicle-controls.start.zeroStart"]
        if zeroStart.waitForExistence(timeout: 1) {
            XCTAssertFalse(zeroStart.isEnabled, "Unverified ES80 start behavior controls must remain read-only.")
        }

        keepScreenshot(named: "Vehicle Controls AOVOPRO ES80 Unverified")
    }

    @MainActor
    func testVehicleControlsPrimaryES80RecomposesAtAccessibilityDynamicType() {
        let app = launchProduction(
            orientation: .portrait,
            contentSizeCategory: "UICTContentSizeCategoryAccessibilityXXXL"
        )

        XCTAssertTrue(app.staticTexts["AOVOPRO ES80"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Scooter software not recognized"].waitForExistence(timeout: 3))

        let controls = app.buttons["Vehicle controls"]
        XCTAssertTrue(controls.waitForExistence(timeout: 2))
        controls.tap()

        XCTAssertTrue(app.navigationBars["Vehicle Controls"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Controls unavailable"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["This vehicle configuration is not verified for control commands."].waitForExistence(timeout: 2))
        keepScreenshot(named: "Vehicle Controls AOVOPRO ES80 Accessibility XXXL Top")

        let cruiseOff = app.buttons["vehicle-controls.cruise.off"]
        let cruiseOn = app.buttons["vehicle-controls.cruise.on"]
        XCTAssertTrue(scrollToExistence(cruiseOff, in: app))
        XCTAssertTrue(scrollToExistence(cruiseOn, in: app))
        XCTAssertFalse(cruiseOff.isEnabled)
        XCTAssertFalse(cruiseOn.isEnabled)
        XCTAssertGreaterThan(
            cruiseOn.frame.minY,
            cruiseOff.frame.maxY,
            "Accessibility Dynamic Type must stack ES80 Cruise controls vertically instead of preserving the compact adaptive row."
        )

        keepScreenshot(named: "Vehicle Controls AOVOPRO ES80 Accessibility XXXL Controls")
    }

    @MainActor
    func testVehicleControlsUnavailableRecoveryRecomposesAtAccessibilityDynamicType() {
        let app = launch(
            scenario: "scooter-unavailable",
            orientation: .portrait,
            contentSizeCategory: "UICTContentSizeCategoryAccessibilityXXXL"
        )

        XCTAssertTrue(app.staticTexts["Scooter not found"].waitForExistence(timeout: 4))
        let controls = app.buttons["Vehicle controls"]
        XCTAssertTrue(controls.waitForExistence(timeout: 2))
        controls.tap()

        XCTAssertTrue(app.navigationBars["Vehicle Controls"].waitForExistence(timeout: 2))
        let recoveryMessage = app.staticTexts["Keep the scooter powered on and nearby, then try again."]
        let reconnect = app.buttons["Reconnect"]
        XCTAssertTrue(recoveryMessage.waitForExistence(timeout: 2))
        XCTAssertTrue(reconnect.waitForExistence(timeout: 2))
        XCTAssertGreaterThan(
            reconnect.frame.minY,
            recoveryMessage.frame.maxY,
            "Accessibility Dynamic Type must place the recovery action below the complete issue prose instead of squeezing both into one row."
        )
        XCTAssertTrue(app.staticTexts["Last confirmed settings shown below"].waitForExistence(timeout: 2))
        keepScreenshot(named: "Vehicle Controls Scooter Unavailable Accessibility XXXL Top")

        let walk = app.buttons["vehicle-controls.mode.walk"]
        let eco = app.buttons["vehicle-controls.mode.eco"]
        XCTAssertTrue(scrollToExistence(walk, in: app))
        XCTAssertTrue(scrollToExistence(eco, in: app))
        XCTAssertGreaterThan(
            eco.frame.minY,
            walk.frame.maxY,
            "Accessibility Dynamic Type must stack Ride Mode controls in one column."
        )

        keepScreenshot(named: "Vehicle Controls Scooter Unavailable Accessibility XXXL Controls")
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
        orientation: UIDeviceOrientation,
        contentSizeCategory: String? = nil
    ) -> XCUIApplication {
        XCUIDevice.shared.orientation = orientation
        let app = XCUIApplication()
        app.launchEnvironment["NEMBRA_SIMULATION_SCENARIO"] = scenario
        applyContentSizeCategory(contentSizeCategory, to: app)
        app.launch()
        return app
    }

    @MainActor
    private func launchProduction(
        orientation: UIDeviceOrientation,
        contentSizeCategory: String? = nil
    ) -> XCUIApplication {
        XCUIDevice.shared.orientation = orientation
        let app = XCUIApplication()
        applyContentSizeCategory(contentSizeCategory, to: app)
        app.launch()
        return app
    }

    @MainActor
    private func applyContentSizeCategory(_ contentSizeCategory: String?, to app: XCUIApplication) {
        guard let contentSizeCategory else { return }
        // Validation-only Simulator override already used by Nembra's Home visual QA.
        // It changes presentation only and never enters vehicle/simulation truth.
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName",
            contentSizeCategory
        ]
    }

    @MainActor
    private func scrollToExistence(
        _ element: XCUIElement,
        in app: XCUIApplication,
        maxSwipes: Int = 4
    ) -> Bool {
        if element.exists { return true }
        for _ in 0..<maxSwipes {
            app.swipeUp()
            if element.exists { return true }
        }
        return false
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
    private func waitForEnabled(_ element: XCUIElement, timeout: TimeInterval = 3) -> Bool {
        let predicate = NSPredicate(format: "enabled == true")
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
