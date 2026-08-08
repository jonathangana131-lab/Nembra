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
            app.staticTexts["This build is still finishing its final checks before it can collect real ES80 data."].waitForExistence(timeout: 3),
            "The primary lock reason must remain rider-readable without exposing internal acceptance machinery."
        )
        XCTAssertTrue(
            app.staticTexts["Not ready for scooter capture yet"].waitForExistence(timeout: 3),
            "The visible blocker must remain expressed in rider-facing product language."
        )
        XCTAssertTrue(
            app.staticTexts["Capture workflow installed"].waitForExistence(timeout: 3),
            "The installed software state must remain visible without internal authority terminology."
        )
        XCTAssertTrue(
            app.staticTexts["Scooter capture unavailable on this build"].waitForExistence(timeout: 3),
            "The build lock must remain explicit without implying physical approval."
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["es80.capture.field-no-go"].waitForExistence(timeout: 3),
            "The dedicated package-gated NO-GO surface must be active."
        )

        let physicalBoundary = app.descendants(matching: .any)["es80.capture.physical-run-locked"]
        XCTAssertTrue(
            physicalBoundary.waitForExistence(timeout: 3),
            "The physical NO-GO boundary must be exposed as one stable accessibility element."
        )
        for forbiddenJargon in ["lifecycle authority", "provenance", "runbook gates", "GO authorization"] {
            XCTAssertFalse(
                physicalBoundary.label.localizedCaseInsensitiveContains(forbiddenJargon),
                "The rider-facing accessible lock explanation must not expose internal engineering terminology: \(forbiddenJargon)."
            )
        }
        XCTAssertFalse(app.staticTexts["Physical Experiment One locked"].exists)
        XCTAssertFalse(app.staticTexts["Single-authority workflow installed"].exists)
        XCTAssertFalse(app.staticTexts["Field execution unavailable on this build"].exists)
        XCTAssertFalse(app.staticTexts["NO-GO"].exists)

        XCTAssertTrue(
            app.staticTexts["ES80-FINGERPRINT-v1"].waitForExistence(timeout: 3),
            "The installed versioned procedure must be identified without becoming executable."
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
        attachment.name = "Nembra Capture V14 — Package-Owned Physical NO-GO"
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
        let physicalBoundary = app.descendants(matching: .any)["es80.capture.physical-run-locked"]
        let recipe = app.staticTexts["ES80-FINGERPRINT-v1"]

        XCTAssertTrue(lockedState.waitForExistence(timeout: 5))
        XCTAssertTrue(physicalBoundary.waitForExistence(timeout: 3))
        XCTAssertTrue(recipe.waitForExistence(timeout: 3))

        let windowFrame = app.windows.firstMatch.frame
        assertVisibleInScreenshotViewport(
            lockedState,
            windowFrame: windowFrame,
            context: "primary NO-GO state at Accessibility XXXL"
        )
        assertVisibleInScreenshotViewport(
            physicalBoundary,
            windowFrame: windowFrame,
            context: "physical-run boundary at Accessibility XXXL"
        )
        assertVisibleInScreenshotViewport(
            recipe,
            windowFrame: windowFrame,
            context: "recipe identity at Accessibility XXXL"
        )

        XCTAssertFalse(app.descendants(matching: .any)["es80.capture.begin-window"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["es80.capture.stationary-preflight"].exists)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Nembra Capture V14 — NO-GO — Accessibility XXXL"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testV14NoGoLandscapeKeepsAuthorityAndProcedureVisible() {
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
        let physicalBoundary = app.descendants(matching: .any)["es80.capture.physical-run-locked"]
        let recipe = app.staticTexts["ES80-FINGERPRINT-v1"]
        XCTAssertTrue(lockedState.waitForExistence(timeout: 3))
        XCTAssertTrue(physicalBoundary.waitForExistence(timeout: 3))
        XCTAssertTrue(recipe.waitForExistence(timeout: 3))

        let windowFrame = app.windows.firstMatch.frame
        assertVisibleInScreenshotViewport(
            lockedState,
            windowFrame: windowFrame,
            context: "primary NO-GO state in landscape"
        )
        assertVisibleInScreenshotViewport(
            physicalBoundary,
            windowFrame: windowFrame,
            context: "physical-run boundary in landscape"
        )
        assertVisibleInScreenshotViewport(
            recipe,
            windowFrame: windowFrame,
            context: "recipe identity in landscape"
        )

        XCTAssertFalse(app.descendants(matching: .any)["es80.capture.begin-window"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["es80.capture.stationary-preflight"].exists)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Nembra Capture V14 — NO-GO — Landscape"
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
