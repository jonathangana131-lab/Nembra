import Foundation
import Testing

@Suite("ES80 Capture recovery-language acceptance")
struct ES80CaptureRecoveryLanguageAcceptanceTests {
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

    private static func section(
        _ source: String,
        beginning: String,
        ending: String
    ) throws -> Substring {
        let start = try #require(source.range(of: beginning))
        let end = try #require(
            source.range(of: ending, range: start.upperBound..<source.endIndex)
        )
        return source[start.lowerBound..<end.lowerBound]
    }

    @Test("runtime phase failures do not expose package or evidence-lifecycle jargon")
    func runtimePhaseFailureCopyIsHumanFirst() throws {
        let source = try Self.shellSource()
        let phase = try Self.section(
            source,
            beginning: "private func phase(",
            ending: "private func simulatorQAPhase("
        )

        let banned = [
            "Experiment One",
            "evidence life",
            "capture authority",
            "package-owned CoreBluetooth controller",
            "package-issued observation authority",
            "package-owned Experiment One workflow",
            "exact correlated target",
            "consumed authority"
        ]

        for phrase in banned {
            #expect(!phase.contains(phrase), "Runtime failure copy still exposes implementation vocabulary: \(phrase)")
        }

        #expect(phase.contains("Nembra left the foreground after Capture began."))
        #expect(phase.contains("Start a fresh Capture."))
        #expect(phase.contains("Bluetooth capture is unavailable for this run."))
        #expect(phase.contains("The four OFF / ON steps did not preserve one valid sequence."))
    }

    @Test("primary failed state offers one clear recovery action")
    func primaryFailureRecoveryActionIsHumanFirst() throws {
        let source = try Self.shellSource()
        let primary = try Self.section(
            source,
            beginning: "private func primaryContent(",
            ending: "private func correlationReadyPanel("
        )

        #expect(primary.contains("Capture stopped safely"))
        #expect(primary.contains("Start a fresh Capture"))
        #expect(!primary.contains("Start a fresh Experiment One"))
        #expect(primary.contains("es80.capture.restart-experiment"))
    }

    @Test("simulator interruption fixture renders rider copy while retaining synthetic disclosure")
    func simulatorInterruptionIsSafeAndReadable() throws {
        let source = try Self.shellSource()
        let simulatorPhase = try Self.section(
            source,
            beginning: "private func simulatorQAPhase(",
            ending: "private var presentationAnalysisReady"
        )

        #expect(simulatorPhase.contains("Capture was interrupted when Nembra left the foreground."))
        #expect(simulatorPhase.contains("Start a fresh Capture."))
        #expect(!simulatorPhase.contains("evidence life"))
        #expect(!simulatorPhase.contains("foreground-invalidated"))

        #expect(source.contains("SIMULATOR / QA"))
        #expect(source.contains("SYNTHETIC SOFTWARE STATE"))
        #expect(source.contains("No Bluetooth transport or capture evidence is created by this presentation fixture."))
    }
}
