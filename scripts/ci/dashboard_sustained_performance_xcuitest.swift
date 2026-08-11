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

        XCTAssertTrue(
            app.descendants(matching: .any)["dashboard.energy-rail"].waitForExistence(timeout: 2),
            "The sustained performance run must exercise the real mounted Energy Rail."
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["dashboard.speed"].waitForExistence(timeout: 2),
            "The sustained performance run must exercise the real mounted speed instrument."
        )

        let initialPowerValue = freshSemanticValue(identifier: "dashboard.energy-rail", in: app)
        let initialSpeedValue = freshSemanticValue(identifier: "dashboard.speed", in: app)
        guard let preMeasureValues = waitForBothSemanticValuesToMove(
            in: app,
            powerFrom: initialPowerValue,
            speedFrom: initialSpeedValue,
            timeout: 2
        ) else {
            XCTFail(
                "Measurement must begin only after fresh Simulator-owned speed/power receipts are actively retargeting both instruments."
            )
            return
        }

        let options = XCTMeasureOptions()
        // The source-owned stress driver remains alive for the fixture lifetime,
        // so launch/idle overhead cannot move this measurement after source motion.
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
            app.descendants(matching: .any)["dashboard.cockpit"].exists,
            "The real cockpit must remain mounted for the complete measurement window."
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["dashboard.energy-rail"].exists,
            "The Energy Rail must remain mounted for the complete measurement window."
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["dashboard.speed"].exists,
            "The speed instrument must remain mounted for the complete measurement window."
        )

        // Prove the source did not terminate at or before the measured window.
        // Re-query the semantic elements on every observation. SwiftUI may replace
        // the accessibility snapshot while the accepted Simulator-owned source is
        // moving, so a pre-measure XCUIElement handle is not itself fresh evidence.
        XCTAssertNotNil(
            waitForBothSemanticValuesToMove(
                in: app,
                powerFrom: preMeasureValues.power,
                speedFrom: preMeasureValues.speed,
                timeout: 1.5
            ),
            "The sustained source must still be actively retargeting both semantic instruments after the metric window."
        )

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Dashboard Sustained Stress Landscape"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func freshSemanticValue(identifier: String, in app: XCUIApplication) -> String {
        let element = app.descendants(matching: .any)[identifier]
        guard element.exists else { return "" }
        return element.value as? String ?? ""
    }

    @MainActor
    private func waitForBothSemanticValuesToMove(
        in app: XCUIApplication,
        powerFrom initialPowerValue: String,
        speedFrom initialSpeedValue: String,
        timeout: TimeInterval
    ) -> (power: String, speed: String)? {
        let deadline = Date().addingTimeInterval(timeout)
        var observedPowerValue = initialPowerValue
        var observedSpeedValue = initialSpeedValue
        var sawPowerMove = false
        var sawSpeedMove = false

        repeat {
            let freshPowerValue = freshSemanticValue(identifier: "dashboard.energy-rail", in: app)
            let freshSpeedValue = freshSemanticValue(identifier: "dashboard.speed", in: app)

            if !freshPowerValue.isEmpty {
                observedPowerValue = freshPowerValue
                sawPowerMove = sawPowerMove || freshPowerValue != initialPowerValue
            }
            if !freshSpeedValue.isEmpty {
                observedSpeedValue = freshSpeedValue
                sawSpeedMove = sawSpeedMove || freshSpeedValue != initialSpeedValue
            }

            if sawPowerMove && sawSpeedMove {
                return (power: observedPowerValue, speed: observedSpeedValue)
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline

        return nil
    }
}
