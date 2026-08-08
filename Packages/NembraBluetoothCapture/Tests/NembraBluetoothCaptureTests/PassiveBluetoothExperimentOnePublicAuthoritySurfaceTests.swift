import Foundation
import Testing

@Suite("Experiment One external-client authority surface")
struct PassiveBluetoothExperimentOnePublicAuthoritySurfaceTests {
    @Test("unfinished authority/PASS types remain package-internal")
    func authorityTypesAreNotPublic() throws {
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
    }
}
