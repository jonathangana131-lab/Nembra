import Foundation
import XCTest

final class ES80ResearchCaptureUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        executionTimeAllowance = 120
    }

    @MainActor
    func testV14ResearchLaunchMechanicallyBlocksPhysicalExperimentWhilePackageIsNoGo() {
        let app = XCUIApplication()
        app.launchArguments = ["--es80-passive-capture"]
        app.launch()

        XCTAssertTrue(
            app.navigationBars["Nembra Capture"].waitForExistence(timeout: 5),
            "The explicit research launch must open the dedicated Nembra Capture surface."
        )
        XCTAssertTrue(
            app.staticTexts["NEMBRA CAPTURE"].waitForExistence(timeout: 3),
            "The V14 capture identity must remain visible."
        )
        XCTAssertTrue(
            app.staticTexts["Capture locked"].waitForExistence(timeout: 3),
            "The current package-owned NO-GO must be the primary product state."
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["es80.capture.field-no-go"].waitForExistence(timeout: 3),
            "The dedicated package-gated NO-GO surface must be active."
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["es80.capture.physical-run-locked"].waitForExistence(timeout: 3),
            "The physical NO-GO boundary must be exposed as one stable accessibility element."
        )

        let buildIdentity = app.descendants(matching: .any)["es80.capture.build-identity"]
        XCTAssertTrue(
            buildIdentity.waitForExistence(timeout: 3),
            "The rider-facing lock must expose the running build's human-readable identity without exposing raw provenance by default."
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["es80.capture.build-source-sha"].exists,
            "The exact source SHA must remain secondary while Engineering Details is collapsed."
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["es80.capture.build-instance-id"].exists,
            "The exact build-instance rendezvous must remain secondary while Engineering Details is collapsed."
        )

        let engineeringDetails = app.descendants(matching: .any)["es80.capture.engineering-details"]
        XCTAssertTrue(
            engineeringDetails.waitForExistence(timeout: 3),
            "Exact recipe and authorization truth must remain available without dominating the rider-facing hierarchy."
        )
        XCTAssertFalse(
            app.staticTexts["ES80-FINGERPRINT-v1"].exists,
            "The raw recipe identifier must stay collapsed on the primary rider-facing NO-GO surface."
        )

        engineeringDetails.tap()
        XCTAssertTrue(
            app.staticTexts["ES80-FINGERPRINT-v1"].waitForExistence(timeout: 3),
            "Engineering Details must preserve the exact installed recipe identifier."
        )
        XCTAssertTrue(
            app.staticTexts["Physical authorization"].waitForExistence(timeout: 3),
            "Engineering Details must preserve the physical authorization dimension."
        )
        XCTAssertTrue(
            app.staticTexts["NO-GO"].waitForExistence(timeout: 3),
            "Engineering Details must preserve explicit physical NO-GO truth."
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["es80.capture.build-source-sha"].waitForExistence(timeout: 3),
            "The QA build injects exact source identity, which must remain inspectable inside Engineering Details."
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["es80.capture.build-instance-id"].waitForExistence(timeout: 3),
            "The QA build injects the produced-build rendezvous, which must remain inspectable inside Engineering Details."
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["es80.capture.stationary-preflight"].exists,
            "Expanding information-only details must not instantiate the field preflight."
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["es80.capture.begin-window"].exists,
            "Expanding information-only details must not expose OFF1 or any field action."
        )

        engineeringDetails.tap()
        XCTAssertFalse(
            app.staticTexts["ES80-FINGERPRINT-v1"].exists,
            "Collapsing Engineering Details must restore the rider-facing hierarchy."
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["es80.capture.build-source-sha"].exists,
            "Collapsing Engineering Details must hide the raw source SHA again."
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["es80.capture.build-instance-id"].exists,
            "Collapsing Engineering Details must hide the raw build-instance rendezvous again."
        )

        XCTAssertFalse(
            app.descendants(matching: .any)["es80.capture.stationary-preflight"].exists,
            "The charger declaration is downstream of package field authority and must not appear while the package gate is NO-GO."
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["es80.capture.preflight.charger-disconnected"].exists,
            "Even the accepted charger choice must not become a UI-level bypass around package NO-GO."
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["es80.capture.preflight.charger-connected"].exists,
            "The blocked charger choice must remain unreachable until package field authority exists."
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["es80.capture.preflight.continue"].exists,
            "No local preflight state may instantiate the physical shell while the package field gate is closed."
        )
        XCTAssertFalse(
            app.buttons["Begin OFF 1 window"].exists,
            "A NO-GO build must not expose the first physical OFF/ON action."
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["es80.capture.begin-window"].exists,
            "No hidden or differently-labeled correlation-window action may bypass the package gate."
        )
        XCTAssertFalse(
            app.buttons["Scan for scooter"].exists,
            "The old generic manual-candidate scan must not become a fallback physical path."
        )
        XCTAssertFalse(
            app.buttons["Start passive capture"].exists,
            "Standalone capture cannot bypass field authorization or Experiment One authority binding."
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["es80.capture.start"].exists,
            "No hidden Start Capture action may bypass the Experiment One authority boundary."
        )
        XCTAssertFalse(
            app.buttons["Finish Capture"].exists,
            "Finish cannot exist before field authorization and accepted Horizon/seal authority."
        )
        XCTAssertFalse(
            app.buttons["Vehicle controls"].exists,
            "Research capture must not silently expose the normal vehicle-control experience."
        )
        XCTAssertFalse(
            app.buttons["Advanced details"].exists,
            "The control-capable package research console must not become a second acquisition workflow."
        )

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Nembra Capture V14 — Rider-Facing Physical NO-GO"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testV14NoGoRemainsLegibleAtAccessibilityExtraExtraExtraLarge() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--es80-passive-capture",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
        ]
        app.launch()

        let lockedState = app.descendants(matching: .any)["es80.capture.field-no-go"]
        let buildIdentity = app.descendants(matching: .any)["es80.capture.build-identity"]
        let physicalBoundary = app.descendants(matching: .any)["es80.capture.physical-run-locked"]
        let engineeringDetails = app.descendants(matching: .any)["es80.capture.engineering-details"]

        XCTAssertTrue(lockedState.waitForExistence(timeout: 5))
        XCTAssertTrue(buildIdentity.waitForExistence(timeout: 3))
        XCTAssertTrue(physicalBoundary.waitForExistence(timeout: 3))
        XCTAssertTrue(engineeringDetails.waitForExistence(timeout: 3))
        XCTAssertFalse(
            app.staticTexts["ES80-FINGERPRINT-v1"].exists,
            "Raw engineering identity must remain collapsed at Accessibility XXXL."
        )
        XCTAssertFalse(app.descendants(matching: .any)["es80.capture.build-source-sha"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["es80.capture.build-instance-id"].exists)

        let windowFrame = app.windows.firstMatch.frame
        assertVisibleInScreenshotViewport(
            lockedState,
            windowFrame: windowFrame,
            context: "primary NO-GO state at Accessibility XXXL"
        )
        assertVisibleInScreenshotViewport(
            buildIdentity,
            windowFrame: windowFrame,
            context: "human-readable build identity at Accessibility XXXL"
        )
        assertVisibleInScreenshotViewport(
            physicalBoundary,
            windowFrame: windowFrame,
            context: "physical-run boundary at Accessibility XXXL"
        )
        assertVisibleInScreenshotViewport(
            engineeringDetails,
            windowFrame: windowFrame,
            context: "Engineering Details disclosure at Accessibility XXXL"
        )

        XCTAssertFalse(app.descendants(matching: .any)["es80.capture.begin-window"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["es80.capture.stationary-preflight"].exists)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Nembra Capture V14 — Rider NO-GO — Accessibility XXXL"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testV14NoGoLandscapeKeepsLockStateAndDetailsVisible() {
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }

        let app = XCUIApplication()
        app.launchArguments = ["--es80-passive-capture"]
        app.launch()

        XCTAssertTrue(
            app.descendants(matching: .any)["es80.capture.field-no-go"].waitForExistence(timeout: 5)
        )

        XCUIDevice.shared.orientation = .landscapeLeft

        let lockedState = app.descendants(matching: .any)["es80.capture.field-no-go"]
        let buildIdentity = app.descendants(matching: .any)["es80.capture.build-identity"]
        let physicalBoundary = app.descendants(matching: .any)["es80.capture.physical-run-locked"]
        let engineeringDetails = app.descendants(matching: .any)["es80.capture.engineering-details"]
        XCTAssertTrue(lockedState.waitForExistence(timeout: 3))
        XCTAssertTrue(buildIdentity.waitForExistence(timeout: 3))
        XCTAssertTrue(physicalBoundary.waitForExistence(timeout: 3))
        XCTAssertTrue(engineeringDetails.waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["ES80-FINGERPRINT-v1"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["es80.capture.build-source-sha"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["es80.capture.build-instance-id"].exists)

        let windowFrame = app.windows.firstMatch.frame
        assertVisibleInScreenshotViewport(
            lockedState,
            windowFrame: windowFrame,
            context: "primary NO-GO state in landscape"
        )
        assertVisibleInScreenshotViewport(
            buildIdentity,
            windowFrame: windowFrame,
            context: "human-readable build identity in landscape"
        )
        assertVisibleInScreenshotViewport(
            physicalBoundary,
            windowFrame: windowFrame,
            context: "physical-run boundary in landscape"
        )
        assertVisibleInScreenshotViewport(
            engineeringDetails,
            windowFrame: windowFrame,
            context: "Engineering Details disclosure in landscape"
        )

        XCTAssertFalse(app.descendants(matching: .any)["es80.capture.begin-window"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["es80.capture.stationary-preflight"].exists)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Nembra Capture V14 — Rider NO-GO — Landscape"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testV14SimulatorQARendersStationaryPreflightWithoutPromotingFieldGo() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--es80-passive-capture-simulator-qa",
            "--es80-capture-qa-scenario=stationaryPreflight"
        ]
        app.launch()

        XCTAssertTrue(
            app.descendants(matching: .any)["es80.capture.stationary-preflight"].waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["es80.capture.simulator-qa"].waitForExistence(timeout: 3)
        )
        XCTAssertTrue(app.buttons["Charger Disconnected"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.descendants(matching: .any)["es80.capture.field-no-go"].exists)
        XCTAssertFalse(app.buttons["Vehicle controls"].exists)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Nembra Capture V14 — SIMULATOR QA — Stationary Preflight"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testV14SimulatorQARendersObservationHorizonReadyInRealCaptureShell() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--es80-passive-capture-simulator-qa",
            "--es80-capture-qa-scenario=observationHorizonReady"
        ]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["es80.capture-shell"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["es80.capture.simulator-qa"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Capture can be sealed"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["es80.capture.finish"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.descendants(matching: .any)["es80.capture.field-no-go"].exists)
        XCTAssertFalse(app.buttons["Vehicle controls"].exists)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Nembra Capture V14 — SIMULATOR QA — Horizon Ready"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testV14SimulatorQARendersCompleteAndShareRetryStates() {
        let complete = XCUIApplication()
        complete.launchArguments = [
            "--es80-passive-capture-simulator-qa",
            "--es80-capture-qa-scenario=captureComplete"
        ]
        complete.launch()

        XCTAssertTrue(complete.descendants(matching: .any)["es80.capture.simulator-qa"].waitForExistence(timeout: 5))
        XCTAssertTrue(complete.staticTexts["CAPTURE COMPLETE"].waitForExistence(timeout: 3))
        XCTAssertTrue(complete.staticTexts["Ready for analysis"].waitForExistence(timeout: 3))
        XCTAssertTrue(complete.buttons["Share Capture"].waitForExistence(timeout: 3))
        XCTAssertTrue(complete.buttons["View Details"].waitForExistence(timeout: 3))
        XCTAssertFalse(complete.buttons["Vehicle controls"].exists)

        complete.buttons["View Details"].tap()
        XCTAssertTrue(
            complete.descendants(matching: .any)["es80.capture.details.simulator-qa"].waitForExistence(timeout: 3)
        )
        XCTAssertTrue(complete.staticTexts["Capture artifact"].waitForExistence(timeout: 3))
        XCTAssertTrue(complete.staticTexts["Not created"].waitForExistence(timeout: 3))
        XCTAssertFalse(complete.staticTexts["Correlation"].exists)

        let detailsAttachment = XCTAttachment(screenshot: complete.screenshot())
        detailsAttachment.name = "Nembra Capture V14 — SIMULATOR QA — Synthetic Details"
        detailsAttachment.lifetime = .keepAlways
        add(detailsAttachment)

        complete.buttons["Done"].tap()
        let completeAttachment = XCTAttachment(screenshot: complete.screenshot())
        completeAttachment.name = "Nembra Capture V14 — SIMULATOR QA — Capture Complete"
        completeAttachment.lifetime = .keepAlways
        add(completeAttachment)
        complete.terminate()

        let retry = XCUIApplication()
        retry.launchArguments = [
            "--es80-passive-capture-simulator-qa",
            "--es80-capture-qa-scenario=shareRetry"
        ]
        retry.launch()

        XCTAssertTrue(retry.descendants(matching: .any)["es80.capture.simulator-qa"].waitForExistence(timeout: 5))
        XCTAssertTrue(retry.buttons["Retry Share file"].waitForExistence(timeout: 3))
        XCTAssertTrue(retry.buttons["View Details"].waitForExistence(timeout: 3))
        XCTAssertFalse(retry.buttons["Vehicle controls"].exists)

        let retryAttachment = XCTAttachment(screenshot: retry.screenshot())
        retryAttachment.name = "Nembra Capture V14 — SIMULATOR QA — Share Retry"
        retryAttachment.lifetime = .keepAlways
        add(retryAttachment)
    }

    @MainActor
    func testV14SimulatorQACaptureCompleteRemainsActionableAtAccessibilityExtraExtraExtraLarge() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--es80-passive-capture-simulator-qa",
            "--es80-capture-qa-scenario=captureComplete",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
        ]
        app.launch()

        let qaDisclosure = app.descendants(matching: .any)["es80.capture.simulator-qa"]
        let completeState = app.staticTexts["CAPTURE COMPLETE"]
        let analysisState = app.staticTexts["Ready for analysis"]
        let shareCapture = app.buttons["Share Capture"]
        let viewDetails = app.buttons["View Details"]

        XCTAssertTrue(qaDisclosure.waitForExistence(timeout: 5))
        XCTAssertTrue(completeState.waitForExistence(timeout: 3))
        XCTAssertTrue(analysisState.waitForExistence(timeout: 3))
        XCTAssertTrue(shareCapture.waitForExistence(timeout: 3))
        XCTAssertTrue(viewDetails.waitForExistence(timeout: 3))
        XCTAssertFalse(app.descendants(matching: .any)["es80.capture.field-no-go"].exists)
        XCTAssertFalse(app.buttons["Vehicle controls"].exists)

        assertVisibleInScreenshotViewport(
            qaDisclosure,
            windowFrame: app.windows.firstMatch.frame,
            context: "synthetic Simulator QA disclosure at Accessibility XXXL"
        )
        let disclosureAttachment = XCTAttachment(screenshot: app.screenshot())
        disclosureAttachment.name = "Nembra Capture V14 — SIMULATOR QA — Capture Complete — Accessibility XXXL — Disclosure"
        disclosureAttachment.lifetime = .keepAlways
        add(disclosureAttachment)

        bringIntoScreenshotViewport(
            completeState,
            in: app,
            context: "Capture Complete state at Accessibility XXXL"
        )
        assertVisibleInScreenshotViewport(
            completeState,
            windowFrame: app.windows.firstMatch.frame,
            context: "Capture Complete state at Accessibility XXXL"
        )
        let completeAttachment = XCTAttachment(screenshot: app.screenshot())
        completeAttachment.name = "Nembra Capture V14 — SIMULATOR QA — Capture Complete — Accessibility XXXL — Complete"
        completeAttachment.lifetime = .keepAlways
        add(completeAttachment)

        bringIntoScreenshotViewport(
            analysisState,
            in: app,
            context: "Ready for analysis state at Accessibility XXXL"
        )
        assertVisibleInScreenshotViewport(
            analysisState,
            windowFrame: app.windows.firstMatch.frame,
            context: "Ready for analysis state at Accessibility XXXL"
        )
        let analysisAttachment = XCTAttachment(screenshot: app.screenshot())
        analysisAttachment.name = "Nembra Capture V14 — SIMULATOR QA — Capture Complete — Accessibility XXXL — Analysis Ready"
        analysisAttachment.lifetime = .keepAlways
        add(analysisAttachment)

        bringIntoScreenshotViewport(
            shareCapture,
            in: app,
            context: "Share Capture action at Accessibility XXXL"
        )
        assertVisibleInScreenshotViewport(
            shareCapture,
            windowFrame: app.windows.firstMatch.frame,
            context: "Share Capture action at Accessibility XXXL"
        )
        let shareAttachment = XCTAttachment(screenshot: app.screenshot())
        shareAttachment.name = "Nembra Capture V14 — SIMULATOR QA — Capture Complete — Accessibility XXXL — Share"
        shareAttachment.lifetime = .keepAlways
        add(shareAttachment)

        bringIntoScreenshotViewport(
            viewDetails,
            in: app,
            context: "View Details action at Accessibility XXXL"
        )
        assertVisibleInScreenshotViewport(
            viewDetails,
            windowFrame: app.windows.firstMatch.frame,
            context: "View Details action at Accessibility XXXL"
        )
        let detailsAttachment = XCTAttachment(screenshot: app.screenshot())
        detailsAttachment.name = "Nembra Capture V14 — SIMULATOR QA — Capture Complete — Accessibility XXXL — View Details"
        detailsAttachment.lifetime = .keepAlways
        add(detailsAttachment)
    }

    @MainActor
    func testV14SimulatorQAHorizonReadyLandscapeKeepsFinishAndTruthVisible() {
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }

        let app = XCUIApplication()
        app.launchArguments = [
            "--es80-passive-capture-simulator-qa",
            "--es80-capture-qa-scenario=observationHorizonReady"
        ]
        app.launch()

        let shell = app.descendants(matching: .any)["es80.capture-shell"]
        XCTAssertTrue(shell.waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = .landscapeLeft

        let qaDisclosure = app.descendants(matching: .any)["es80.capture.simulator-qa"]
        let readyState = app.staticTexts["Capture can be sealed"]
        let finish = app.descendants(matching: .any)["es80.capture.finish"]
        XCTAssertTrue(qaDisclosure.waitForExistence(timeout: 3))
        XCTAssertTrue(readyState.waitForExistence(timeout: 3))
        XCTAssertTrue(finish.waitForExistence(timeout: 3))
        XCTAssertFalse(app.descendants(matching: .any)["es80.capture.field-no-go"].exists)
        XCTAssertFalse(app.buttons["Vehicle controls"].exists)

        let landscapeFrame = app.windows.firstMatch.frame
        XCTAssertGreaterThan(
            landscapeFrame.width,
            landscapeFrame.height,
            "The positive-state visual gate must actually run in landscape."
        )
        assertVisibleInScreenshotViewport(
            qaDisclosure,
            windowFrame: landscapeFrame,
            context: "synthetic Simulator QA disclosure in positive-state landscape"
        )
        let disclosureAttachment = XCTAttachment(screenshot: app.screenshot())
        disclosureAttachment.name = "Nembra Capture V14 — SIMULATOR QA — Horizon Ready — Landscape — Disclosure"
        disclosureAttachment.lifetime = .keepAlways
        add(disclosureAttachment)

        bringIntoScreenshotViewport(
            readyState,
            in: app,
            context: "Horizon-ready state in landscape"
        )
        assertVisibleInScreenshotViewport(
            readyState,
            windowFrame: app.windows.firstMatch.frame,
            context: "Horizon-ready state in landscape"
        )
        let readyAttachment = XCTAttachment(screenshot: app.screenshot())
        readyAttachment.name = "Nembra Capture V14 — SIMULATOR QA — Horizon Ready — Landscape — Status"
        readyAttachment.lifetime = .keepAlways
        add(readyAttachment)

        bringIntoScreenshotViewport(
            finish,
            in: app,
            context: "Seal Capture action in landscape"
        )
        assertVisibleInScreenshotViewport(
            finish,
            windowFrame: app.windows.firstMatch.frame,
            context: "Seal Capture action in landscape"
        )
        let finishAttachment = XCTAttachment(screenshot: app.screenshot())
        finishAttachment.name = "Nembra Capture V14 — SIMULATOR QA — Horizon Ready — Landscape — Seal"
        finishAttachment.lifetime = .keepAlways
        add(finishAttachment)
    }

    @MainActor
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

    @MainActor
    func testV14SimulatorQARetainsPreviouslyUncoveredPortraitStates() {
        struct Scenario {
            let rawValue: String
            let attachmentName: String
            let stableElementIdentifier: String
            let stableText: String
        }

        let scenarios: [Scenario] = [
            .init(
                rawValue: "firstPoweredOff",
                attachmentName: "OFF 1 Ready",
                stableElementIdentifier: "es80.capture.begin-window",
                stableText: "Scooter OFF"
            ),
            .init(
                rawValue: "firstPoweredOn",
                attachmentName: "ON 1 Ready",
                stableElementIdentifier: "es80.capture.begin-window",
                stableText: "Scooter ON"
            ),
            .init(
                rawValue: "targetConfirmation",
                attachmentName: "Target Confirmation",
                stableElementIdentifier: "es80.capture.confirm-correlated-target",
                stableText: "One target repeated twice"
            ),
            .init(
                rawValue: "observationReady",
                attachmentName: "Observation Ready",
                stableElementIdentifier: "es80.capture.finish",
                stableText: "OBSERVATION READY"
            )
        ]

        for scenario in scenarios {
            let app = XCUIApplication()
            app.launchArguments = [
                "--es80-passive-capture-simulator-qa",
                "--es80-capture-qa-scenario=\(scenario.rawValue)"
            ]
            app.launch()

            XCTAssertTrue(
                app.descendants(matching: .any)["es80.capture-shell"].waitForExistence(timeout: 5),
                "\(scenario.rawValue) must render through the real Capture shell."
            )
            XCTAssertTrue(
                app.descendants(matching: .any)["es80.capture.simulator-qa"].waitForExistence(timeout: 3),
                "\(scenario.rawValue) must retain the synthetic/non-authorizing QA disclosure."
            )
            XCTAssertTrue(
                app.descendants(matching: .any)[scenario.stableElementIdentifier].waitForExistence(timeout: 3),
                "\(scenario.rawValue) must expose its expected stable Capture action/state."
            )
            XCTAssertTrue(
                app.staticTexts[scenario.stableText].waitForExistence(timeout: 3),
                "\(scenario.rawValue) must render its expected rider-facing state."
            )
            XCTAssertFalse(
                app.descendants(matching: .any)["es80.capture.field-no-go"].exists,
                "Synthetic QA must exercise the real presentation state instead of the field-lock surface."
            )
            XCTAssertFalse(
                app.buttons["Vehicle controls"].exists,
                "Capture QA must never expose the ordinary vehicle-control surface."
            )

            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "Nembra Capture V14 — SIMULATOR QA — \(scenario.attachmentName) — Portrait"
            attachment.lifetime = .keepAlways
            add(attachment)
            app.terminate()
        }
    }

    func testSimulatorQAAppSeamIsCompileBoundedAndProductionRouteRemainsLocked() throws {
        let appSource = try repositorySource(at: "NembraApp/App/NembraApp.swift")
        let shellSource = try captureShellSource()
        let fixtureSource = try repositorySource(
            at: "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/PassiveBluetoothExperimentOneSimulatorQAFixture.swift"
        )
        let gateSource = try repositorySource(
            at: "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/PassiveBluetoothExperimentOneFieldExecutionGate.swift"
        )

        XCTAssertTrue(appSource.contains("#if DEBUG && targetEnvironment(simulator)"))
        XCTAssertTrue(appSource.contains("--es80-passive-capture-simulator-qa"))
        XCTAssertTrue(
            appSource.contains("if PassiveBluetoothExperimentOneFieldExecutionGate.permitsPhysicalProcedure"),
            "The normal research route must still be downstream of the package field gate."
        )
        XCTAssertTrue(
            appSource.contains("PassiveBluetoothExperimentOneCoordinator.makeAuthorizedES80()"),
            "The real field route must retain its package-owned attested factory."
        )
        XCTAssertTrue(shellSource.contains("simulatorQASnapshot"))
        XCTAssertTrue(shellSource.contains("guard status.physicalProcedurePermitted else"))
        XCTAssertTrue(shellSource.contains("Synthetic Simulator QA presentation only"))
        XCTAssertTrue(fixtureSource.contains("physicalProcedurePermitted: false"))
        XCTAssertTrue(fixtureSource.contains("mayUseBluetoothTransport: false"))
        XCTAssertTrue(gateSource.contains(".noGo(.finalComposedBuildNotAuthorized)"))
        XCTAssertFalse(appSource.contains("permitsPhysicalProcedure = true"))
        XCTAssertFalse(shellSource.contains("permitsPhysicalProcedure = true"))
        XCTAssertFalse(fixtureSource.contains("ForegroundCoreBluetoothCaptureController"))
    }

    func testCompletionSourceRequiresExactFinalShareIntegrityBeforeAnalysisReady() throws {
        let source = try captureShellSource()

        XCTAssertTrue(
            source.contains("coordinator.finalizedShareArtifactForCurrentApplication(setup: setup)"),
            "The app must prepare the package-owned final Share artifact, not stage raw capture or inner export bytes directly."
        )
        XCTAssertTrue(
            source.contains("PassiveBluetoothExperimentOneFinalShareIntegrity.inspect(artifact.json)"),
            "Analysis readiness must come from inspection of the exact final Share bytes."
        )
        XCTAssertTrue(
            source.contains("Text(analysisReady ? \"Ready for analysis\" : \"Integrity check required\")"),
            "Horizon seal alone must not render Ready for analysis."
        )
        XCTAssertTrue(
            source.contains("if let data = finalShareData"),
            "A temporary Share-file retry must reuse retained verified bytes rather than mint a new evidence artifact."
        )
        XCTAssertTrue(
            source.contains("finalShareIntegrityReport = report"),
            "The exact integrity report must be retained as the app's analysis-readiness authority."
        )
        XCTAssertTrue(
            source.contains("coordinator.status.finalizationCleanup == .failed"),
            "Post-seal cleanup failure must remain visible without revoking the sealed artifact."
        )
        XCTAssertFalse(
            source.contains("prepareSoftwareExportForShare()"),
            "The superseded inner-SoftwareExport-only Share path must not remain callable."
        )
        XCTAssertFalse(
            source.contains("softwareExportData"),
            "The app should retain the exact final Share artifact rather than an ambiguous inner-export state."
        )
    }

    @MainActor
    private func bringIntoScreenshotViewport(
        _ element: XCUIElement,
        in app: XCUIApplication,
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
            let windowFrame = app.windows.firstMatch.frame
            let frame = element.frame
            if frame.width > 0,
               frame.height > 0,
               frame.minX >= windowFrame.minX - 1,
               frame.maxX <= windowFrame.maxX + 1,
               frame.minY >= windowFrame.minY - 1,
               frame.maxY <= windowFrame.maxY + 1 {
                return
            }
            app.swipeUp()
            remaining -= 1
        }

        assertVisibleInScreenshotViewport(
            element,
            windowFrame: app.windows.firstMatch.frame,
            context: context,
            file: file,
            line: line
        )
    }

    private func assertVisibleInScreenshotViewport(
        _ element: XCUIElement,
        windowFrame: CGRect,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let frame = element.frame
        XCTAssertGreaterThan(
            frame.width,
            0,
            "Required \(context) must have positive width.",
            file: file,
            line: line
        )
        XCTAssertGreaterThan(
            frame.height,
            0,
            "Required \(context) must have positive height.",
            file: file,
            line: line
        )
        XCTAssertGreaterThanOrEqual(
            frame.minX,
            windowFrame.minX - 1,
            "Required \(context) must not clip off the leading screenshot edge.",
            file: file,
            line: line
        )
        XCTAssertLessThanOrEqual(
            frame.maxX,
            windowFrame.maxX + 1,
            "Required \(context) must not clip off the trailing screenshot edge.",
            file: file,
            line: line
        )
        XCTAssertGreaterThanOrEqual(
            frame.minY,
            windowFrame.minY - 1,
            "Required \(context) must not clip above the screenshot viewport.",
            file: file,
            line: line
        )
        XCTAssertLessThanOrEqual(
            frame.maxY,
            windowFrame.maxY + 1,
            "Required \(context) must not clip below the screenshot viewport.",
            file: file,
            line: line
        )
    }

    private func captureShellSource() throws -> String {
        try repositorySource(at: "NembraApp/Features/Research/ES80CaptureShellView.swift")
    }

    private func repositorySource(at path: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRoot.appendingPathComponent(path)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
