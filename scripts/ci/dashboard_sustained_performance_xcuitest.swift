// Appended at CI runtime to NembraUITests.swift by dashboard-sustained-performance.yml.
// This witness measures only Simulator presentation performance. Synthetic source
// cadence and rendered intermediate frames create no physical or telemetry authority.
final class DashboardSustainedPerformanceUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        executionTimeAllowance = 120
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
        let speed = app.descendants(matching: .any)["dashboard.speed"]
        XCTAssertTrue(
            speed.waitForExistence(timeout: 2),
            "The sustained performance run must exercise the real mounted speed instrument."
        )

        let initialPowerValue = energyRail.value as? String ?? ""
        let initialSpeedValue = speed.value as? String ?? ""
        let powerMoved = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value != %@", initialPowerValue),
            object: energyRail
        )
        let speedMoved = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value != %@", initialSpeedValue),
            object: speed
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [powerMoved, speedMoved], timeout: 2),
            .completed,
            "Measurement must begin only after fresh Simulator-owned speed/power receipts are actively retargeting both instruments."
        )

        let options = XCTMeasureOptions()
        // XCTest performs one warm-up plus one recorded iteration. The source-owned
        // stress fixture runs for roughly 12 seconds, covering both 3-second windows.
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

        XCTAssertTrue(cockpit.exists, "The real cockpit must remain mounted for the complete measurement window.")
        XCTAssertTrue(energyRail.exists, "The Energy Rail must remain mounted for the complete measurement window.")
        XCTAssertTrue(speed.exists, "The speed instrument must remain mounted for the complete measurement window.")

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Dashboard Sustained Stress Landscape"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}