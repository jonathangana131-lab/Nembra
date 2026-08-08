import Foundation
import Testing

@Suite("ES80 Capture product closure acceptance")
struct ES80CaptureProductClosureAcceptanceTests {
    private static func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func uiTestSource() throws -> String {
        try String(
            contentsOf: repositoryRoot()
                .appendingPathComponent("NembraUITests")
                .appendingPathComponent("ES80ResearchCaptureUITests.swift"),
            encoding: .utf8
        )
    }

    private static func shellSource() throws -> String {
        try String(
            contentsOf: repositoryRoot()
                .appendingPathComponent("NembraApp")
                .appendingPathComponent("Features")
                .appendingPathComponent("Research")
                .appendingPathComponent("ES80CaptureShellView.swift"),
            encoding: .utf8
        )
    }

    private static func methodBody(named name: String, in source: String) throws -> Substring {
        let signature = "func \(name)()"
        let start = try #require(
            source.range(of: signature),
            "Missing required positive-state UI acceptance method: \(name)"
        )

        let remaining = source[start.upperBound..<source.endIndex]
        let candidateEnds = [
            remaining.range(of: "\n    @MainActor")?.lowerBound,
            remaining.range(of: "\n    func ")?.lowerBound,
            remaining.range(of: "\n    private func ")?.lowerBound
        ].compactMap { $0 }
        let end = candidateEnds.min() ?? source.endIndex
        return source[start.lowerBound..<end]
    }

    @Test("positive Horizon-ready shell is screenshot-gated at Accessibility XXXL")
    func positiveHorizonReadyAccessibilityXXXLIsARealAcceptanceState() throws {
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
    func positiveHorizonReadyLandscapeIsARealAcceptanceState() throws {
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

    @Test("normal rider errors do not expose package ownership or raw Swift errors")
    func renderedFailureCopyStaysHumanFirstAndBounded() throws {
        let shell = try Self.shellSource()

        #expect(
            !shell.contains("package-owned Experiment One workflow"),
            "A fresh-run failure can still expose package ownership vocabulary to the rider."
        )
        #expect(
            !shell.contains("return String(describing: error)"),
            "Unknown Capture errors must not dump raw Swift/package descriptions into the rider surface."
        )

        // Preserve the established typed error boundary rather than solving copy by deleting it.
        #expect(shell.contains("private func experimentErrorMessage(_ error: Error) -> String"))
        #expect(shell.contains("PassiveBluetoothExperimentOneCoordinator.CoordinatorError"))
        #expect(shell.contains("PassiveBluetoothPowerCycleObservationSessionError"))
        #expect(shell.contains("experimentErrorMessage(error)"))
    }
}