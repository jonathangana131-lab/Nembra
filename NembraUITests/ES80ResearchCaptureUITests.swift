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
        let testFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRoot
            .appendingPathComponent("NembraApp/Features/Research/ES80CaptureShellView.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
