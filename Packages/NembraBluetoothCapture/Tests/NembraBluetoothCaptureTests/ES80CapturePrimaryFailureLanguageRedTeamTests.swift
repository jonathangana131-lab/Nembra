import Foundation
import Testing

@Suite("ES80 Capture primary failure-language red team")
struct ES80CapturePrimaryFailureLanguageRedTeamTests {
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
        to endingMarker: String
    ) throws -> Substring {
        let beginning = try #require(source.range(of: beginningMarker))
        let ending = try #require(
            source.range(
                of: endingMarker,
                range: beginning.lowerBound..<source.endIndex
            )
        )
        return source[beginning.lowerBound..<ending.lowerBound]
    }

    @Test("production phase routing never exposes authority implementation vocabulary")
    func productionPhaseFailureCopyStaysRiderReadable() throws {
        let source = try Self.shellSource()
        let phaseRouting = try Self.slice(
            source,
            from: "private func phase(",
            to: "private func simulatorQAPhase("
        )

        let forbiddenPrimaryFailurePhrases = [
            "evidence life",
            "capture authority",
            "consumed authority",
            "package-owned",
            "package-issued",
            "CoreBluetooth",
            "scan-liveness",
            "correlation progress",
            "final result"
        ]

        for phrase in forbiddenPrimaryFailurePhrases {
            #expect(
                !phaseRouting.localizedCaseInsensitiveContains(phrase),
                "Primary phase failure copy still exposes implementation vocabulary: \(phrase)"
            )
        }

        #expect(phaseRouting.contains("Start a fresh"))
        #expect(phaseRouting.contains("Bluetooth"))
        #expect(phaseRouting.contains("OFF 1"))
        #expect(phaseRouting.contains("ON 1"))
        #expect(phaseRouting.contains("OFF 2"))
        #expect(phaseRouting.contains("ON 2"))
    }

    @Test("fresh-run creation failure never dumps raw implementation errors")
    func restartFailureCopyStaysRiderReadable() throws {
        let source = try Self.shellSource()
        let restart = try Self.slice(
            source,
            from: "private func restartExperiment()",
            to: "private func handleScenePhaseChange("
        )

        #expect(!restart.contains("package-owned"))
        #expect(!restart.contains("String(describing: error)"))
        #expect(restart.contains("fresh"))
    }

    @Test("primary sealing and Share recovery copy avoids evidence-debugger language")
    func primaryIntegrityRecoveryCopyStaysHumanFirst() throws {
        let source = try Self.shellSource()
        let primarySurface = try Self.slice(
            source,
            from: "private var passiveSafetyPanel",
            to: "private var captureDetailsSheet"
        )

        let forbiddenPrimaryIntegrityPhrases = [
            "final evidence cutoff",
            "nested capture integrity",
            "nested evidence",
            "Verify final artifact"
        ]

        for phrase in forbiddenPrimaryIntegrityPhrases {
            #expect(
                !primarySurface.localizedCaseInsensitiveContains(phrase),
                "Primary Capture recovery copy still exposes evidence-debugger language: \(phrase)"
            )
        }

        #expect(primarySurface.contains("Seal Capture"))
        #expect(primarySurface.contains("Share Capture"))
        #expect(primarySurface.contains("Ready for analysis"))
    }
}
