import Foundation
import Testing

@Suite("Capture Dynamic Type source acceptance")
struct ES80CaptureDynamicTypeSourceAcceptanceTests {
    private static func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func entrypointSource() throws -> String {
        try String(
            contentsOf: repositoryRoot()
                .appendingPathComponent("NembraApp")
                .appendingPathComponent("App")
                .appendingPathComponent("NembraCaptureEntrypoint.swift"),
            encoding: .utf8
        )
    }

    private static func captureUITestSource() throws -> String {
        try String(
            contentsOf: repositoryRoot()
                .appendingPathComponent("NembraCaptureUITests")
                .appendingPathComponent("NembraCaptureUITests.swift"),
            encoding: .utf8
        )
    }

    private static func section(
        _ source: String,
        from startNeedle: String,
        to endNeedle: String
    ) throws -> Substring {
        let start = try #require(source.range(of: startNeedle))
        let end = try #require(
            source.range(
                of: endNeedle,
                range: start.lowerBound..<source.endIndex
            )
        )
        return source[start.lowerBound..<end.lowerBound]
    }

    @Test("active Capture root deliberately adapts and remains scrollable at accessibility sizes")
    func activeCaptureRootAdaptsForDynamicType() throws {
        let source = try Self.entrypointSource()
        let root = try Self.section(
            source,
            from: "private struct CaptureP0Root: View",
            to: "private final class SecureLinkController"
        )

        #expect(root.contains("@Environment(\\.dynamicTypeSize) private var dynamicTypeSize"))
        #expect(root.contains("dynamicTypeSize.isAccessibilitySize"))
        #expect(root.contains("ScrollView"))
        #expect(root.contains("spacing: isAccessibilityLayout ? 16 : 22"))
        #expect(root.contains("nembra.capture.root.account-link-action"))
        #expect(root.contains(".frame(maxWidth: .infinity, minHeight: 52)"))
    }

    @Test("active secure-link flow recomposes dense progress and observation content")
    func secureLinkFlowRecomposesForDynamicType() throws {
        let source = try Self.entrypointSource()
        let secureLink = try Self.section(
            source,
            from: "private struct SecureLinkView: View",
            to: "struct CaptureCorrelationSuccessPresentation: View"
        )

        #expect(secureLink.contains("@Environment(\\.dynamicTypeSize) private var dynamicTypeSize"))
        #expect(secureLink.contains("ScrollView"))
        #expect(secureLink.contains("if dynamicTypeSize.isAccessibilitySize"))
        #expect(secureLink.contains("VStack(alignment: .leading, spacing: 8)"))
        #expect(secureLink.contains("nembra.capture.observation.surface"))
        #expect(secureLink.contains(".fixedSize(horizontal: false, vertical: true)"))
    }

    @Test("public-build Accessibility XXXL UI evidence keeps its only action usable")
    func publicBuildAccessibilityXXXLActionEvidenceIsRequired() throws {
        let source = try Self.captureUITestSource()
        let block = try Self.section(
            source,
            from: "func testAccessibilityXXXLKeepsTheOnlyPublicActionUsable()",
            to: "func testUnknownSyntheticScenarioBlocksInsteadOfOpeningLiveCapture()"
        )

        #expect(block.contains("-UIPreferredContentSizeCategoryName"))
        #expect(block.contains("UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"))
        #expect(block.contains("capture.p0-root"))
        #expect(block.contains("Physical capture locked"))
        #expect(block.contains("nembra.capture.root.account-link-action"))
        #expect(block.contains("XCTAssertTrue(accountLink.isEnabled)"))
        #expect(block.contains("XCTAssertTrue(accountLink.isHittable)"))
    }

    @Test("synthetic safety-sheet Accessibility XXXL evidence keeps confirmation reachable")
    func syntheticSafetySheetAccessibilityXXXLEvidenceIsRequired() throws {
        let source = try Self.captureUITestSource()
        let block = try Self.section(
            source,
            from: "func testSyntheticSafetySheetAtAccessibilityXXXLKeepsDisclosureAndConfirmationReachable()",
            to: "func testSyntheticCorrelationWithNoRepeatableTargetStopsWithoutConfirmation()"
        )

        #expect(block.contains("scenario: \"safety\""))
        #expect(block.contains("-UIPreferredContentSizeCategoryName"))
        #expect(block.contains("UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"))
        #expect(block.contains("nembra.capture.qa.synthetic-sheet-disclosure"))
        #expect(block.contains("nembra.capture.stationary-safety-confirm"))
        let reveal = try #require(block.range(of: "reveal(confirm, in: app)"))
        let screenshot = try #require(block.range(of: "keepSyntheticScreenshot(named: \"SAFETY-SHEET-AX-XXXL\")"))
        #expect(reveal.lowerBound < screenshot.lowerBound)
        #expect(block.contains("XCTAssertTrue(confirm.isEnabled)"))
    }

    @Test("all retained Capture QA screenshots stay explicitly synthetic")
    func screenshotsCannotMasqueradeAsPhysicalEvidence() throws {
        let source = try Self.captureUITestSource()

        #expect(source.contains("XCTAttachment(screenshot: XCUIScreen.main.screenshot())"))
        #expect(source.contains("screenshot.name = \"SYNTHETIC-QA-\\(name)\""))
        #expect(source.contains("SYNTHETIC UI STATE · NO CAPTURE ARTIFACT"))
        #expect(source.contains("assertNoCompleteOrShare(in: app)"))
    }
}
