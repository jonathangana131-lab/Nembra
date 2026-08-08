import Foundation
import XCTest

final class ES80CaptureFinalExportTruthTests: XCTestCase {
    func testFinalShareUsesPackageOwnedVerifiedEnvelopeInsteadOfRawControllerJSON() throws {
        let shellURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("NembraApp/Features/Research/ES80CaptureShellView.swift")
        let source = try String(contentsOf: shellURL, encoding: .utf8)

        XCTAssertFalse(
            source.contains("shareURL = try persistShareArtifact(artifact.captureJSON)"),
            "Raw sealed controller JSON must never be surfaced as the final physical field artifact."
        )
        XCTAssertTrue(
            source.contains("PassiveBluetoothExperimentOneExportArtifactJSON.make("),
            "The app-visible completion path must ask the package to compose the final Experiment One envelope."
        )
        XCTAssertTrue(
            source.contains("PassiveBluetoothCaptureRuntimeBuildIdentityReader.currentApplication()"),
            "Final export must bind provenance from the exact running application rather than rider-entered metadata."
        )
        XCTAssertTrue(
            source.contains("shareURL = try persistShareArtifact(fieldArtifact)"),
            "Share Capture must persist the verified package envelope, not one detached inner payload."
        )
        XCTAssertTrue(
            source.contains("Share remains blocked so raw controller JSON cannot masquerade as the field artifact."),
            "A sealed capture whose final envelope cannot be prepared must retain evidence while blocking a misleading Share affordance."
        )
    }
}