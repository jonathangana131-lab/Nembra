import XCTest

@MainActor
final class NembraUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        executionTimeAllowance = 60
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    func testConnectedHomeControlsConfirmStateAndNavigate() {
        launch(scenario: "connected-stopped")

        XCTAssertTrue(app.staticTexts["MAXSHOT V1S Pro"].waitForExistence(timeout: 3))

        let light = button(containing: "Light")
        XCTAssertTrue(light.waitForExistence(timeout: 2))
        XCTAssertTrue(light.label.contains("Off"))
        light.tap()
        XCTAssertTrue(waitForLabelFragment("On", element: light))

        let drive = app.buttons["home.mode.drive"]
        XCTAssertTrue(drive.exists)
        drive.tap()
        let modeMetric = app.descendants(matching: .any)["Mode"]
        XCTAssertTrue(modeMetric.waitForExistence(timeout: 2))
        XCTAssertTrue(waitForValue("Drive", element: modeMetric))

        let lock = button(containing: "Lock")
        XCTAssertTrue(lock.exists)
        lock.tap()
        let confirmLock = app.sheets.buttons["Lock"]
        XCTAssertTrue(confirmLock.waitForExistence(timeout: 2))
        confirmLock.tap()
        XCTAssertTrue(waitForLabelFragment("Secured", element: lock))

        let controls = app.buttons["Vehicle controls"]
        XCTAssertTrue(controls.exists)
        controls.tap()
        XCTAssertTrue(app.navigationBars["Vehicle Controls"].waitForExistence(timeout: 2))
    }

    func testUnavailableScooterCanRecoverWithoutInventingLiveState() {
        launch(scenario: "scooter-unavailable")

        XCTAssertTrue(app.staticTexts["Scooter not found"].waitForExistence(timeout: 3))
        let reconnect = app.buttons["Reconnect scooter"]
        XCTAssertTrue(reconnect.exists)
        reconnect.tap()
        XCTAssertTrue(app.staticTexts["Connected"].waitForExistence(timeout: 4))
    }

    func testPermissionDeniedOffersSettingsInsteadOfFakeReconnect() {
        launch(scenario: "permission-denied")
        XCTAssertTrue(app.staticTexts["Bluetooth access is off"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Open Nembra settings"].exists)
        XCTAssertFalse(app.buttons["Reconnect scooter"].exists)
    }

    private func launch(scenario: String) {
        app.launchEnvironment["NEMBRA_SIMULATION_SCENARIO"] = scenario
        app.launch()
    }

    private func button(containing fragment: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", fragment)).firstMatch
    }

    private func waitForLabelFragment(_ fragment: String, element: XCUIElement, timeout: TimeInterval = 3) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@", fragment)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitForValue(_ value: String, element: XCUIElement, timeout: TimeInterval = 3) -> Bool {
        let predicate = NSPredicate(format: "value == %@", value)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}
