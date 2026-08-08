import Foundation
import XCTest

final class ES80CaptureFinalExportTruthTests: XCTestCase {
    func testCompletionDoesNotExposeRawControllerJSONAsFinalShareArtifact() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let shellURL = repositoryRoot
            .appendingPathComponent("NembraApp")
            .appendingPathComponent("Features")
            .appendingPathComponent("Research")
            .appendingPathComponent("ES80CaptureShellView.swift")

        let source = try String(contentsOf: shellURL, encoding: .utf8)

        XCTAssertFalse(
            source.contains("ShareLink(item: shareURL)"),
            "Raw sealed controller JSON is only analyzer/QA plumbing until correlation evidence plus accepted build/procedure provenance are bound into one package-owned export envelope."
        )
        XCTAssertFalse(
            source.contains("@State private var shareURL: URL?"),
            "The app must not retain an app-owned raw-JSON share URL as though it were the final physical field artifact."
        )
        XCTAssertTrue(
            source.contains("View Details"),
            "Completion should still expose the truthful evidence details while final export authority is unavailable."
        )
    }
}
