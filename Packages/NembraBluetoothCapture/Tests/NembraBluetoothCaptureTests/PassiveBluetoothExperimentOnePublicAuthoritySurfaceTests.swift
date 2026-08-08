import Foundation
import Testing

@Suite("Experiment One authority surface")
struct PassiveBluetoothExperimentOnePublicAuthoritySurfaceTests {
    @Test("unfinished PASS surface stays package-internal and evidence issuance stays producer-file private")
    func authoritySurfaceIsSealed() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let sourcesDirectory = testsDirectory
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/NembraBluetoothCapture", isDirectory: true)

        let runSource = try String(
            contentsOf: sourcesDirectory.appendingPathComponent("PassiveBluetoothExperimentOneRun.swift"),
            encoding: .utf8
        )
        let assessmentSource = try String(
            contentsOf: sourcesDirectory.appendingPathComponent(
                "PassiveBluetoothExperimentOneCaptureEvidenceAssessment.swift"
            ),
            encoding: .utf8
        )

        let compactRun = runSource.filter { !$0.isWhitespace }
        let compactAssessment = assessmentSource.filter { !$0.isWhitespace }

        // General-purpose public raw capture APIs remain legitimate research tooling. What must not
        // be public until controller-owned H-bounded finalization exists is the authority-bearing
        // Experiment One bridge that could promote those raw artifacts into a coherent PASS.
        #expect(!compactRun.contains("publicfinalclassPassiveBluetoothExperimentOneRun"))
        #expect(!compactRun.contains("publicstructPassiveBluetoothExperimentOnePowerCycleEvidence"))
        #expect(!compactRun.contains("publicstructPassiveBluetoothExperimentOneCaptureEvidence"))
        #expect(!compactRun.contains("publicfuncbeginCaptureRecorder("))
        #expect(!compactRun.contains("publicfunccaptureEvidenceAssessment("))
        #expect(!compactAssessment.contains("publicstructPassiveBluetoothExperimentOneCaptureEvidenceAssessment"))
        #expect(!compactAssessment.contains("publicstaticfuncassess("))

        // Package-internal alone is not enough: another production file in this same module must
        // not be able to manufacture authority-bearing wrappers around detached raw evidence.
        #expect(
            compactRun.contains(
                "fileprivateinit?(result:PassiveBluetoothPowerCycleObservationResult)"
            )
        )
        #expect(
            compactRun.contains(
                "fileprivateinit(observationSeriesIdentity:PassiveBluetoothCandidateObservationSeriesIdentity,session:PassiveBluetoothCaptureSession)"
            )
        )
        #expect(
            !compactRun.contains(
                "internalinit?(result:PassiveBluetoothPowerCycleObservationResult)"
            )
        )
        #expect(
            !compactRun.contains(
                "internalinit(observationSeriesIdentity:PassiveBluetoothCandidateObservationSeriesIdentity,session:PassiveBluetoothCaptureSession)"
            )
        )
    }
}
