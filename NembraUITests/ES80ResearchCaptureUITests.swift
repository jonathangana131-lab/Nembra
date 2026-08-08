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
            "The current package-owned lock must remain the primary rider-facing product state."
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
        XCTAssertTrue(
            app.descendants(matching: .any)["es80.capture.build-identity"].waitForExistence(timeout: 3),
            "The locked surface must expose the running build identity or its fail-closed unavailable state."
        )

        XCTAssertFalse(app.descendants(matching: .any)["es80.capture.stationary-preflight"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["es80.capture.preflight.charger-disconnected"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["es80.capture.preflight.charger-connected"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["es80.capture.preflight.continue"].exists)
        XCTAssertFalse(app.buttons["Begin OFF 1 window"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["es80.capture.begin-window"].exists)
        XCTAssertFalse(app.buttons["Scan for scooter"].exists)
        XCTAssertFalse(app.buttons["Start passive capture"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["es80.capture.start"].exists)
        XCTAssertFalse(app.buttons["Finish Capture"].exists)
        XCTAssertFalse(app.buttons["Vehicle controls"].exists)
        XCTAssertFalse(app.buttons["Advanced details"].exists)

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
        let buildIdentity = app.descendants(matching: .any)["es80.capture.build-identity"]

        XCTAssertTrue(lockedState.waitForExistence(timeout: 5))
        XCTAssertTrue(physicalBoundary.waitForExistence(timeout: 3))
        XCTAssertTrue(recipe.waitForExistence(timeout: 3))
        XCTAssertTrue(buildIdentity.waitForExistence(timeout: 3))
        XCTAssertTrue(lockedState.isHittable || lockedState.frame.height > 0)
        XCTAssertTrue(physicalBoundary.frame.height > 0)
        XCTAssertTrue(recipe.frame.height > 0)
        XCTAssertTrue(buildIdentity.frame.height > 0)

        let windowFrame = app.windows.firstMatch.frame
        for element in [lockedState, physicalBoundary, recipe, buildIdentity] {
            XCTAssertGreaterThanOrEqual(element.frame.minX, windowFrame.minX - 1)
            XCTAssertLessThanOrEqual(element.frame.maxX, windowFrame.maxX + 1)
        }

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
        XCTAssertTrue(app.descendants(matching: .any)["es80.capture.field-no-go"].waitForExistence(timeout: 5))

        XCUIDevice.shared.orientation = .landscapeLeft

        let physicalBoundary = app.descendants(matching: .any)["es80.capture.physical-run-locked"]
        let recipe = app.staticTexts["ES80-FINGERPRINT-v1"]
        let buildIdentity = app.descendants(matching: .any)["es80.capture.build-identity"]
        XCTAssertTrue(physicalBoundary.waitForExistence(timeout: 3))
        XCTAssertTrue(recipe.waitForExistence(timeout: 3))
        XCTAssertTrue(buildIdentity.waitForExistence(timeout: 3))
        XCTAssertGreaterThan(physicalBoundary.frame.height, 0)
        XCTAssertGreaterThan(recipe.frame.height, 0)
        XCTAssertGreaterThan(buildIdentity.frame.height, 0)
        XCTAssertFalse(app.descendants(matching: .any)["es80.capture.begin-window"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["es80.capture.stationary-preflight"].exists)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Nembra Capture V14 — NO-GO — Landscape"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testCompletionSourceRequiresExactFinalShareIntegrityBeforeAnalysisReady() throws {
        let source = try captureShellSource()
        XCTAssertTrue(source.contains("coordinator.finalizedShareArtifactForCurrentApplication(setup: setup)"))
        XCTAssertTrue(source.contains("PassiveBluetoothExperimentOneFinalShareIntegrity.inspect(artifact.json)"))
        XCTAssertTrue(source.contains("Text(analysisReady ? \"Ready for analysis\" : \"Integrity check required\")"))
        XCTAssertTrue(source.contains("if let data = finalShareData"))
        XCTAssertTrue(source.contains("finalShareIntegrityReport = report"))
        XCTAssertTrue(source.contains("coordinator.status.finalizationCleanup == .failed"))
        XCTAssertFalse(source.contains("prepareSoftwareExportForShare()"))
        XCTAssertFalse(source.contains("softwareExportData"))
    }

    func testNoGoSourceUsesPackageRuntimeBuildIdentityReader() throws {
        let source = try nembraAppSource()
        XCTAssertTrue(source.contains("PassiveBluetoothCaptureRuntimeBuildIdentityReader.currentApplication()"))
        XCTAssertTrue(source.contains("accessibilityIdentifier(\"es80.capture.build-identity\")"))
        XCTAssertTrue(source.contains("runtimeBuildIdentity.buildIdentifier"))
        XCTAssertTrue(source.contains("runtimeBuildIdentity.sourceCommitSHA"))
        XCTAssertTrue(source.contains("runtimeBuildIdentity.buildInstanceID"))
        XCTAssertTrue(source.contains("Build identity unavailable"))
    }

    private func captureShellSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFile.deletingLastPathComponent().deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot.appendingPathComponent("NembraApp/Features/Research/ES80CaptureShellView.swift"),
            encoding: .utf8
        )
    }

    private func nembraAppSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFile.deletingLastPathComponent().deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot.appendingPathComponent("NembraApp/App/NembraApp.swift"),
            encoding: .utf8
        )
    }
}