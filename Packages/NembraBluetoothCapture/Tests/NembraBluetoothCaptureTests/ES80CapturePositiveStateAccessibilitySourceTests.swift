import Foundation
import Testing

@Suite("ES80 Capture positive-state accessibility source contract")
struct ES80CapturePositiveStateAccessibilitySourceTests {
    private var repositoryRoot: URL {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 {
            root.deleteLastPathComponent()
        }
        return root
    }

    private func source(at relativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    @Test("real Capture shell deliberately recomposes fixed horizontal instruments at accessibility sizes")
    func productShellHasExplicitAccessibilitySizeRecomposition() throws {
        let shell = try source(
            at: "NembraApp/Features/Research/ES80CaptureShellView.swift"
        )

        #expect(
            shell.contains("@Environment(\\.dynamicTypeSize)"),
            "The app-visible Capture shell needs the actual Dynamic Type environment so positive field states can deliberately recompose instead of merely hoping fixed HStacks fit."
        )
        #expect(
            shell.contains("dynamicTypeSize.isAccessibilitySize"),
            "At Accessibility sizes the hero/status, six-stage progress rail, and three-part health strip require an explicit recomposition path."
        )
    }

    @Test("Horizon-ready positive Simulator QA is exercised at Accessibility XXXL")
    func horizonReadyHasAccessibilityXXXLRuntimeGate() throws {
        let uiTests = try source(
            at: "NembraUITests/ES80ResearchCaptureUITests.swift"
        )

        let expectedLaunchPair = "\"--es80-capture-qa-scenario=observationHorizonReady\",\n            \"-UIPreferredContentSizeCategoryName\",\n            \"UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge\""
        #expect(
            uiTests.contains(expectedLaunchPair),
            "The real positive Horizon-ready Capture shell must be launched at Accessibility XXXL, not only the separate locked NO-GO surface."
        )
        #expect(
            uiTests.contains("Nembra Capture V14 — SIMULATOR QA — Horizon Ready — Accessibility XXXL"),
            "Keep a retained screenshot for direct visual review of the positive large-text state."
        )
    }
}
