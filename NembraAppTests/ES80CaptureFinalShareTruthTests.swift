import Foundation
import XCTest

final class ES80CaptureFinalShareTruthTests: XCTestCase {
    func testFinalShareNeverPublishesRawControllerJSONAsFieldArtifact() throws {
        let shellURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("NembraApp/Features/Research/ES80CaptureShellView.swift")
        let source = try String(contentsOf: shellURL, encoding: .utf8)

        XCTAssertFalse(
            source.contains("shareURL = try persistShareArtifact(artifact.captureJSON)"),
            "Raw sealed controller JSON drops the coordinator-retained four-window correlation evidence and accepted build/procedure provenance. It must not be surfaced as the final physical field artifact."
        )

        XCTAssertFalse(
            source.contains("Label(\"Share Capture\", systemImage: \"square.and.arrow.up\")"),
            "Do not label a raw controller-JSON share affordance as the completed Capture export before one package-owned envelope binds capture bytes, correlation evidence, recipe, and accepted build provenance."
        )
    }
}
