import Foundation
import Testing

@Suite("Capture synthetic representative screenshot viewport acceptance")
struct ES80CaptureRepresentativeViewportAcceptanceTests {
    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func uiTestSource() throws -> String {
        try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("NembraCaptureUITests")
                .appendingPathComponent("NembraCaptureUITests.swift"),
            encoding: .utf8
        )
    }

    private static func section(
        in source: String,
        from startNeedle: String,
        to endNeedle: String
    ) throws -> Substring {
        let start = try #require(
            source.range(of: startNeedle)
        )
        let end = try #require(
            source.range(
                of: endNeedle,
                range: start.lowerBound..<source.endIndex
            )
        )
        return source[start.lowerBound..<end.lowerBound]
    }

    @Test("retained synthetic screenshots reveal a required action before capture")
    func representativeSyntheticScreenshotsRequireActionViewportEvidence() throws {
        let source = try Self.uiTestSource()
        let representatives = [
            (
                start: "func testSyntheticSafetySheetAtAccessibilityXXXLKeepsDisclosureAndConfirmationReachable()",
                end: "func testSyntheticCorrelationWithNoRepeatableTargetStopsWithoutConfirmation()",
                reveal: "reveal(confirm, in: app)",
                screenshot: "keepSyntheticScreenshot(named: \"SAFETY-SHEET-AX-XXXL\")"
            ),
            (
                start: "func testSyntheticSingleCorrelationRequiresConfirmationBeforeObservationPresentation()",
                end: "func testSyntheticCorrelationToObservationFitsCompactLandscape()",
                reveal: "reveal(confirm, in: app)",
                screenshot: "keepSyntheticScreenshot(named: \"CORRELATION-SUCCESS\")"
            ),
            (
                start: "func testSyntheticCorrelationToObservationFitsCompactLandscape()",
                end: "func testSyntheticObservationCompletionPresentationStillRequiresIntegrityBeforeComplete()",
                reveal: "reveal(app.buttons[\"nembra.capture.qa.complete-observation\"], in: app)",
                screenshot: "keepSyntheticScreenshot(named: \"CORRELATION-OBSERVATION-COMPACT-LANDSCAPE\")"
            )
        ]

        for representative in representatives {
            let block = try Self.section(
                in: source,
                from: representative.start,
                to: representative.end
            )
            let reveal = try #require(block.range(of: representative.reveal))
            let screenshot = try #require(block.range(of: representative.screenshot))
            #expect(
                reveal.lowerBound < screenshot.lowerBound,
                "The required action must be scrolled into a hittable viewport before retaining the synthetic screenshot."
            )
        }

        let revealHelper = try Self.section(
            in: source,
            from: "private func reveal(",
            to: "private func waitForHittable("
        )
        #expect(revealHelper.contains("XCTAssertTrue(waitForHittable(element, timeout: 2))"))
        #expect(source.contains("XCTAttachment(screenshot: XCUIScreen.main.screenshot())"))
        #expect(source.contains("screenshot.name = \"SYNTHETIC-QA-\\(name)\""))
        #expect(source.contains("syntheticDisclosureIdentifier"))
    }
}
