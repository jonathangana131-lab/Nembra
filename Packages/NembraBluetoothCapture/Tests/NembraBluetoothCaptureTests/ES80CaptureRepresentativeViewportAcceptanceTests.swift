import Foundation
import Testing

@Suite("ES80 Capture representative screenshot viewport acceptance")
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
                .appendingPathComponent("NembraUITests")
                .appendingPathComponent("ES80ResearchCaptureUITests.swift"),
            encoding: .utf8
        )
    }

    private static func representativeMatrix(in source: String) throws -> Substring {
        let start = try #require(
            source.range(
                of: "func testV14SimulatorQACapturesRepresentativeInProgressAndRecoveryStates()"
            )
        )
        let end = try #require(
            source.range(
                of: "func testSimulatorQAAppSeamIsCompileBoundedAndProductionRouteRemainsLocked()",
                range: start.lowerBound..<source.endIndex
            )
        )
        return source[start.lowerBound..<end.lowerBound]
    }

    @Test("representative screenshots prove required state is inside the captured viewport")
    func representativeScreenshotsRequireViewportEvidence() throws {
        let source = try Self.uiTestSource()
        let matrix = try Self.representativeMatrix(in: source)

        let assertionToken = "assertVisibleInScreenshotViewport("
        let navigationToken = "bringIntoScreenshotViewport("
        let screenshotToken = "XCTAttachment(screenshot: app.screenshot())"

        let assertionCount = matrix.components(separatedBy: assertionToken).count - 1
        let navigationCount = matrix.components(separatedBy: navigationToken).count - 1

        #expect(
            assertionCount >= 3,
            "The representative matrix must mechanically prove the Simulator QA disclosure, rider-facing state, and any required action are inside the screenshot viewport."
        )
        #expect(
            navigationCount >= 2,
            "Scrollable representative states must be brought into the screenshot viewport before their retained evidence is captured."
        )

        let firstViewportAssertion = try #require(matrix.range(of: assertionToken))
        let firstScreenshot = try #require(matrix.range(of: screenshotToken))
        #expect(
            firstViewportAssertion.lowerBound < firstScreenshot.lowerBound,
            "Viewport proof must happen before the representative screenshot is retained."
        )

        #expect(matrix.contains("es80.capture.simulator-qa"))
        #expect(matrix.contains("expectation.requiredText"))
        #expect(matrix.contains("expectation.requiredIdentifier"))
    }
}
