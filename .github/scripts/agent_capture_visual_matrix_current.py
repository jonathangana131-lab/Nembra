from pathlib import Path

path = Path("NembraUITests/ES80ResearchCaptureUITests.swift")
text = path.read_text(encoding="utf-8")
anchor = "    func testSimulatorQAAppSeamIsCompileBoundedAndProductionRouteRemainsLocked() throws {"
if text.count(anchor) != 1:
    raise SystemExit(f"Expected one insertion anchor, found {text.count(anchor)}")
if "testV14SimulatorQACapturesRepresentativeInProgressAndRecoveryStates" in text:
    raise SystemExit("Representative state matrix already exists on current flagship")

block = r'''    @MainActor
    func testV14SimulatorQACapturesRepresentativeInProgressAndRecoveryStates() {
        struct ScenarioExpectation {
            let scenario: String
            let requiredText: String
            let requiredIdentifier: String?
            let screenshotName: String
        }

        let scenarios = [
            ScenarioExpectation(
                scenario: "secondPoweredOff",
                requiredText: "Scooter OFF",
                requiredIdentifier: "es80.capture.begin-window",
                screenshotName: "Nembra Capture V14 — SIMULATOR QA — OFF 2 Ready"
            ),
            ScenarioExpectation(
                scenario: "secondPoweredOn",
                requiredText: "One target repeated twice",
                requiredIdentifier: "es80.capture.confirm-correlated-target",
                screenshotName: "Nembra Capture V14 — SIMULATOR QA — Scooter Signal Found"
            ),
            ScenarioExpectation(
                scenario: "passiveDiscovery",
                requiredText: "Opening the correlated target",
                requiredIdentifier: nil,
                screenshotName: "Nembra Capture V14 — SIMULATOR QA — Passive Connection"
            ),
            ScenarioExpectation(
                scenario: "captureInProgress",
                requiredText: "OBSERVATION READY",
                requiredIdentifier: "es80.capture.finish",
                screenshotName: "Nembra Capture V14 — SIMULATOR QA — Observation In Progress"
            ),
            ScenarioExpectation(
                scenario: "horizonSealed",
                requiredText: "Freezing final evidence",
                requiredIdentifier: nil,
                screenshotName: "Nembra Capture V14 — SIMULATOR QA — Sealing"
            ),
            ScenarioExpectation(
                scenario: "foregroundInterrupted",
                requiredText: "Capture stopped safely",
                requiredIdentifier: "es80.capture.restart-experiment",
                screenshotName: "Nembra Capture V14 — SIMULATOR QA — Foreground Interrupted"
            )
        ]

        for expectation in scenarios {
            let app = XCUIApplication()
            app.launchArguments = [
                "--es80-passive-capture-simulator-qa",
                "--es80-capture-qa-scenario=\(expectation.scenario)"
            ]
            app.launch()

            XCTAssertTrue(
                app.descendants(matching: .any)["es80.capture-shell"].waitForExistence(timeout: 5),
                "Scenario \(expectation.scenario) must render the real Capture shell."
            )
            XCTAssertTrue(
                app.descendants(matching: .any)["es80.capture.simulator-qa"].waitForExistence(timeout: 3),
                "Scenario \(expectation.scenario) must stay explicitly labeled SIMULATOR / QA."
            )
            XCTAssertTrue(
                app.staticTexts[expectation.requiredText].waitForExistence(timeout: 3),
                "Scenario \(expectation.scenario) did not render its expected rider-facing state."
            )
            if let identifier = expectation.requiredIdentifier {
                XCTAssertTrue(
                    app.descendants(matching: .any)[identifier].waitForExistence(timeout: 3),
                    "Scenario \(expectation.scenario) lost its stable state/action identifier \(identifier)."
                )
            }
            XCTAssertFalse(
                app.descendants(matching: .any)["es80.capture.field-no-go"].exists,
                "Synthetic QA presentation should exercise the real Capture state instead of the field lock surface."
            )
            XCTAssertFalse(
                app.buttons["Vehicle controls"].exists,
                "Capture QA must never expose the ordinary vehicle-control surface."
            )

            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = expectation.screenshotName
            attachment.lifetime = .keepAlways
            add(attachment)
            app.terminate()
        }
    }

'''
path.write_text(text.replace(anchor, block + anchor, 1), encoding="utf-8")
