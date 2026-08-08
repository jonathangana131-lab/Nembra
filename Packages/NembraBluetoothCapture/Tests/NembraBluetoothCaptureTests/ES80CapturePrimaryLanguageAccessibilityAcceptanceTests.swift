import Foundation
import Testing

@Suite("ES80 Capture primary-language accessibility acceptance")
struct ES80CapturePrimaryLanguageAccessibilityAcceptanceTests {
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

    private static func riderSurface(in source: String) throws -> Substring {
        let beginning = try #require(source.range(of: "private var passiveSafetyPanel"))
        let details = try #require(
            source.range(
                of: "private var captureDetailsSheet",
                range: beginning.lowerBound..<source.endIndex
            )
        )
        return source[beginning.lowerBound..<details.lowerBound]
    }

    @Test("visible and VoiceOver primary copy stay free of engineering vocabulary")
    func primaryAccessibilityLanguageStaysHumanFirst() throws {
        let riderSurface = try Self.riderSurface(in: Self.shellSource())

        let forbiddenPrimaryPhrases = [
            "bounded Bluetooth observation window",
            "package producer",
            "full Bluetooth identifier",
            "RSSI",
            "application characteristic-value writes",
            "PASSIVE ACQUISITION",
            "Learning the readable surface",
            "HORIZON READY",
            "Finite acquisition",
            "monotonic observation duration",
            "healthItem(\"FINITE\"",
            "healthItem(\"HORIZON\""
        ]

        for phrase in forbiddenPrimaryPhrases {
            #expect(
                !riderSurface.contains(phrase),
                "Primary Capture or VoiceOver copy still exposes engineering vocabulary: \(phrase)"
            )
        }
    }

    @Test("primary health and seal language use product terms without weakening authority")
    func primaryHealthLanguageUsesProductTerms() throws {
        let source = try Self.shellSource()
        let riderSurface = try Self.riderSurface(in: source)

        #expect(riderSurface.contains("READY TO SEAL"))
        #expect(riderSurface.contains("healthItem(\"SETUP\""))
        #expect(riderSurface.contains("healthItem(\"OBSERVE\""))
        #expect(riderSurface.contains("Capture health. Target"))
        #expect(riderSurface.contains("Setup"))
        #expect(riderSurface.contains("Observation"))

        // Language repair must remain presentation-only. The accepted package authority and
        // monotonic Horizon predicate stay mechanically unchanged behind rider-facing wording.
        #expect(source.contains("presentationCanFinalizeObservationHorizon(status: status)"))
        #expect(source.contains("coordinator.finalizeObservationHorizon()"))
        #expect(source.contains("guard status.physicalProcedurePermitted else"))
        #expect(source.contains("PassiveBluetoothExperimentOneFinalShareIntegrity.inspect(artifact.json)"))
    }
}
