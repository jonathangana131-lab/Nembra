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
        XCTAssertTrue(waitForPortraitWindow(in: app, timeout: 5))

        let qaDisclosure = app.descendants(matching: .any)["home.connection-status"]
        XCTAssertTrue(qaDisclosure.waitForExistence(timeout: 3))
        XCTAssertTrue(semantics(of: qaDisclosure).localizedCaseInsensitiveContains("SIM"))
        XCTAssertTrue(semantics(of: qaDisclosure).localizedCaseInsensitiveContains("synthetic evidence"))

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
    func testConnectedHomeInitialRailAndRideContinuationClearNativeTabWithoutScrolling() {
        let app = launch(scenario: "connected-stopped", orientation: .portrait)
        XCTAssertTrue(waitForPortraitWindow(in: app, timeout: 5))

        let light = button(containing: "Light", in: app)
        let lock = button(containing: "Lock", in: app)
        let mode = app.buttons["home.mode.selector"]
        let latest = app.descendants(matching: .any)["home.latest-ride.empty"]
        let tabBar = app.tabBars.firstMatch
        let window = app.windows.firstMatch

        for (element, name) in [(light, "Light"), (lock, "Lock"), (mode, "Mode")] {
            XCTAssertTrue(element.waitForExistence(timeout: 5), "Missing initial \(name) control.")
            XCTAssertTrue(element.isHittable, "Initial \(name) control must be operable without scrolling.")
        }
        XCTAssertTrue(
            latest.waitForExistence(timeout: 6),
            "A fresh connected-stopped namespace must settle on the honest empty latest-ride row."
        )
        XCTAssertTrue(tabBar.waitForExistence(timeout: 3))
        XCTAssertTrue(window.exists)

        let controlsFrame = light.frame.union(lock.frame).union(mode.frame)
            .insetBy(dx: -6, dy: -7)
        XCTAssertTrue(
            window.frame.contains(controlsFrame),
            "The complete 110-point control rail \(controlsFrame) must be inside the initial window \(window.frame)."
        )
        XCTAssertLessThanOrEqual(
            controlsFrame.maxY,
            tabBar.frame.minY - 8,
            "The complete control rail must clear native tab chrome at the untouched top scroll offset."
        )
        assertFullyInsideWindowAndAboveTabBar(
            latest,
            named: "Empty latest-ride row",
            in: app
        )
    }

    @MainActor
    func testConnectedHomePassesProductionAccessibilityAudit() throws {
        defer {
            if XCUIDevice.shared.orientation != .portrait {
                XCUIDevice.shared.orientation = .portrait
            }
        }

        let app = launch(scenario: "connected-stopped", orientation: .portrait)
        XCTAssertTrue(waitForPortraitWindow(in: app, timeout: 5))
        XCTAssertTrue(
            app.descendants(matching: .any)["home.latest-ride.empty"]
                .waitForExistence(timeout: 6),
            "The standard-size audit must run only after Home settles on its truthful empty-history state."
        )
        let vehicleControls = app.buttons["Vehicle controls"]
        XCTAssertTrue(vehicleControls.waitForExistence(timeout: 3))
        assertMinimumTouchTarget(vehicleControls, named: "Standard Home vehicle controls")

        try app.performAccessibilityAudit(
            for: [
                .sufficientElementDescription,
                .hitRegion,
                .contrast,
                .textClipped,
                .trait,
                .dynamicType
            ]
        )
    }

    @MainActor
    func testConnectedHomeAtAccessibilityXXXLKeepsTruthAndControlsReachable() {
        defer {
            if XCUIDevice.shared.orientation != .portrait {
                XCUIDevice.shared.orientation = .portrait
            }
        }

        let app = launch(
            scenario: "connected-stopped",
            orientation: .portrait,
            arguments: [
                "-UIPreferredContentSizeCategoryName",
                // This preference consumes UIKit's raw category identifier,
                // not the Swift symbol's expanded English case name.
                "UICTContentSizeCategoryAccessibilityXXXL"
            ]
        )
        XCTAssertTrue(waitForPortraitWindow(in: app, timeout: 5))

        let connection = app.descendants(matching: .any)["home.connection-status"]
        XCTAssertTrue(connection.waitForExistence(timeout: 5))
        let connectionSemantics = semantics(of: connection)
        XCTAssertTrue(connectionSemantics.localizedCaseInsensitiveContains("Connected"))
        XCTAssertTrue(
            connectionSemantics.localizedCaseInsensitiveContains("SIM, QA only, synthetic evidence"),
            "Accessibility XXXL evidence must remain explicitly Simulator-only."
        )

        let vehicleControls = app.buttons["Vehicle controls"]
        XCTAssertTrue(vehicleControls.waitForExistence(timeout: 3))
        XCTAssertGreaterThanOrEqual(
            vehicleControls.frame.minY,
            connection.frame.maxY,
            "Accessibility XXXL must activate Home's vertical vehicle-header reflow."
        )
        assertMinimumTouchTarget(vehicleControls, named: "Accessibility XXXL vehicle controls")
        XCTAssertTrue(vehicleControls.isHittable)

        let battery = app.buttons["home.metric.battery"]
        XCTAssertTrue(battery.waitForExistence(timeout: 3))
        let batterySemantics = semantics(of: battery)
        XCTAssertTrue(batterySemantics.localizedCaseInsensitiveContains("92 percent"))
        XCTAssertTrue(batterySemantics.localizedCaseInsensitiveContains("unavailable"))
        XCTAssertTrue(batterySemantics.localizedCaseInsensitiveContains("no learned range"))
        assertMinimumTouchTarget(battery, named: "Accessibility XXXL battery and range")
        XCTAssertTrue(battery.isHittable)

        let latest = app.descendants(matching: .any)["home.latest-ride.empty"]
        XCTAssertTrue(
            latest.waitForExistence(timeout: 6),
            "The fresh Simulator namespace must settle on the truthful empty latest-ride state."
        )
        keepScreenshot(named: "Home Accessibility XXXL Top - Simulator QA Only")

        let readiness = app.buttons["home.horizon-entry"]
        XCTAssertTrue(
            swipeUpUntilHittable(readiness, in: app, maximumAttempts: 6),
            "Accessibility XXXL readiness must remain scroll-reachable."
        )
        let readinessSemantics = semantics(of: readiness)
        XCTAssertTrue(readinessSemantics.localizedCaseInsensitiveContains("Open Horizon Dashboard"))
        XCTAssertTrue(readinessSemantics.localizedCaseInsensitiveContains("Automatic ride tracking"))
        XCTAssertTrue(readinessSemantics.localizedCaseInsensitiveContains("Vehicle: Connected"))
        assertMinimumTouchTarget(readiness, named: "Accessibility XXXL Horizon readiness")

        let light = button(containing: "Light", in: app)
        XCTAssertTrue(
            swipeUpUntilHittable(light, in: app, maximumAttempts: 6),
            "Accessibility XXXL Light must remain scroll-reachable."
        )
        XCTAssertTrue(semantics(of: light).localizedCaseInsensitiveContains("Light, Off"))
        assertMinimumTouchTarget(light, named: "Accessibility XXXL Light")

        let lock = button(containing: "Lock", in: app)
        XCTAssertTrue(
            swipeUpUntilHittable(lock, in: app, maximumAttempts: 6),
            "Accessibility XXXL Lock must remain scroll-reachable."
        )
        XCTAssertTrue(semantics(of: lock).localizedCaseInsensitiveContains("Lock, Ready"))
        assertMinimumTouchTarget(lock, named: "Accessibility XXXL Lock")

        let mode = app.buttons["home.mode.selector"]
        XCTAssertTrue(
            swipeUpUntilHittable(mode, in: app, maximumAttempts: 6),
            "Accessibility XXXL Mode must remain scroll-reachable."
        )
        let modeSemantics = semantics(of: mode)
        XCTAssertTrue(modeSemantics.localizedCaseInsensitiveContains("Mode"))
        XCTAssertTrue(modeSemantics.localizedCaseInsensitiveContains("Sport"))
        assertMinimumTouchTarget(mode, named: "Accessibility XXXL Mode")

        XCTAssertTrue(
            scrollFullyInsideWindowAndAboveTabBar(latest, in: app, maximumAttempts: 8),
            "Accessibility XXXL latest-ride content must scroll fully clear of native tab chrome."
        )
        let latestSemantics = semantics(of: latest)
        XCTAssertTrue(latestSemantics.localizedCaseInsensitiveContains("No completed rides yet"))
        XCTAssertTrue(latestSemantics.localizedCaseInsensitiveContains("safely saved"))
        assertFullyInsideWindowAndAboveTabBar(
            latest,
            named: "Accessibility XXXL latest-ride row",
            in: app
        )
        keepScreenshot(named: "Home Accessibility XXXL Bottom - Simulator QA Only")
    }

    @MainActor
    func testUnavailableScooterCanRecoverWithoutInventingLiveState() {
        let app = launch(scenario: "scooter-unavailable", orientation: .portrait)

        XCTAssertTrue(app.staticTexts["Scooter not found"].waitForExistence(timeout: 3))
        let reconnect = app.buttons["Reconnect scooter"]
        XCTAssertTrue(reconnect.exists)
        reconnect.tap()
        XCTAssertTrue(
            waitForSemanticsContaining(
                "Connected",
                identifier: "home.connection-status",
                in: app,
                timeout: 4
            )
        )
    }

    @MainActor
    func testPermissionDeniedOffersSettingsInsteadOfFakeReconnect() {
        let app = launch(scenario: "permission-denied", orientation: .portrait)
        XCTAssertTrue(app.staticTexts["Bluetooth access is off"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Open Nembra settings"].exists)
        XCTAssertFalse(app.buttons["Reconnect scooter"].exists)
    }

    @MainActor
    func testRetainedBatteryShowsOriginalFreshnessAndDisablesControls() throws {
        let app = launch(
            scenario: "connected-stopped",
            orientation: .portrait,
            environment: ["NEMBRA_SIMULATION_HOME_STATE_FIXTURE": "retain-after-live"]
        )

        XCTAssertTrue(
            waitForSemanticsContaining(
                "Reconnecting",
                identifier: "home.connection-status",
                in: app,
                timeout: 5
            )
        )
        let freshness = app.descendants(matching: .any)["home.battery.retained-freshness"]
        XCTAssertTrue(freshness.waitForExistence(timeout: 3))
        XCTAssertTrue(freshness.label.localizedCaseInsensitiveContains("Last confirmed"))

        let battery = app.buttons["home.metric.battery"]
        XCTAssertTrue(battery.waitForExistence(timeout: 3))
        let batterySemantics = semantics(of: battery)
        XCTAssertTrue(batterySemantics.localizedCaseInsensitiveContains("92 percent"))
        XCTAssertTrue(batterySemantics.localizedCaseInsensitiveContains("last known"))
        XCTAssertTrue(batterySemantics.localizedCaseInsensitiveContains("unavailable"))

        let modeSelector = app.buttons["home.mode.selector"]
        XCTAssertTrue(swipeUpUntilHittable(modeSelector, in: app))
        let light = button(containing: "Light", in: app)
        XCTAssertTrue(light.waitForExistence(timeout: 2))
        XCTAssertFalse(light.isEnabled)
        try app.performAccessibilityAudit(for: [.contrast])
        keepScreenshot(named: "Home Retained Battery - Simulator QA Only")
    }

    @MainActor
    func testLowBatteryHasVisibleNonColorWarning() throws {
        let app = launch(scenario: "low-battery", orientation: .portrait)

        let warning = app.descendants(matching: .any)["home.battery.low-warning"]
        XCTAssertTrue(warning.waitForExistence(timeout: 3))
        XCTAssertTrue(warning.label.localizedCaseInsensitiveContains("Low battery"))

        let battery = app.buttons["home.metric.battery"]
        XCTAssertTrue(battery.waitForExistence(timeout: 3))
        let batterySemantics = semantics(of: battery)
        XCTAssertTrue(batterySemantics.localizedCaseInsensitiveContains("14 percent"))
        XCTAssertTrue(batterySemantics.localizedCaseInsensitiveContains("low battery"))
        try app.performAccessibilityAudit(for: [.contrast])
        keepScreenshot(named: "Home Low Battery Warning - Simulator QA Only")
    }

    @MainActor
    func testPendingCommandNeverAppearsConfirmed() {
        let app = launch(
            scenario: "connected-stopped",
            orientation: .portrait,
            environment: ["NEMBRA_SIMULATION_HOME_STATE_FIXTURE": "command-pending"]
        )

        let modeSelector = app.buttons["home.mode.selector"]
        XCTAssertTrue(swipeUpUntilHittable(modeSelector, in: app))
        let light = button(containing: "Light", in: app)
        XCTAssertTrue(light.waitForExistence(timeout: 2))
        XCTAssertTrue(light.label.localizedCaseInsensitiveContains("Off"))
        light.tap()

        let pending = app.buttons.matching(NSPredicate(
            format: "label CONTAINS[c] %@ AND value CONTAINS[c] %@",
            "Light",
            "Requesting confirmation"
        )).firstMatch
        XCTAssertTrue(pending.waitForExistence(timeout: 3))
        XCTAssertTrue(pending.label.localizedCaseInsensitiveContains("Off"))
        XCTAssertFalse(pending.label.localizedCaseInsensitiveContains("On"))
        keepScreenshot(named: "Home Command Pending - Simulator QA Only")
    }

    @MainActor
    func testRejectedCommandShowsFailureAndKeepsConfirmedState() {
        let app = launch(
            scenario: "connected-stopped",
            orientation: .portrait,
            environment: ["NEMBRA_SIMULATION_HOME_STATE_FIXTURE": "command-rejected"]
        )

        let modeSelector = app.buttons["home.mode.selector"]
        XCTAssertTrue(swipeUpUntilHittable(modeSelector, in: app))
        let light = button(containing: "Light", in: app)
        XCTAssertTrue(light.waitForExistence(timeout: 2))
        XCTAssertTrue(light.label.localizedCaseInsensitiveContains("Off"))
        light.tap()

        XCTAssertTrue(app.alerts["Command not confirmed"].waitForExistence(timeout: 3))
        XCTAssertTrue(
            app.staticTexts["The scooter rejected that command in its current state."]
                .waitForExistence(timeout: 2)
        )
        keepScreenshot(named: "Home Command Rejected - Simulator QA Only")
        app.alerts.buttons["OK"].tap()

        let unchangedLight = button(containing: "Light", in: app)
        XCTAssertTrue(unchangedLight.waitForExistence(timeout: 2))
        XCTAssertTrue(unchangedLight.label.localizedCaseInsensitiveContains("Off"))
    }

    @MainActor
    func testPersistenceFailureDoesNotCorruptVehicleTruth() {
        let app = launch(
            scenario: "connected-stopped",
            orientation: .portrait,
            environment: ["NEMBRA_SIMULATION_HOME_STATE_FIXTURE": "persistence-failure"]
        )

        XCTAssertTrue(
            waitForSemanticsContaining(
                "Connected",
                identifier: "home.connection-status",
                in: app
            )
        )
        let readiness = app.buttons["home.horizon-entry"]
        XCTAssertTrue(readiness.waitForExistence(timeout: 3))
        XCTAssertTrue(semantics(of: readiness).localizedCaseInsensitiveContains("Ride tracking unavailable"))

        let trip = app.descendants(matching: .any)["home.metric.trip"]
        XCTAssertTrue(trip.waitForExistence(timeout: 3))
        XCTAssertTrue(semantics(of: trip).localizedCaseInsensitiveContains("unavailable"))

        let battery = app.buttons["home.metric.battery"]
        XCTAssertTrue(battery.exists)
        XCTAssertTrue(semantics(of: battery).localizedCaseInsensitiveContains("92 percent"))

        let latest = app.descendants(matching: .any)["home.latest-ride.unavailable"]
        let window = app.windows.firstMatch
        let tabBar = app.tabBars.firstMatch
        for _ in 0..<4 where !isFullyInsideWindowAndAboveTabBar(latest, window: window, tabBar: tabBar) {
            app.swipeUp()
        }
        XCTAssertTrue(latest.waitForExistence(timeout: 3))
        assertFullyInsideWindowAndAboveTabBar(
            latest,
            named: "Persistence failure state",
            in: app
        )
        keepScreenshot(named: "Home Persistence Failure - Simulator QA Only")
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

        XCTAssertTrue(app.buttons["home.metric.battery"].waitForExistence(timeout: 5))
        let homeQADisclosure = app.descendants(matching: .any)["home.connection-status"]
        XCTAssertTrue(homeQADisclosure.waitForExistence(timeout: 3))
        XCTAssertTrue(semantics(of: homeQADisclosure).localizedCaseInsensitiveContains("SIM"))
        XCTAssertTrue(semantics(of: homeQADisclosure).localizedCaseInsensitiveContains("synthetic evidence"))

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
    func testPassiveLandscapeLeftNeverAuthorizesHorizonAndRestoresPortraitHome() {
        assertPassiveLandscapeNeverAuthorizesHorizonAndRestoresPortraitHome(.landscapeLeft)
    }

    @MainActor
    func testPassiveLandscapeRightNeverAuthorizesHorizonAndRestoresPortraitHome() {
        assertPassiveLandscapeNeverAuthorizesHorizonAndRestoresPortraitHome(.landscapeRight)
    }

    @MainActor
    /// The historical XCTest selector is retained as CI workflow ABI. This test
    /// validates the post-V4 Cockpit Drive implementation; V4 visuals are rejected.
    func testHorizonV4DriveEntryTruthAndScreenshot() {
        let previousAppearance = XCUIDevice.shared.appearance
        defer {
            if XCUIDevice.shared.orientation != .portrait {
                XCUIDevice.shared.orientation = .portrait
            }
            if XCUIDevice.shared.appearance != previousAppearance {
                XCUIDevice.shared.appearance = previousAppearance
            }
        }

        XCUIDevice.shared.appearance = .dark
        let app = launch(scenario: "riding", orientation: .portrait)
        enterHorizon(in: app)

        let cockpit = app.descendants(matching: .any)["dashboard.cockpit"]
        XCTAssertTrue(cockpit.waitForExistence(timeout: 8))
        XCTAssertTrue(
            waitForLandscapeWindow(in: app, timeout: 8),
            "Cockpit must appear only after the requested landscape geometry is observed."
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
            "Cockpit Drive must expose accepted simulator power without relabeling it as throttle."
        )
        let propulsionSemantics = semantics(of: propulsion)
        for required in ["NOW", "from zero", "positive propulsion", "QA scale"] {
            XCTAssertTrue(
                propulsionSemantics.localizedCaseInsensitiveContains(required),
                "Power semantics must make \(required) explicit."
            )
        }
        for rejected in ["throttle", "regen", "rated", "negative scale", "-18", "kW"] {
            XCTAssertFalse(
                propulsionSemantics.localizedCaseInsensitiveContains(rejected),
                "Power semantics must not claim \(rejected)."
            )
        }

        for identifier in [
            "dashboard.today",
            "dashboard.ride-time",
            "dashboard.odometer",
            "dashboard.city-explored",
            "dashboard.recording-status"
        ] {
            XCTAssertTrue(
                app.descendants(matching: .any)[identifier].waitForExistence(timeout: 3),
                "Missing Cockpit truth surface: \(identifier)"
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
        XCTAssertFalse(
            speed.frame.intersects(propulsion.frame),
            "The speed caption and accepted NOW power band must remain spatially distinct."
        )

        let home = app.buttons["dashboard.control.home"]
        let navigate = app.buttons["dashboard.control.navigate"]
        assertMinimumTouchTarget(home, named: "Cockpit Home")
        assertMinimumTouchTarget(navigate, named: "Cockpit Navigate")

        let battery = app.buttons["dashboard.battery-range"]
        XCTAssertTrue(battery.waitForExistence(timeout: 3))
        assertMinimumTouchTarget(battery, named: "Cockpit battery")
        XCTAssertFalse(
            app.descendants(matching: .any)["dashboard.adaptive-range"].exists,
            "Cockpit must never duplicate a detached adaptive-range readout."
        )
        if !battery.label.localizedCaseInsensitiveContains("Battery") {
            battery.tap()
            XCTAssertTrue(waitForLabelContaining("Battery", element: app.buttons["dashboard.battery-range"]))
        }

        let percentageSemantics = semantics(of: app.buttons["dashboard.battery-range"])
        XCTAssertTrue(percentageSemantics.localizedCaseInsensitiveContains("percent"))
        XCTAssertFalse(percentageSemantics.localizedCaseInsensitiveContains(" mi"))
        XCTAssertFalse(percentageSemantics.localizedCaseInsensitiveContains(" km"))

        XCTAssertTrue(windowFrame.contains(battery.frame))
        XCTAssertFalse(
            battery.frame.intersects(speed.frame),
            "The one-value battery instrument must not overlap the speed hero."
        )

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
        let rangeSemantics = semantics(of: app.buttons["dashboard.battery-range"])
        XCTAssertFalse(
            rangeSemantics.localizedCaseInsensitiveContains("percent"),
            "Range mode must expose exactly one primary readout, never a duplicated percentage."
        )
        XCTAssertTrue(
            rangeSemantics.localizedCaseInsensitiveContains("unavailable")
                || rangeSemantics.localizedCaseInsensitiveContains("learning")
                || rangeSemantics.localizedCaseInsensitiveContains(" mi")
                || rangeSemantics.localizedCaseInsensitiveContains(" km"),
            "Range mode must truthfully expose learned range, learning, or unavailable."
        )

        app.buttons["dashboard.battery-range"].tap()
        XCTAssertTrue(
            waitForSemanticChange(
                identifier: "dashboard.battery-range",
                from: rangeSemantics,
                in: app
            ),
            "The same battery instrument must return to percentage mode."
        )
        let restoredPercentageSemantics = semantics(of: app.buttons["dashboard.battery-range"])
        XCTAssertTrue(restoredPercentageSemantics.localizedCaseInsensitiveContains("percent"))
        XCTAssertFalse(restoredPercentageSemantics.localizedCaseInsensitiveContains(" mi"))
        XCTAssertFalse(restoredPercentageSemantics.localizedCaseInsensitiveContains(" km"))

        // Exact Xcode 27 evidence showed that dispatching another XCUI event after
        // a kept landscape screenshot can block on an animation-idle notification.
        // Keep screenshot capture terminal here; the separate hitch test exercises
        // the real Home control and exact-scene portrait restoration.
        keepScreenshot(named: "Cockpit Drive Post-V4 - Simulator QA Only")
        app.terminate()
    }

    @MainActor
    func testCockpitDriveAtAccessibilityXXXLPassesProductionAudit() throws {
        let previousAppearance = XCUIDevice.shared.appearance
        defer {
            if XCUIDevice.shared.orientation != .portrait {
                XCUIDevice.shared.orientation = .portrait
            }
            if XCUIDevice.shared.appearance != previousAppearance {
                XCUIDevice.shared.appearance = previousAppearance
            }
        }

        XCUIDevice.shared.appearance = .dark
        let app = launch(
            scenario: "riding",
            orientation: .portrait,
            arguments: [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityXXXL"
            ]
        )
        defer { app.terminate() }
        enterHorizon(in: app)

        XCTAssertTrue(app.descendants(matching: .any)["dashboard.cockpit"].waitForExistence(timeout: 8))
        XCTAssertTrue(waitForLandscapeWindow(in: app, timeout: 8))

        let window = app.windows.firstMatch
        let battery = app.buttons["dashboard.battery-range"]
        let home = app.buttons["dashboard.control.home"]
        let navigate = app.buttons["dashboard.control.navigate"]
        let speed = app.descendants(matching: .any)["dashboard.speed"]
        let power = app.descendants(matching: .any)["dashboard.energy-rail"]
        let identity = app.descendants(matching: .any)["dashboard.vehicle-identity"]

        for (element, name) in [
            (battery, "battery"),
            (home, "Home"),
            (navigate, "Navigate")
        ] {
            XCTAssertTrue(element.waitForExistence(timeout: 3), "Missing Cockpit \(name) control.")
            assertMinimumTouchTarget(element, named: "Accessibility XXXL Cockpit \(name)")
            XCTAssertTrue(window.frame.contains(element.frame), "Cockpit \(name) must remain inside the window.")
        }
        for (element, name) in [(speed, "speed"), (power, "power")] {
            XCTAssertTrue(element.waitForExistence(timeout: 3), "Missing Cockpit \(name) instrument.")
            XCTAssertTrue(window.frame.contains(element.frame), "Cockpit \(name) must remain inside the window.")
        }

        XCTAssertTrue(identity.waitForExistence(timeout: 3), "Missing Cockpit vehicle identity.")
        XCTAssertTrue(window.frame.contains(identity.frame), "Cockpit identity must remain inside the window.")
        XCTAssertFalse(identity.frame.intersects(speed.frame), "Cockpit identity must not cover the speed hero.")
        XCTAssertFalse(speed.frame.intersects(power.frame), "Speed and accepted NOW power bands must not overlap.")

        let ledgerElements = [
            app.descendants(matching: .any)["dashboard.recording-status"],
            app.descendants(matching: .any)["dashboard.today"],
            app.descendants(matching: .any)["dashboard.ride-time"],
            app.descendants(matching: .any)["dashboard.odometer"],
            app.descendants(matching: .any)["dashboard.city-explored"]
        ]
        for element in ledgerElements {
            XCTAssertTrue(element.waitForExistence(timeout: 3), "Missing accessibility ledger truth surface.")
            XCTAssertFalse(element.frame.isEmpty, "Accessibility ledger truth surfaces need laid-out frames.")
            XCTAssertTrue(window.frame.contains(element.frame), "Accessibility ledger must remain in the window.")
            XCTAssertFalse(element.frame.intersects(speed.frame), "Accessibility ledger must not cover speed.")
            XCTAssertFalse(element.frame.intersects(power.frame), "Accessibility ledger must not cover accepted power.")
        }

        XCTAssertTrue(semantics(of: battery).localizedCaseInsensitiveContains("percent"))
        XCTAssertTrue(semantics(of: power).localizedCaseInsensitiveContains("positive propulsion"))

        try app.performAccessibilityAudit(
            for: [
                .sufficientElementDescription,
                .hitRegion,
                .contrast,
                .textClipped,
                .trait,
                .dynamicType
            ]
        )

        // Keep capture terminal: exact hosted evidence shows a later XCUI event
        // can otherwise block on the landscape animation-idle notification.
        keepScreenshot(named: "Cockpit Drive Accessibility XXXL - Simulator QA Only")
        app.terminate()
    }

    @MainActor
    /// Historical workflow selector retained until the shared CI ABI is migrated.
    func testHorizonV4DriveBatteryToggleHitchEvidence() {
        let previousAppearance = XCUIDevice.shared.appearance
        defer {
            if XCUIDevice.shared.orientation != .portrait {
                XCUIDevice.shared.orientation = .portrait
            }
            if XCUIDevice.shared.appearance != previousAppearance {
                XCUIDevice.shared.appearance = previousAppearance
            }
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
        XCTAssertTrue(
            waitForPortraitWindow(in: app, timeout: 8),
            "The cockpit Home control must restore the owned portrait session."
        )
        XCTAssertTrue(app.buttons["home.horizon-entry"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["dashboard.cockpit"].exists)
    }

    @MainActor
    /// Historical workflow selector retained until the shared CI ABI is migrated.
    func testHorizonV4DriveSustainedRenderIslandHitchEvidence() {
        let previousAppearance = XCUIDevice.shared.appearance
        defer {
            if XCUIDevice.shared.orientation != .portrait {
                XCUIDevice.shared.orientation = .portrait
            }
            if XCUIDevice.shared.appearance != previousAppearance {
                XCUIDevice.shared.appearance = previousAppearance
            }
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
        options.invocationOptions = .manuallyStop
        measure(
            metrics: [
                XCTClockMetric(),
                XCTHitchMetric(application: app)
            ],
            options: options
        ) {
            // Keep XCUI accessibility queries outside the measured interval. The
            // app's independently clocked synthetic source continues offering
            // broad state updates throughout this fixed six-second window. A
            // monotonic clock metric makes the sustained interval independently
            // identifiable in the xcresult; the app-targeted hitch metric remains
            // the rendering-quality measurement.
            let deadline = ProcessInfo.processInfo.systemUptime + 6
            repeat {
                RunLoop.current.run(until: Date().addingTimeInterval(0.10))
            } while ProcessInfo.processInfo.systemUptime < deadline
            stopMeasuring()
        }

        XCTAssertTrue(
            waitForSustainedDashboardUpdates(speed: speed, power: power, requiredChanges: 3),
            "Synthetic speed and accepted-power source updates must still advance after all measured intervals."
        )

        keepScreenshot(named: "Cockpit Drive Render Stress - Simulator QA Only")

        // The stress fixture intentionally keeps publishing source updates, so a
        // Home tap would wait for XCUI quiescence that can never arrive. Portrait
        // restoration is covered independently; terminate this isolated fixture
        // after its post-measurement proof and retained screenshot instead.
        app.terminate()
    }

    @MainActor
    private func launch(
        scenario: String,
        orientation: UIDeviceOrientation,
        environment: [String: String] = [:],
        arguments: [String] = []
    ) -> XCUIApplication {
        XCUIDevice.shared.orientation = orientation
        let app = XCUIApplication()
        app.launchEnvironment["NEMBRA_SIMULATION_SCENARIO"] = scenario
        app.launchEnvironment["NEMBRA_SIMULATION_STORAGE_NAMESPACE"] = UUID().uuidString
        for (key, value) in environment {
            app.launchEnvironment[key] = value
        }
        // Product persistence is covered by an isolated unit test. UI evidence
        // starts from the documented default so retries/order cannot inherit a
        // prior test's odd-numbered toggle through global UserDefaults.
        app.launchArguments.append(contentsOf: [
            "-horizon.batteryPrimaryReadout.v1",
            "percentage"
        ])
        app.launchArguments.append(contentsOf: arguments)
        app.launch()
        return app
    }

    @MainActor
    private func enterHorizon(in app: XCUIApplication) {
        let entry = app.buttons["home.horizon-entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        if !entry.isHittable {
            XCTAssertTrue(
                swipeUpUntilHittable(entry, in: app),
                "The Horizon entry must remain reachable at the active Dynamic Type size."
            )
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
    private func assertPassiveLandscapeNeverAuthorizesHorizonAndRestoresPortraitHome(
        _ orientation: UIDeviceOrientation
    ) {
        // Hosted XCUI may spend close to a minute draining orientation-animation
        // notifications even after the app has already restored portrait truth.
        // Keep each direction isolated and give only this exact evidence path a
        // bounded allowance; terminating first prevents cleanup from waiting on
        // another app-owned geometry correction.
        executionTimeAllowance = 110

        let app = launch(scenario: "connected-stopped", orientation: .portrait)
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }
        let homeEntry = app.buttons["home.horizon-entry"]
        XCTAssertTrue(homeEntry.waitForExistence(timeout: 5))

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
    private func waitForSemanticsContaining(
        _ value: String,
        identifier: String,
        in app: XCUIApplication,
        timeout: TimeInterval = 3
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let element = app.descendants(matching: .any)[identifier]
            if element.exists,
               semantics(of: element).localizedCaseInsensitiveContains(value) {
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
        timeout: TimeInterval = 8
    ) -> Bool {
        guard requiredChanges > 0, speed.exists, power.exists else { return false }

        let deadline = Date().addingTimeInterval(timeout)
        var previousSpeed = dynamicValue(of: speed)
        var previousPower = dynamicValue(of: power)
        var speedChanges = 0
        var powerChanges = 0

        repeat {
            let currentSpeed = dynamicValue(of: speed)
            if currentSpeed != previousSpeed {
                previousSpeed = currentSpeed
                speedChanges += 1
            }

            let currentPower = dynamicValue(of: power)
            if currentPower != previousPower {
                previousPower = currentPower
                powerChanges += 1
            }

            if speedChanges >= requiredChanges, powerChanges >= requiredChanges {
                return true
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline

        return false
    }

    @MainActor
    private func dynamicValue(of element: XCUIElement) -> String {
        element.value as? String ?? ""
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
    private func scrollFullyInsideWindowAndAboveTabBar(
        _ element: XCUIElement,
        in app: XCUIApplication,
        maximumAttempts: Int
    ) -> Bool {
        guard element.waitForExistence(timeout: 2) else { return false }
        let scrollView = app.scrollViews.firstMatch
        let window = app.windows.firstMatch
        let tabBar = app.tabBars.firstMatch
        guard scrollView.waitForExistence(timeout: 2),
              window.waitForExistence(timeout: 2),
              tabBar.waitForExistence(timeout: 2) else {
            return false
        }

        for attempt in 0...maximumAttempts {
            if isFullyInsideWindowAndAboveTabBar(element, window: window, tabBar: tabBar) {
                return true
            }
            guard attempt < maximumAttempts else { break }
            scrollView.swipeUp()
        }

        return isFullyInsideWindowAndAboveTabBar(element, window: window, tabBar: tabBar)
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
    private func assertFullyInsideWindowAndAboveTabBar(
        _ element: XCUIElement,
        named name: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let window = app.windows.firstMatch
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(window.exists, "The application window must exist.", file: file, line: line)
        XCTAssertTrue(tabBar.exists, "The native tab bar must exist.", file: file, line: line)
        XCTAssertFalse(window.frame.isEmpty, "The application window must have laid-out bounds.", file: file, line: line)
        XCTAssertFalse(tabBar.frame.isEmpty, "The native tab bar must have laid-out bounds.", file: file, line: line)
        XCTAssertFalse(element.frame.isEmpty, "\(name) must have a laid-out nonempty frame.", file: file, line: line)
        XCTAssertTrue(
            window.frame.contains(element.frame),
            "\(name) \(element.frame) must remain inside window \(window.frame).",
            file: file,
            line: line
        )
        XCTAssertLessThanOrEqual(
            element.frame.maxY,
            tabBar.frame.minY - 8,
            "\(name) \(element.frame) must clear tab bar \(tabBar.frame).",
            file: file,
            line: line
        )
    }

    @MainActor
    private func isFullyInsideWindowAndAboveTabBar(
        _ element: XCUIElement,
        window: XCUIElement,
        tabBar: XCUIElement
    ) -> Bool {
        guard element.exists, window.exists, tabBar.exists else { return false }
        guard !element.frame.isEmpty, !window.frame.isEmpty, !tabBar.frame.isEmpty else { return false }
        return window.frame.contains(element.frame)
            && element.frame.maxY <= tabBar.frame.minY - 8
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
    private func staticText(containing fragment: String, in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", fragment)).firstMatch
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
