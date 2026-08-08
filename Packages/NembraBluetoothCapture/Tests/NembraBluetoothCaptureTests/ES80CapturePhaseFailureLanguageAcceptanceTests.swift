import Foundation
import Testing

@Suite("ES80 Capture phase-failure rider language")
struct ES80CapturePhaseFailureLanguageAcceptanceTests {
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

    private static func productionPhaseCopy(in source: String) throws -> Substring {
        let beginning = try #require(
            source.range(of: "private func phase(")
        )
        let end = try #require(
            source.range(
                of: "private func simulatorQAPhase(",
                range: beginning.lowerBound..<source.endIndex
            )
        )
        return source[beginning.lowerBound..<end.lowerBound]
    }

    @Test("phase-derived primary failures stay rider-readable")
    func phaseDerivedFailuresStayHumanFirst() throws {
        let source = try Self.shellSource()
        let phaseCopy = try Self.productionPhaseCopy(in: source)

        let implementationPhrasesThatMustStayOutOfPrimaryFailureCopy = [
            "package-issued observation authority",
            "package-owned Experiment One workflow",
            "scan-liveness",
            "four-window observation series"
        ]

        for phrase in implementationPhrasesThatMustStayOutOfPrimaryFailureCopy {
            #expect(
                !phaseCopy.contains(phrase),
                "Phase-derived primary failure copy still exposes implementation vocabulary: \(phrase)"
            )
        }

        #expect(phaseCopy.contains("OFF 1"))
        #expect(phaseCopy.contains("ON 1"))
        #expect(phaseCopy.contains("Bluetooth"))
    }
}
