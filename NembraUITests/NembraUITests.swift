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

            XCTAssertTrue(
                app.descendants(matching: .any)["es80.capture-shell"].waitForExistence(timeout: 5),
                "Capture accessibility audit scenario \(scenario) must render the real Capture shell."
            )
            XCTAssertTrue(
                app.descendants(matching: .any)["es80.capture.simulator-qa"].waitForExistence(timeout: 3),
                "Capture accessibility audit scenario \(scenario) must remain visibly synthetic and non-authorizing."
            )

            try app.performAccessibilityAudit()
            app.terminate()
        }
    }

    @MainActor
    func testCaptureHorizonReadyRecomposesAtAccessibilityExtraExtraExtraLarge() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--es80-passive-capture-simulator-qa",
            "--es80-capture-qa-scenario=observationHorizonReady",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
        ]
        app.launch()

        let shell = app.descendants(matching: .any)["es80.capture-shell"]
        let disclosure = app.descendants(matching: .any)["es80.capture.simulator-qa"]
        let passiveMode = app.staticTexts["PASSIVE / READ ONLY"]
        let progress = app.descendants(matching: .any)["es80.capture.experiment-progress"]
        let health = app.descendants(matching: .any)["es80.capture.health"]
        let finish = app.descendants(matching: .any)["es80.capture.finish"]

        XCTAssertTrue(shell.waitForExistence(timeout: 5))
        XCTAssertTrue(disclosure.waitForExistence(timeout: 3))
        XCTAssertTrue(passiveMode.waitForExistence(timeout: 3))
        XCTAssertTrue(progress.waitForExistence(timeout: 3))
        XCTAssertTrue(health.waitForExistence(timeout: 3))
        XCTAssertTrue(finish.waitForExistence(timeout: 3))
        XCTAssertFalse(app.descendants(matching: .any)["es80.capture.field-no-go"].exists)
        XCTAssertFalse(app.buttons["Vehicle controls"].exists)

        assertVisibleInCurrentViewport(
            disclosure,
            app: app,
            context: "synthetic QA disclosure at Accessibility XXXL"
        )
        assertVisibleInCurrentViewport(
            passiveMode,
            app: app,
            context: "PASSIVE / READ ONLY hero state at Accessibility XXXL"
        )
        keepScreenshot(named: "Nembra Capture V14 — SIMULATOR QA — Hero — Accessibility XXXL")

        bringIntoCurrentViewport(
            progress,
            app: app,
            context: "paired Capture progress at Accessibility XXXL"
        )
        keepScreenshot(named: "Nembra Capture V14 — SIMULATOR QA — Progress — Accessibility XXXL")

        bringIntoCurrentViewport(
            health,
            app: app,
            context: "stacked Capture health at Accessibility XXXL"
        )
        keepScreenshot(named: "Nembra Capture V14 — SIMULATOR QA — Health — Accessibility XXXL")

        bringIntoCurrentViewport(
            finish,
            app: app,
            context: "Seal Capture action at Accessibility XXXL"
        )
        keepScreenshot(named: "Nembra Capture V14 — SIMULATOR QA — Seal — Accessibility XXXL")
    }

    @MainActor
    func testCaptureHorizonReadyProgressRemainsReviewableInLandscape() {
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }

        let app = XCUIApplication()
        app.launchArguments = [
            "--es80-passive-capture-simulator-qa",
            "--es80-capture-qa-scenario=observationHorizonReady"
        ]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["es80.capture-shell"].waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = .landscapeLeft

        let progress = app.descendants(matching: .any)["es80.capture.experiment-progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 3))
        XCTAssertFalse(app.descendants(matching: .any)["es80.capture.field-no-go"].exists)

        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThan(window.width, window.height, "Capture progress review must actually run in landscape.")
        bringIntoCurrentViewport(progress, app: app, context: "Capture progress in landscape")
        keepScreenshot(named: "Nembra Capture V14 — SIMULATOR QA — Progress — Landscape")
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
    private func bringIntoCurrentViewport(
        _ element: XCUIElement,
        app: XCUIApplication,
        context: String,
        maxSwipes: Int = 6,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            element.waitForExistence(timeout: 3),
            "Required \(context) must exist before viewport navigation.",
            file: file,
            line: line
        )

        var remaining = maxSwipes
        while remaining > 0 {
            if isVisibleInCurrentViewport(element, app: app) {
                return
            }
            app.swipeUp()
            remaining -= 1
        }

        assertVisibleInCurrentViewport(element, app: app, context: context, file: file, line: line)
    }

    @MainActor
    private func assertVisibleInCurrentViewport(
        _ element: XCUIElement,
        app: XCUIApplication,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let window = app.windows.firstMatch.frame
        let frame = element.frame
        XCTAssertGreaterThan(frame.width, 0, "Required \(context) must have positive width.", file: file, line: line)
        XCTAssertGreaterThan(frame.height, 0, "Required \(context) must have positive height.", file: file, line: line)
        XCTAssertGreaterThanOrEqual(frame.minX, window.minX - 1, "Required \(context) clips off the leading viewport edge.", file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxX, window.maxX + 1, "Required \(context) clips off the trailing viewport edge.", file: file, line: line)
        XCTAssertGreaterThanOrEqual(frame.minY, window.minY - 1, "Required \(context) clips above the viewport.", file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxY, window.maxY + 1, "Required \(context) clips below the viewport.", file: file, line: line)
    }

    @MainActor
    private func isVisibleInCurrentViewport(_ element: XCUIElement, app: XCUIApplication) -> Bool {
        let window = app.windows.firstMatch.frame
        let frame = element.frame
        return frame.width > 0
            && frame.height > 0
            && frame.minX >= window.minX - 1
            && frame.maxX <= window.maxX + 1
            && frame.minY >= window.minY - 1
            && frame.maxY <= window.maxY + 1
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
