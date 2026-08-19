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

        let modeSelector = app.buttons["home.mode.selector"]
        XCTAssertTrue(modeSelector.waitForExistence(timeout: 3))
        XCTAssertTrue(
            swipeUpUntilHittable(modeSelector, in: app),
            "The identified Home controls rail must scroll clear of the floating tab chrome."
        )

        let light = button(containing: "Light", in: app)
        XCTAssertTrue(light.waitForExistence(timeout: 2))
        XCTAssertTrue(light.isHittable)
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

        modeSelector.tap()

        let drive = app.sheets.buttons["Drive"]
        XCTAssertTrue(drive.waitForExistence(timeout: 2))
        drive.tap()

        XCTAssertTrue(
            waitForLabelContaining("Drive", element: app.buttons["home.mode.selector"]),
            "The mode control must expose the scooter-confirmed Drive mode, not merely a tapped dialog choice."
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
        XCTAssertTrue(controls.waitForExistence(timeout: 2))
        XCTAssertTrue(
            swipeDownUntilHittable(controls, in: app),
            "The Vehicle controls link must remain reachable after operating the lower Home controls."
        )
        controls.tap()
        XCTAssertTrue(app.navigationBars["Vehicle"].waitForExistence(timeout: 2))
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
    func testSelectedPortraitSurfacesCaptureSimulatorOnlyEvidence() {
        let previousAppearance = XCUIDevice.shared.appearance
        defer {
            XCUIDevice.shared.orientation = .portrait
            XCUIDevice.shared.appearance = previousAppearance
        }

        XCUIDevice.shared.appearance = .dark
        let app = launch(scenario: "connected-stopped", orientation: .portrait)

        XCTAssertTrue(app.descendants(matching: .any)["home.energy-hero"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Nembra Simulator"].waitForExistence(timeout: 3))

        let battery = app.buttons["home.metric.battery"]
        assertMinimumTouchTarget(battery, named: "Home battery and range")
        var initialBatterySemantics = semantics(of: battery)
        if !initialBatterySemantics.localizedCaseInsensitiveContains("Battery percentage emphasized") {
            battery.tap()
            XCTAssertTrue(
                waitForSemanticChange(
                    identifier: "home.metric.battery",
                    from: initialBatterySemantics,
                    in: app
                )
            )
            initialBatterySemantics = semantics(of: app.buttons["home.metric.battery"])
        }
        XCTAssertTrue(initialBatterySemantics.localizedCaseInsensitiveContains("Battery percentage emphasized"))
        XCTAssertTrue(initialBatterySemantics.localizedCaseInsensitiveContains("percent"))
        XCTAssertTrue(initialBatterySemantics.localizedCaseInsensitiveContains("range"))
        XCTAssertTrue(
            initialBatterySemantics.localizedCaseInsensitiveContains("unavailable"),
            "Simulator display-only battery evidence must not mint a learned numeric range."
        )

        battery.tap()
        XCTAssertTrue(
            waitForSemanticChange(
                identifier: "home.metric.battery",
                from: initialBatterySemantics,
                in: app
            ),
            "Home must toggle battery/range emphasis while keeping both values visible."
        )

        let toggledBattery = app.buttons["home.metric.battery"]
        let toggledBatterySemantics = semantics(of: toggledBattery)
        XCTAssertTrue(toggledBatterySemantics.localizedCaseInsensitiveContains("percent"))
        XCTAssertTrue(toggledBatterySemantics.localizedCaseInsensitiveContains("range"))
        toggledBattery.tap()
        XCTAssertTrue(
            waitForSemanticChange(
                identifier: "home.metric.battery",
                from: toggledBatterySemantics,
                in: app
            ),
            "The same Home control must return to its prior persisted emphasis."
        )
        XCTAssertEqual(
            semantics(of: app.buttons["home.metric.battery"]),
            initialBatterySemantics
        )

        keepScreenshot(named: "Selected Portrait Home - Simulator QA Only")

        selectTab("Rides", destinationIdentifier: "rides.mileage-activity", in: app)
        keepScreenshot(named: "Selected Portrait Rides - Simulator QA Only")

        selectTab("Vehicle", destinationIdentifier: "vehicle-controls.status", in: app)
        XCTAssertTrue(
            app.descendants(matching: .any)["vehicle-controls.battery-range"].waitForExistence(timeout: 3)
        )
        keepScreenshot(named: "Selected Portrait Vehicle - Simulator QA Only")

        selectTab("Settings", destinationIdentifier: "settings.surface", in: app)
        keepScreenshot(named: "Selected Portrait Settings - Simulator QA Only")
    }

    @MainActor
    func testPassiveLandscapeLeftAndRightNeverAuthorizeHorizonAndRestorePortraitHome() {
        defer { XCUIDevice.shared.orientation = .portrait }

        let app = launch(scenario: "connected-stopped", orientation: .portrait)
        let homeEntry = app.buttons["home.horizon-entry"]
        XCTAssertTrue(homeEntry.waitForExistence(timeout: 5))

        for orientation in [UIDeviceOrientation.landscapeLeft, .landscapeRight] {
            XCUIDevice.shared.orientation = orientation

            XCTAssertTrue(
                waitForPassivePortraitOwnership(in: app, timeout: 8),
                "A passive \(orientation) change must return the exact Home scene to portrait without authorizing Horizon."
            )
            XCTAssertFalse(
                app.descendants(matching: .any)["dashboard.cockpit"].exists,
                "Device orientation is observation only and must never authorize Horizon."
            )
            XCTAssertFalse(
                app.descendants(matching: .any)["home.orientation.failure"].exists,
                "Home portrait ownership should recover without leaving a failure prompt."
            )
            XCTAssertTrue(homeEntry.waitForExistence(timeout: 3))
        }
    }

    @MainActor
    func testHorizonV4DriveEntryTruthAndPortraitRestoration() {
        let previousAppearance = XCUIDevice.shared.appearance
        defer {
            XCUIDevice.shared.orientation = .portrait
            XCUIDevice.shared.appearance = previousAppearance
        }

        XCUIDevice.shared.appearance = .dark
        let app = launch(scenario: "riding", orientation: .portrait)
        enterHorizon(in: app)

        let cockpit = app.descendants(matching: .any)["dashboard.cockpit"]
        XCTAssertTrue(cockpit.waitForExistence(timeout: 8))
        XCTAssertTrue(
            waitForLandscapeWindow(in: app, timeout: 8),
            "Horizon must appear only after the requested landscape geometry is observed."
        )

        let qaDisclosure = app.descendants(matching: .any)["dashboard.qa-disclosure"]
        XCTAssertTrue(qaDisclosure.waitForExistence(timeout: 3))
        XCTAssertTrue(
            (qaDisclosure.value as? String ?? "").localizedCaseInsensitiveContains("synthetic evidence"),
            "The screenshot fixture must remain visibly and semantically simulator-only."
        )

        let speed = app.descendants(matching: .any)["dashboard.speed"]
        XCTAssertTrue(speed.waitForExistence(timeout: 3))
        let speedValue = speed.value as? String ?? ""
        XCTAssertTrue(speedValue.localizedCaseInsensitiveContains("Simulator QA"))
        XCTAssertFalse(speedValue.localizedCaseInsensitiveContains("unavailable"))

        let propulsion = app.descendants(matching: .any)["dashboard.energy-rail"]
        XCTAssertTrue(propulsion.waitForExistence(timeout: 3))
        XCTAssertTrue(
            (propulsion.value as? String ?? "").localizedCaseInsensitiveContains("accepted watts"),
            "V4 Drive must expose accepted simulator power without relabeling it as throttle."
        )

        for identifier in [
            "dashboard.today",
            "dashboard.ride-time",
            "dashboard.odometer",
            "dashboard.city-explored",
            "dashboard.recording-status"
        ] {
            XCTAssertTrue(
                app.descendants(matching: .any)[identifier].waitForExistence(timeout: 3),
                "Missing Horizon truth surface: \(identifier)"
            )
        }

        let windowFrame = app.windows.firstMatch.frame
        for identifier in ["dashboard.speed", "dashboard.energy-rail"] {
            let element = app.descendants(matching: .any)[identifier]
            XCTAssertTrue(
                windowFrame.contains(element.frame),
                "\(identifier) must remain fully inside the iPhone 12 landscape window."
            )
        }

        let home = app.buttons["dashboard.control.home"]
        let navigate = app.buttons["dashboard.control.navigate"]
        assertMinimumTouchTarget(home, named: "Horizon Home")
        assertMinimumTouchTarget(navigate, named: "Horizon Navigate")

        let battery = app.buttons["dashboard.battery-range"]
        XCTAssertTrue(battery.waitForExistence(timeout: 3))
        if !battery.label.localizedCaseInsensitiveContains("Battery") {
            battery.tap()
            XCTAssertTrue(waitForLabelContaining("Battery", element: app.buttons["dashboard.battery-range"]))
        }

        keepScreenshot(named: "Horizon V4 Drive - Simulator QA Only")

        let initialBatterySemantics = semantics(of: app.buttons["dashboard.battery-range"])
        app.buttons["dashboard.battery-range"].tap()
        XCTAssertTrue(
            waitForSemanticChange(
                identifier: "dashboard.battery-range",
                from: initialBatterySemantics,
                in: app
            ),
            "The battery control must switch percentage/range semantics while its fill remains SOC."
        )

        home.tap()
        XCTAssertTrue(
            waitForPortraitWindow(in: app, timeout: 8),
            "The cockpit Home control must restore the owned portrait session."
        )
        XCTAssertTrue(app.buttons["home.horizon-entry"].waitForExistence(timeout: 5))
        XCTAssertFalse(cockpit.exists)
    }

    @MainActor
    func testHorizonV4DriveBatteryToggleHitchEvidence() {
        let previousAppearance = XCUIDevice.shared.appearance
        defer {
            XCUIDevice.shared.orientation = .portrait
            XCUIDevice.shared.appearance = previousAppearance
        }

        XCUIDevice.shared.appearance = .dark
        let app = launch(scenario: "riding", orientation: .portrait)
        enterHorizon(in: app)

        XCTAssertTrue(app.descendants(matching: .any)["dashboard.cockpit"].waitForExistence(timeout: 8))
        XCTAssertTrue(waitForLandscapeWindow(in: app, timeout: 8))
        XCTAssertTrue(app.buttons["dashboard.battery-range"].waitForExistence(timeout: 3))

        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [XCTHitchMetric(application: app)], options: options) {
            let battery = app.buttons["dashboard.battery-range"]
            let before = semantics(of: battery)
            battery.tap()
            XCTAssertTrue(
                waitForSemanticChange(
                    identifier: "dashboard.battery-range",
                    from: before,
                    in: app,
                    timeout: 3
                )
            )
        }

        app.buttons["dashboard.control.home"].tap()
        XCTAssertTrue(waitForPortraitWindow(in: app, timeout: 8))
    }

    @MainActor
    func testHorizonV4DriveSustainedRenderIslandHitchEvidence() {
        let previousAppearance = XCUIDevice.shared.appearance
        defer {
            XCUIDevice.shared.orientation = .portrait
            XCUIDevice.shared.appearance = previousAppearance
        }

        XCUIDevice.shared.appearance = .dark
        let app = launch(
            scenario: "riding",
            orientation: .portrait,
            environment: ["NEMBRA_SIMULATION_DASHBOARD_RENDER_STRESS": "1"]
        )
        enterHorizon(in: app)

        XCTAssertTrue(app.descendants(matching: .any)["dashboard.cockpit"].waitForExistence(timeout: 8))
        XCTAssertTrue(waitForLandscapeWindow(in: app, timeout: 8))

        let qaDisclosure = app.descendants(matching: .any)["dashboard.qa-disclosure"]
        XCTAssertTrue(qaDisclosure.waitForExistence(timeout: 3))
        XCTAssertTrue(
            (qaDisclosure.value as? String ?? "").localizedCaseInsensitiveContains("synthetic evidence"),
            "The performance fixture must remain visibly and semantically Simulator-only."
        )

        let speed = app.descendants(matching: .any)["dashboard.speed"]
        let power = app.descendants(matching: .any)["dashboard.energy-rail"]
        XCTAssertTrue(speed.waitForExistence(timeout: 3))
        XCTAssertTrue(power.waitForExistence(timeout: 3))
        XCTAssertTrue(
            waitForSustainedDashboardUpdates(speed: speed, power: power, requiredChanges: 3),
            "The Simulator stress fixture must prove both source-backed render islands are advancing before measurement."
        )

        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTHitchMetric(application: app)], options: options) {
            // Keep XCUI accessibility queries outside the measured interval. The
            // app's independently clocked synthetic source continues offering
            // broad state updates throughout this fixed six-second window.
            let intervalFinished = XCTestExpectation(description: "Six-second Dashboard render-stress interval")
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                intervalFinished.fulfill()
            }
            XCTAssertEqual(
                XCTWaiter.wait(for: [intervalFinished], timeout: 7),
                .completed
            )
        }

        XCTAssertTrue(
            waitForSustainedDashboardUpdates(speed: speed, power: power, requiredChanges: 3),
            "Synthetic speed and accepted-power source updates must still advance after all measured intervals."
        )

        keepScreenshot(named: "Horizon V4 Drive Render Stress - Simulator QA Only")

        app.buttons["dashboard.control.home"].tap()
        XCTAssertTrue(waitForPortraitWindow(in: app, timeout: 8))
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
        app.launchEnvironment["NEMBRA_SIMULATION_STORAGE_NAMESPACE"] = UUID().uuidString
        for (key, value) in environment {
            app.launchEnvironment[key] = value
        }
        app.launch()
        return app
    }

    @MainActor
    private func enterHorizon(in app: XCUIApplication) {
        let entry = app.buttons["home.horizon-entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        if !entry.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(entry.isHittable)
        entry.tap()
    }

    @MainActor
    private func selectTab(
        _ name: String,
        destinationIdentifier: String,
        in app: XCUIApplication
    ) {
        let tab = app.tabBars.buttons[name]
        XCTAssertTrue(tab.waitForExistence(timeout: 3), "Missing \(name) tab.")
        tab.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)[destinationIdentifier].waitForExistence(timeout: 6),
            "The \(name) tab did not expose \(destinationIdentifier)."
        )
    }

    @MainActor
    private func waitForLandscapeWindow(
        in app: XCUIApplication,
        timeout: TimeInterval
    ) -> Bool {
        waitForWindowGeometry(in: app, timeout: timeout) { $0.width > $0.height }
    }

    @MainActor
    private func waitForPortraitWindow(
        in app: XCUIApplication,
        timeout: TimeInterval
    ) -> Bool {
        waitForWindowGeometry(in: app, timeout: timeout) { $0.height > $0.width }
    }

    @MainActor
    private func waitForWindowGeometry(
        in app: XCUIApplication,
        timeout: TimeInterval,
        predicate: (CGRect) -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let window = app.windows.firstMatch
            if window.exists, predicate(window.frame) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline
        return false
    }

    @MainActor
    private func waitForPassivePortraitOwnership(
        in app: XCUIApplication,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var portraitStableSince: Date?

        repeat {
            if app.descendants(matching: .any)["dashboard.cockpit"].exists {
                return false
            }
            if app.descendants(matching: .any)["home.orientation.failure"].exists {
                return false
            }

            let window = app.windows.firstMatch
            let homeEntry = app.buttons["home.horizon-entry"]
            if window.exists,
               window.frame.height > window.frame.width,
               homeEntry.exists {
                if portraitStableSince == nil {
                    portraitStableSince = .now
                }
                if let portraitStableSince,
                   Date().timeIntervalSince(portraitStableSince) >= 0.75 {
                    return true
                }
            } else {
                portraitStableSince = nil
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline
        return false
    }

    @MainActor
    private func waitForSemanticChange(
        identifier: String,
        from original: String,
        in app: XCUIApplication,
        timeout: TimeInterval = 3
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let element = app.buttons[identifier]
            if element.exists, semantics(of: element) != original {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline
        return false
    }

    @MainActor
    private func semantics(of element: XCUIElement) -> String {
        "\(element.label)|\(element.value as? String ?? "")"
    }

    @MainActor
    private func waitForSustainedDashboardUpdates(
        speed: XCUIElement,
        power: XCUIElement,
        requiredChanges: Int,
        timeout: TimeInterval = 3
    ) -> Bool {
        guard requiredChanges > 0, speed.exists, power.exists else { return false }

        let deadline = Date().addingTimeInterval(timeout)
        var previousSpeed = semantics(of: speed)
        var previousPower = semantics(of: power)
        var speedChanges = 0
        var powerChanges = 0

        repeat {
            let currentSpeed = semantics(of: speed)
            if currentSpeed != previousSpeed {
                previousSpeed = currentSpeed
                speedChanges += 1
            }

            let currentPower = semantics(of: power)
            if currentPower != previousPower {
                previousPower = currentPower
                powerChanges += 1
            }

            if speedChanges >= requiredChanges, powerChanges >= requiredChanges {
                return true
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        } while Date() < deadline

        return false
    }

    @MainActor
    private func swipeUpUntilHittable(
        _ element: XCUIElement,
        in app: XCUIApplication,
        maximumAttempts: Int = 4
    ) -> Bool {
        scrollUntilHittable(
            element,
            maximumAttempts: maximumAttempts,
            swipe: { app.swipeUp() }
        )
    }

    @MainActor
    private func swipeDownUntilHittable(
        _ element: XCUIElement,
        in app: XCUIApplication,
        maximumAttempts: Int = 4
    ) -> Bool {
        scrollUntilHittable(
            element,
            maximumAttempts: maximumAttempts,
            swipe: { app.swipeDown() }
        )
    }

    @MainActor
    private func scrollUntilHittable(
        _ element: XCUIElement,
        maximumAttempts: Int,
        swipe: () -> Void
    ) -> Bool {
        guard element.waitForExistence(timeout: 2) else { return false }
        if element.isHittable { return true }

        for _ in 0..<maximumAttempts {
            swipe()
            if element.waitForExistence(timeout: 1), element.isHittable {
                return true
            }
        }

        return element.exists && element.isHittable
    }

    @MainActor
    private func assertMinimumTouchTarget(
        _ element: XCUIElement,
        named name: String,
        minimum: CGFloat = 44,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(element.waitForExistence(timeout: 3), "\(name) must exist.", file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.width, minimum, file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.height, minimum, file: file, line: line)
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
    private func waitForLabelContaining(
        _ value: String,
        element: XCUIElement,
        timeout: TimeInterval = 3
    ) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@", value)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}
