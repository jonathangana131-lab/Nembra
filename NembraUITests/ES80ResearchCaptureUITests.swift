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
            app.staticTexts["Capture isn't ready yet"].waitForExistence(timeout: 3),
            "The current package-owned NO-GO must read as a clear product state rather than an engineering checklist."
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["es80.capture.field-no-go"].waitForExistence(timeout: 3),
            "The dedicated package-gated NO-GO surface must be active."
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["es80.capture.physical-run-locked"].waitForExistence(timeout: 3),
            "The physical NO-GO boundary must be exposed as one stable accessibility element."
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["es80.capture.engineering-details"].waitForExistence(timeout: 3),
            "Exact procedure vocabulary must remain available behind secondary engineering details."
        )
        XCTAssertFalse(
            app.staticTexts["ES80-FINGERPRINT-v1"].exists,
            "Raw recipe vocabulary must not compete with the primary locked-state message before details are requested."
        )
        XCTAssertFalse(
            app.staticTexts["Single-authority workflow installed"].exists,
            "Internal authority vocabulary must not leak into the primary rider-facing state."
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
        attachment.name = "Nembra Capture V14 — Product Physical NO-GO"
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
        let engineeringDetails = app.descendants(matching: .any)["es80.capture.engineering-details"]

        XCTAssertTrue(lockedState.waitForExistence(timeout: 5))
        XCTAssertTrue(physicalBoundary.waitForExistence(timeout: 3))
        XCTAssertTrue(engineeringDetails.waitForExistence(timeout: 3))
        XCTAssertTrue(lockedState.isHittable || lockedState.frame.height > 0)
        XCTAssertTrue(physicalBoundary.frame.height > 0)
        XCTAssertTrue(engineeringDetails.frame.height > 0)

        let windowFrame = app.windows.firstMatch.frame
        for element in [lockedState, physicalBoundary, engineeringDetails] {
            XCTAssertGreaterThanOrEqual(
                element.frame.minX,
                windowFrame.minX - 1,
                "Required NO-GO content must not clip off the leading edge at accessibility sizes."
            )
            XCTAssertLessThanOrEqual(
                element.frame.maxX,
                windowFrame.maxX + 1,
                "Required NO-GO content must not clip off the trailing edge at accessibility sizes."
            )
        }

        XCTAssertFalse(app.staticTexts["ES80-FINGERPRINT-v1"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["es80.capture.begin-window"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["es80.capture.stationary-preflight"].exists)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Nembra Capture V14 — Product NO-GO — Accessibility XXXL"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testV14NoGoLandscapeKeepsAuthorityAndFieldStatusVisible() {
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }

        let app = XCUIApplication()
        app.launchArguments = ["--es80-passive-capture"]
        app.launch()

        XCTAssertTrue(
            app.descendants(matching: .any)["es80.capture.field-no-go"].waitForExistence(timeout: 5)
        )

        XCUIDevice.shared.orientation = .landscapeLeft

        let physicalBoundary = app.descendants(matching: .any)["es80.capture.physical-run-locked"]
        let engineeringDetails = app.descendants(matching: .any)["es80.capture.engineering-details"]
        XCTAssertTrue(physicalBoundary.waitForExistence(timeout: 3))
        XCTAssertTrue(engineeringDetails.waitForExistence(timeout: 3))
        XCTAssertGreaterThan(physicalBoundary.frame.height, 0)
        XCTAssertGreaterThan(engineeringDetails.frame.height, 0)
        XCTAssertFalse(app.staticTexts["ES80-FINGERPRINT-v1"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["es80.capture.begin-window"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["es80.capture.stationary-preflight"].exists)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Nembra Capture V14 — Product NO-GO — Landscape"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testNoGoPrimaryCopyKeepsEngineeringVocabularySecondary() throws {
        let source = try nembraAppSource()

        XCTAssertTrue(source.contains("Text(\"Capture isn't ready yet\")"))
        XCTAssertTrue(source.contains("DisclosureGroup(\"Engineering details\")"))
        XCTAssertTrue(source.contains("Text(recipeID)"))
        XCTAssertFalse(source.contains("Text(\"Single-authority workflow installed\")"))
        XCTAssertFalse(source.contains("final composed app, lifecycle authority, provenance, runtime, visual, accessibility, performance, and runbook gates"))
        XCTAssertFalse(source.contains("package-owned authorization; a UI flag, typed identifier, or local preference"))
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

    private func captureShellSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRoot
            .appendingPathComponent("NembraApp/Features/Research/ES80CaptureShellView.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private func nembraAppSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRoot
            .appendingPathComponent("NembraApp/App/NembraApp.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
