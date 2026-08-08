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
            app.staticTexts["Capture not ready"].waitForExistence(timeout: 3),
            "The current package-owned NO-GO must be the primary product state without engineering-gate jargon."
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
            "The installed versioned recipe must be identified without becoming executable."
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["es80.capture.build-identity"].waitForExistence(timeout: 3),
            "The locked surface must expose package-derived runtime build identity or an explicit fail-closed unavailable state."
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
        attachment.name = "Nembra Capture V14 — Physical Capture Locked"
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
            context: "primary locked state at Accessibility XXXL"
        )
        assertVisibleInScreenshotViewport(
            physicalBoundary,
            windowFrame: windowFrame,
            context: "physical-capture boundary at Accessibility XXXL"
        )
        assertVisibleInScreenshotViewport(
            recipe,
            windowFrame: windowFrame,
            context: "recipe identity at Accessibility XXXL"
        )

        XCTAssertFalse(app.descendants(matching: .any)["es80.capture.begin-window"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["es80.capture.stationary-preflight"].exists)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Nembra Capture V14 — Locked — Accessibility XXXL"
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
            context: "primary locked state in landscape"
        )
        assertVisibleInScreenshotViewport(
            physicalBoundary,
            windowFrame: windowFrame,
            context: "physical-capture boundary in landscape"
        )
        assertVisibleInScreenshotViewport(
            recipe,
            windowFrame: windowFrame,
            context: "recipe identity in landscape"
        )

        XCTAssertFalse(app.descendants(matching: .any)["es80.capture.begin-window"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["es80.capture.stationary-preflight"].exists)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Nembra Capture V14 — Locked — Landscape"
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

    func testNoGoSourceUsesPackageRuntimeBuildIdentityReader() throws {
        let source = try nembraAppSource()

        XCTAssertTrue(
            source.contains("PassiveBluetoothCaptureRuntimeBuildIdentityReader.currentApplication()"),
            "The field-lock surface must consume the package-owned fail-closed runtime build identity reader instead of reconstructing build provenance in SwiftUI."
        )
        XCTAssertTrue(
            source.contains("accessibilityIdentifier(\"es80.capture.build-identity\")"),
            "The app-visible build identity must remain a stable acceptance surface."
        )
        XCTAssertTrue(
            source.contains("runtimeBuildIdentity.buildIdentifier"),
            "The human-readable build identifier must remain visible without rider transcription."
        )
        XCTAssertTrue(
            source.contains("runtimeBuildIdentity.sourceCommitSHA"),
            "The exact embedded source commit must remain available in secondary build details."
        )
        XCTAssertTrue(
            source.contains("runtimeBuildIdentity.buildInstanceID"),
            "The produced-build rendezvous identity must remain available without granting field authority."
        )
        XCTAssertTrue(
            source.contains("DisclosureGroup(\"Build details\")"),
            "Raw source/build-instance identifiers belong in secondary Build details rather than the rider's primary lock hierarchy."
        )
        XCTAssertTrue(
            source.contains("Build identity unavailable"),
            "Failure to read exact runtime build identity must remain an explicit fail-closed product state."
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
        XCTAssertGreaterThan(frame.width, 0, "Required \(context) must have positive width.", file: file, line: line)
        XCTAssertGreaterThan(frame.height, 0, "Required \(context) must have positive height.", file: file, line: line)
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
