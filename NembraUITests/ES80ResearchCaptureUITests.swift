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
            app.staticTexts["Field capture locked"].waitForExistence(timeout: 3),
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
        XCTAssertTrue(
            app.staticTexts["ES80-FINGERPRINT-v1"].waitForExistence(timeout: 3),
            "The installed versioned procedure must be identified without becoming executable."
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

    func testStationarySetupRequiresExplicitChargerDeclarationAndConnectedStateFailsClosed() throws {
        let source = try captureShellSource()

        XCTAssertTrue(
            source.contains("@State private var selectedChargerState: PassiveBluetoothStationaryCaptureChargerState?"),
            "The operator's visible charger choice must be retained separately from confirmed setup provenance."
        )
        XCTAssertTrue(source.contains("CHARGER UNPLUGGED"))
        XCTAssertTrue(source.contains("CHARGER CONNECTED"))
        XCTAssertTrue(source.contains("identifier: \"es80.capture.charger-unplugged\""))
        XCTAssertTrue(source.contains("identifier: \"es80.capture.charger-connected\""))
        XCTAssertTrue(
            source.contains("if selectedChargerState == .disconnected"),
            "Only an explicitly selected unplugged state may expose setup confirmation."
        )
        XCTAssertTrue(
            source.contains("else if selectedChargerState == .connected"),
            "A connected charger declaration must remain an explicit fail-closed product state."
        )
        XCTAssertTrue(
            source.contains("Charger connected. Unplug the scooter charger"),
            "The connected state must give a visible corrective action instead of silently coercing provenance."
        )
        XCTAssertTrue(
            source.contains("chargerState: .disconnected"),
            "Confirmed stationary setup must retain the exact allowed charger declaration."
        )
        XCTAssertTrue(
            source.contains("selectedChargerState = nil"),
            "A fresh Experiment One must not inherit an earlier charger choice."
        )
        XCTAssertFalse(
            source.contains("Confirm only when those are your declared setup conditions"),
            "The old one-tap path that silently wrote disconnected provenance must be removed."
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
