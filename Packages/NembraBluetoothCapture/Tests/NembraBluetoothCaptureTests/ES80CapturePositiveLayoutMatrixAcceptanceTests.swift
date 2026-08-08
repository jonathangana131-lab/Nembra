import Foundation
import Testing

@Suite("ES80 Capture positive-state layout acceptance")
struct ES80CapturePositiveLayoutMatrixAcceptanceTests {
    private static func uiTestSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        return try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("NembraUITests")
                .appendingPathComponent("ES80ResearchCaptureUITests.swift"),
            encoding: .utf8
        )
    }

    private static func methodBody(named name: String, in source: String) throws -> Substring {
        let signature = "func \(name)()"
        let start = try #require(
            source.range(of: signature),
            "Missing required positive-state UI acceptance method: \(name)"
        )

        let searchStart = start.upperBound
        let remaining = source[searchStart..<source.endIndex]
        let candidateEnds = [
            remaining.range(of: "\n    @MainActor")?.lowerBound,
            remaining.range(of: "\n    func ")?.lowerBound,
            remaining.range(of: "\n    private func ")?.lowerBound
        ].compactMap { $0 }

        let end = candidateEnds.min() ?? source.endIndex
        return source[start.lowerBound..<end]
    }

    @Test("positive Horizon-ready shell is screenshot-gated at Accessibility XXXL")
    func horizonReadyAccessibilityXXXLIsARealAcceptanceState() throws {
        let source = try Self.uiTestSource()
        let method = try Self.methodBody(
            named: "testV14SimulatorQAPositiveShellRemainsLegibleAtAccessibilityExtraExtraExtraLarge",
            in: source
        )

        let requiredMarkers = [
            "--es80-passive-capture-simulator-qa",
            "--es80-capture-qa-scenario=observationHorizonReady",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
            "es80.capture-shell",
            "es80.capture.simulator-qa",
            "es80.capture.experiment-progress",
            "es80.capture.finish",
            "assertVisibleInScreenshotViewport",
            "Accessibility XXXL"
        ]

        for marker in requiredMarkers {
            #expect(
                method.contains(marker),
                "Positive Accessibility XXXL acceptance is missing required marker: \(marker)"
            )
        }
    }

    @Test("positive Horizon-ready shell is screenshot-gated in landscape")
    func horizonReadyLandscapeIsARealAcceptanceState() throws {
        let source = try Self.uiTestSource()
        let method = try Self.methodBody(
            named: "testV14SimulatorQAPositiveShellLandscapeKeepsProgressAndSealVisible",
            in: source
        )

        let requiredMarkers = [
            "--es80-passive-capture-simulator-qa",
            "--es80-capture-qa-scenario=observationHorizonReady",
            "XCUIDevice.shared.orientation = .portrait",
            "XCUIDevice.shared.orientation = .landscapeLeft",
            "defer { XCUIDevice.shared.orientation = .portrait }",
            "es80.capture-shell",
            "es80.capture.simulator-qa",
            "es80.capture.experiment-progress",
            "es80.capture.finish",
            "assertVisibleInScreenshotViewport",
            "Landscape"
        ]

        for marker in requiredMarkers {
            #expect(
                method.contains(marker),
                "Positive landscape acceptance is missing required marker: \(marker)"
            )
        }
    }
}