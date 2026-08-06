#!/usr/bin/env python3
from pathlib import Path


def replace_once(path: str, old: str, new: str, label: str) -> None:
    p = Path(path)
    text = p.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one anchor, found {count}")
    p.write_text(text.replace(old, new, 1))


service = "Packages/NembraCore/Sources/NembraCore/SimulatedScooterService.swift"
replace_once(
    service,
    '''    case connectedStopped = "connected-stopped"
    case riding
''',
    '''    case connectedStopped = "connected-stopped"
    case connectedSpeedUnknown = "connected-speed-unknown"
    case riding
''',
    "scenario enum",
)
replace_once(
    service,
    '''        case .connectedStopped, .riding, .lowBattery:
            true
''',
    '''        case .connectedStopped, .connectedSpeedUnknown, .riding, .lowBattery:
            true
''',
    "auto-connect classification",
)
replace_once(
    service,
    '''        case .riding:
            VehicleState(
''',
    '''        case .connectedSpeedUnknown:
            VehicleState(
                connection: .connected,
                batteryPercent: 92,
                speedKilometersPerHour: nil,
                odometerKilometers: 231.4,
                tripKilometers: 4.6,
                rideMode: .sport,
                startMode: .zeroStart,
                speedLimitsKilometersPerHour: representativeSpeedLimits,
                isLocked: false,
                isHeadlightOn: false,
                isCruiseEnabled: false,
                powerWatts: nil,
                currentAmps: nil
            )
        case .riding:
            VehicleState(
''',
    "unknown-speed fixture",
)

replace_once(
    "Packages/NembraCore/Tests/NembraCoreTests/SimulatedScooterServiceTests.swift",
    '''        let riding = SimulatedScooterService.state(for: .riding)
''',
    '''        let connectedUnknown = SimulatedScooterService.state(for: .connectedSpeedUnknown)
        #expect(connectedUnknown.connection == .connected)
        #expect(connectedUnknown.speedKilometersPerHour == nil)
        #expect(connectedUnknown.isLocked == false)
        #expect(connectedUnknown.dataAvailability == .live)

        let riding = SimulatedScooterService.state(for: .riding)
''',
    "simulation fixture test",
)

replace_once(
    "NembraUITests/NembraUITests.swift",
    '''    @MainActor
    func testPermissionDeniedOffersSettingsInsteadOfFakeReconnect() {
''',
    '''    @MainActor
    func testConnectedUnknownSpeedDoesNotPretendScooterIsStopped() {
        let app = launch(scenario: "connected-speed-unknown", orientation: .portrait)

        let connection = app.descendants(matching: .any)["home.connection"]
        XCTAssertTrue(connection.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForValue("Connected", element: connection))

        let lock = button(containing: "Lock", in: app)
        XCTAssertTrue(lock.waitForExistence(timeout: 2))
        XCTAssertFalse(lock.isEnabled, "Lock must stay disabled until a confirmed stationary speed exists.")
        XCTAssertTrue(lock.label.contains("Speed unavailable"))
    }

    @MainActor
    func testLandscapeUnknownSpeedSuppressesStoppedControls() {
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launch(scenario: "connected-speed-unknown", orientation: .landscapeRight)

        XCTAssertTrue(app.descendants(matching: .any)["dashboard.cockpit"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["SPEED UNAVAILABLE"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["dashboard.control.lock"].exists)
        XCTAssertFalse(app.buttons["dashboard.control.light"].exists)
        XCTAssertFalse(app.buttons["dashboard.mode.sport"].exists)

        keepScreenshot(named: "Dashboard Speed Unavailable Landscape")
    }

    @MainActor
    func testPermissionDeniedOffersSettingsInsteadOfFakeReconnect() {
''',
    "unknown-speed UI tests",
)

replace_once(
    "scripts/ci/xcode27_simulator_capture.sh",
    '''  connected-stopped \\
  riding \\
''',
    '''  connected-stopped \\
  connected-speed-unknown \\
  riding \\
''',
    "portrait capture scenario",
)

print("Connected unknown-speed QA scenario applied successfully.")
