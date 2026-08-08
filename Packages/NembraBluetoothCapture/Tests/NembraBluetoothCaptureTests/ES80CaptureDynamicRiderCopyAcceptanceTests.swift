import Foundation
import Testing

@Suite("ES80 Capture dynamic rider-copy acceptance")
struct ES80CaptureDynamicRiderCopyAcceptanceTests {
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

    private static func slice(
        _ source: String,
        from beginningMarker: String,
        throughBefore endMarker: String
    ) throws -> Substring {
        let beginning = try #require(source.range(of: beginningMarker))
        let end = try #require(
            source.range(
                of: endMarker,
                range: beginning.lowerBound..<source.endIndex
            )
        )
        return source[beginning.lowerBound..<end.lowerBound]
    }

    @Test("phase-derived primary states stay rider-readable")
    func phaseDerivedPrimaryStatesStayHumanFirst() throws {
        let source = try Self.shellSource()
        let phaseProjection = try Self.slice(
            source,
            from: "private func phase(",
            throughBefore: "private func progressStage("
        )

        let implementationPhrasesThatMustStayOutOfProjectedPrimaryCopy = [
            "package-owned CoreBluetooth controller",
            "package-owned Experiment One workflow",
            "accepted observation",
            "consumed authority",
            "scan-liveness",
            "four-window observation series"
        ]

        for phrase in implementationPhrasesThatMustStayOutOfProjectedPrimaryCopy {
            #expect(
                !phaseProjection.contains(phrase),
                "A phase-derived primary Capture state still exposes engineering vocabulary: \(phrase)"
            )
        }
    }

    @Test("fresh-capture recovery never dumps raw construction errors")
    func freshCaptureRecoveryStaysHumanFirst() throws {
        let source = try Self.shellSource()
        let recovery = try Self.slice(
            source,
            from: "private func restartExperiment()",
            throughBefore: "private func handleScenePhaseChange("
        )

        #expect(!recovery.contains("package-owned Experiment One workflow"))
        #expect(!recovery.contains("String(describing: error)"))
        #expect(
            recovery.contains("experimentErrorMessage(error)"),
            "Fresh-capture recovery must reuse the rider-safe error projection instead of dumping a raw error."
        )
    }
}
