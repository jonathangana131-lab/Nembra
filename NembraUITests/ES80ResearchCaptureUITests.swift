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

    func testV14CompletionSourceSharesPackageOwnedSoftwareExportInsteadOfRawControllerJSON() throws {
        let source = try captureShellSource()

        XCTAssertTrue(
            source.contains("coordinator.encodedFinalizedSoftwareExportForCurrentApplication()"),
            "The product Share path must consume the package-owned Experiment One software export so capture bytes, same-run correlation, recipe, manifest, and build provenance stay mechanically bound."
        )
        XCTAssertTrue(
            source.contains("ShareLink(item: softwareExportURL)"),
            "Share Capture must point at the prepared package-owned software evidence bundle."
        )
        XCTAssertFalse(
            source.contains("ShareLink(item: shareURL)"),
            "Raw controller JSON must not masquerade as the final Capture share artifact."
        )
        XCTAssertFalse(
            source.contains("@State private var shareURL: URL?"),
            "SwiftUI must not retain the legacy app-owned raw JSON share state."
        )
        XCTAssertFalse(
            source.contains("persistShareArtifact(artifact.captureJSON)"),
            "Immutable controller JSON is one input to the package envelope, not the user-facing final Share object."
        )
        XCTAssertTrue(
            source.contains("Nembra-ES80-Experiment-One-Software-Export-"),
            "The prepared file should be named as a software evidence export rather than implying independently accepted field authorization."
        )
    }

    func testV14PostSealSharePreparationFailurePreservesCaptureAndRetryPath() throws {
        let source = try captureShellSource()

        XCTAssertTrue(
            source.contains("_ = try await coordinator.finalizeObservationHorizon()"),
            "Immutable Horizon finalization must remain the authority boundary before export preparation."
        )
        XCTAssertTrue(
            source.contains("Capture is sealed, but its software evidence bundle could not be prepared"),
            "A packaging/provenance failure after Horizon must be described as a Share preparation problem, not as loss of already-sealed capture evidence."
        )
        XCTAssertTrue(
            source.contains("Retry Share Preparation"),
            "The completed state must let the operator retry export preparation without repeating physical evidence collection."
        )
        XCTAssertTrue(
            source.contains("View Details"),
            "Already-legitimate sealed evidence must remain inspectable when Share preparation is unavailable."
        )
        XCTAssertTrue(
            source.contains("External accepted field-build / GO authority remains separate."),
            "The app must not promote a locally produced software envelope into physical field authorization."
        )
    }

    private func captureShellSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let shellURL = repositoryRoot
            .appendingPathComponent("NembraApp")
            .appendingPathComponent("Features")
            .appendingPathComponent("Research")
            .appendingPathComponent("ES80CaptureShellView.swift")

        return try String(contentsOf: shellURL, encoding: .utf8)
    }
}
