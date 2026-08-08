import Foundation
import Testing

@Suite("ES80 Capture dynamic rider-language acceptance")
struct ES80CaptureDynamicRiderLanguageAcceptanceTests {
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

    @Test("dynamic phase and restart messages stay human-first")
    func dynamicMessagesStayHumanFirst() throws {
        let source = try Self.shellSource()
        let phaseStart = try #require(source.range(of: "private func phase("))
        let errorHelperStart = try #require(
            source.range(
                of: "private func experimentErrorMessage",
                range: phaseStart.lowerBound..<source.endIndex
            )
        )
        let dynamicSurface = source[phaseStart.lowerBound..<errorHelperStart.lowerBound]

        let implementationPhrasesThatMustStayOutOfDynamicPrimaryCopy = [
            "This evidence life cannot regain capture authority",
            "replaying consumed authority",
            "package-owned CoreBluetooth controller",
            "package-issued observation authority",
            "package-owned Experiment One workflow",
            "scan-liveness",
            "foreground-invalidated evidence life",
            "could not create a fresh package-owned Experiment One workflow"
        ]

        for phrase in implementationPhrasesThatMustStayOutOfDynamicPrimaryCopy {
            #expect(
                !dynamicSurface.contains(phrase),
                "Dynamic rider-facing Capture copy still exposes implementation vocabulary: \(phrase)"
            )
        }
    }

    @Test("dynamic failure states do not dump package diagnostics or raw Error descriptions")
    func dynamicFailureStatesStayCurated() throws {
        let source = try Self.shellSource()
        let phaseStart = try #require(source.range(of: "private func phase("))
        let phaseEnd = try #require(
            source.range(
                of: "private var presentationAnalysisReady",
                range: phaseStart.lowerBound..<source.endIndex
            )
        )
        let phaseAndSimulator = source[phaseStart.lowerBound..<phaseEnd.lowerBound]

        #expect(!phaseAndSimulator.contains("return .failed(coordinator.lastDiagnostic ??"))

        let restartStart = try #require(source.range(of: "private func restartExperiment()"))
        let restartEnd = try #require(
            source.range(
                of: "private func handleScenePhaseChange",
                range: restartStart.lowerBound..<source.endIndex
            )
        )
        let restart = source[restartStart.lowerBound..<restartEnd.lowerBound]
        #expect(!restart.contains("String(describing: error)"))
    }
}
