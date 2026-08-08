import Foundation
import XCTest

final class ES80CaptureSoftwareExportShareTests: XCTestCase {
    func testCompletionSharesPackageOwnedSoftwareExportInsteadOfRawControllerJSON() throws {
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

    func testPostSealExportPreparationFailurePreservesLegitimateCaptureAndRetryPath() throws {
        let source = try captureShellSource()

        XCTAssertTrue(
            source.contains("_ = try await coordinator.finalizeObservationHorizon()"),
            "Immutable Horizon finalization must remain the authority boundary before export preparation."
        )
        XCTAssertTrue(
            source.contains("prepareSoftwareExportForShare()"),
            "A sealed capture should prepare its share envelope as a separate post-finalization operation."
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
