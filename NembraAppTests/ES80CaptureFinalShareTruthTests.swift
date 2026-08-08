import Foundation
import XCTest

final class ES80CaptureFinalShareTruthTests: XCTestCase {
    func testFinalShareUsesVerifiedPackageExportInsteadOfRawControllerJSON() throws {
        let shellURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("NembraApp/Features/Research/ES80CaptureShellView.swift")
        let source = try String(contentsOf: shellURL, encoding: .utf8)

        XCTAssertFalse(
            source.contains("shareURL = try persistShareArtifact(artifact.captureJSON)"),
            "Raw sealed controller JSON drops same-run correlation evidence and build/procedure provenance. It must never be surfaced as the primary Capture share artifact."
        )
        XCTAssertFalse(
            source.contains("persistShareArtifact(finalizedArtifact.captureJSON)"),
            "Renaming the finalized artifact must not reintroduce raw-controller-JSON sharing."
        )

        let makeRange = try XCTUnwrap(
            source.range(of: "PassiveBluetoothExperimentOneSoftwareExportCodec\n                    .makeForCurrentApplication(finalizedArtifact: finalizedArtifact)")
        )
        let encodeRange = try XCTUnwrap(
            source.range(of: "PassiveBluetoothExperimentOneSoftwareExportCodec\n                    .encode(softwareExport)")
        )
        let verifyRange = try XCTUnwrap(
            source.range(of: "PassiveBluetoothExperimentOneSoftwareExportCodec.decodeAndVerify(shareJSON)")
        )
        let persistRange = try XCTUnwrap(
            source.range(of: "shareURL = try persistShareArtifact(shareJSON)")
        )

        XCTAssertLessThan(makeRange.lowerBound, encodeRange.lowerBound)
        XCTAssertLessThan(encodeRange.lowerBound, verifyRange.lowerBound)
        XCTAssertLessThan(verifyRange.lowerBound, persistRange.lowerBound)
        XCTAssertTrue(
            source.contains("Label(\"Share Capture\", systemImage: \"square.and.arrow.up\")"),
            "Once the package-owned software export has been encoded and replay-verified, the product should retain the primary Share Capture affordance."
        )
    }

    func testDeclaredStationaryExportSetupIsVisibleInOperatorInstructions() throws {
        let shellURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("NembraApp/Features/Research/ES80CaptureShellView.swift")
        let source = try String(contentsOf: shellURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("charger disconnected"),
            "The software export declares chargerState disconnected, so the product workflow must visibly instruct that condition instead of silently recording it as provenance."
        )
        XCTAssertTrue(
            source.contains("stock app closed"),
            "The software export declares no stock-app reference, so the operator workflow must keep the stock scooter app closed."
        )
    }
}
