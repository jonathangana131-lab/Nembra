import Foundation
import Testing

@Suite("ES80 Capture Share recovery language")
struct ES80CaptureShareRecoveryLanguageTests {
    private static func shellSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        return try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("NembraApp")
                .appendingPathComponent("Features")
                .appendingPathComponent("Research")
                .appendingPathComponent("ES80CaptureShellView.swift"),
            encoding: .utf8
        )
    }

    @Test("Share recovery warnings remain rider-readable after the artifact is sealed")
    func shareRecoveryWarningsStayHumanFirst() throws {
        let source = try Self.shellSource()
        let start = try #require(source.range(of: "private func prepareFinalShareForAnalysisAndSharing()"))
        let end = try #require(
            source.range(
                of: "private func restartExperiment()",
                range: start.lowerBound..<source.endIndex
            )
        )
        let shareRecoverySurface = source[start.lowerBound..<end.lowerBound]

        let implementationPhrasesThatMustStayOutOfShareRecovery = [
            "Experiment One",
            "setup provenance",
            "temporary Share file could not be staged",
            "exact final Share artifact did not earn analysis readiness"
        ]

        for phrase in implementationPhrasesThatMustStayOutOfShareRecovery {
            #expect(
                !shareRecoverySurface.contains(phrase),
                "Share recovery still exposes implementation vocabulary: \(phrase)"
            )
        }

        #expect(shareRecoverySurface.contains("its setup confirmation is missing"))
        #expect(shareRecoverySurface.contains("Start a fresh capture"))
        #expect(shareRecoverySurface.contains("Nembra could not prepare the Share file"))
        #expect(shareRecoverySurface.contains("Nembra could not verify the Share file for analysis"))
        #expect(shareRecoverySurface.contains("Capture remains sealed"))
    }
}
