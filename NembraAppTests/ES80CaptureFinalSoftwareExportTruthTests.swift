import Foundation
import XCTest

final class ES80CaptureFinalSoftwareExportTruthTests: XCTestCase {
    func testFinalShareUsesPackageSoftwareExportInsteadOfRawControllerJSON() throws {
        let shellURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("NembraApp/Features/Research/ES80CaptureShellView.swift")
        let source = try String(contentsOf: shellURL, encoding: .utf8)

        XCTAssertFalse(
            source.contains("shareURL = try persistShareArtifact(artifact.captureJSON)"),
            "Raw sealed controller JSON must not be surfaced as the final Share Capture artifact."
        )
        XCTAssertTrue(
            source.contains("finalizedSoftwareExportForCurrentApplication("),
            "The app-visible completion path must use the package-owned finalized software export."
        )
        XCTAssertTrue(
            source.contains("PassiveBluetoothExperimentOneSoftwareExportCodec.decodeAndVerify(encoded)"),
            "The exact encoded bytes destined for Share must pass the package verifier before the affordance appears."
        )
        XCTAssertTrue(
            source.contains("shareURL = try persistShareArtifact(encoded)"),
            "Share Capture must persist the verified software envelope rather than a detached inner payload."
        )
        XCTAssertTrue(
            source.contains("Share remains blocked so raw controller JSON cannot masquerade as the completed software artifact."),
            "If export preparation fails after sealing, legitimate evidence must remain retained while Share fails closed."
        )
    }

    func testDeclaredStationarySetupIsVisibleInTheOperatorProcedure() throws {
        let shellURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("NembraApp/Features/Research/ES80CaptureShellView.swift")
        let source = try String(contentsOf: shellURL, encoding: .utf8)

        XCTAssertTrue(source.contains("chargerState: .disconnected"))
        XCTAssertTrue(source.contains("executionContext: .foregroundUnlockedScreenOn"))
        XCTAssertTrue(source.contains("stockAppReferenceSetup: .none"))
        XCTAssertTrue(
            source.contains("keep the charger disconnected and the stock app closed"),
            "The product must instruct the operator to follow the same stationary setup it declares in the export manifest."
        )
        XCTAssertTrue(
            source.contains("build-instance/runtime hashes do not independently authorize a field build"),
            "The app must keep software provenance distinct from physical GO authority."
        )
    }
}