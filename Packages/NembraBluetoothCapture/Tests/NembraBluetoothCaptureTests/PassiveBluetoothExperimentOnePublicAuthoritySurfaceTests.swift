import Foundation
import Testing

@Suite("Experiment One authority surface")
struct PassiveBluetoothExperimentOnePublicAuthoritySurfaceTests {
    private static func runSource() throws -> String {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let sourcesDirectory = testsDirectory
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/NembraBluetoothCapture", isDirectory: true)

        return try String(
            contentsOf: sourcesDirectory.appendingPathComponent("PassiveBluetoothExperimentOneRun.swift"),
            encoding: .utf8
        )
    }

    @Test("unfinished PASS surface stays sealed while controller admission remains non-public")
    func authoritySurfaceIsSealed() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let sourcesDirectory = testsDirectory
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/NembraBluetoothCapture", isDirectory: true)

        let runSource = try Self.runSource()
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
        #expect(!compactRun.contains("publicfinalclassPassiveBluetoothExperimentOneCaptureAdmission"))
        #expect(!compactRun.contains("publicfuncissueCaptureAdmission("))
        #expect(!compactRun.contains("publicfuncbeginCaptureRecorder("))
        #expect(!compactRun.contains("publicfunccaptureEvidenceSnapshot("))
        #expect(!compactRun.contains("publicfunccaptureEvidenceAssessment("))
        #expect(!compactAssessment.contains("publicstructPassiveBluetoothExperimentOneCaptureEvidenceAssessment"))
        #expect(!compactAssessment.contains("publicstaticfuncassess("))

        // Authority-bearing wrappers remain producer-file private. Same-module code may consume only
        // the reviewed one-shot admission; it still cannot wrap detached raw evidence, initialize an
        // admission, or construct a replacement consumed payload from chosen scalar/object values.
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
            compactRun.contains(
                "fileprivateinit(admissionIdentity:UUID,issuedAtUptimeNanoseconds:UInt64,powerCycleEvidence:PassiveBluetoothExperimentOnePowerCycleEvidence,peripheralIdentifier:UUID,recorder:PassiveCoreBluetoothCaptureRecorder)"
            )
        )
        #expect(
            compactRun.contains(
                "fileprivateinit(issuedAtUptimeNanoseconds:UInt64,powerCycleEvidence:PassiveBluetoothExperimentOnePowerCycleEvidence,peripheralIdentifier:UUID,recorder:PassiveCoreBluetoothCaptureRecorder)"
            )
        )

        #expect(compactRun.contains("fileprivatefuncbeginCaptureRecorder("))
        #expect(compactRun.contains("fileprivatefunccaptureEvidenceSnapshot()"))
        #expect(compactRun.contains("fileprivatefunccaptureEvidenceAssessment()"))

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

    @Test("controller admission is producer-derived, chronology-stamped, and one-shot")
    func controllerAdmissionIsProducerDerivedChronologyStampedAndOneShot() throws {
        let source = try Self.runSource()
        let compact = source.filter { !$0.isWhitespace }

        let issue = try #require(source.range(of: "func issueCaptureAdmission("))
        let completedEvidence = try #require(source.range(
            of: "guard let evidence = completedPowerCycleEvidence else",
            range: issue.lowerBound..<source.endIndex
        ))
        let uniqueCorrelation = try #require(source.range(
            of: "guard case let .singleRepeatableCandidate(peripheralIdentifier)",
            range: completedEvidence.lowerBound..<source.endIndex
        ))
        let recorder = try #require(source.range(
            of: "let recorder = try beginCaptureRecorder(startedAt: startedAt)",
            range: uniqueCorrelation.lowerBound..<source.endIndex
        ))
        let issuance = try #require(source.range(
            of: "let issuedAtUptimeNanoseconds = DispatchTime.now().uptimeNanoseconds",
            range: recorder.lowerBound..<source.endIndex
        ))
        let admission = try #require(source.range(
            of: "return PassiveBluetoothExperimentOneCaptureAdmission(",
            range: issuance.lowerBound..<source.endIndex
        ))

        #expect(issue.lowerBound < completedEvidence.lowerBound)
        #expect(completedEvidence.lowerBound < uniqueCorrelation.lowerBound)
        #expect(uniqueCorrelation.lowerBound < recorder.lowerBound)
        #expect(recorder.lowerBound < issuance.lowerBound)
        #expect(issuance.lowerBound < admission.lowerBound)

        // The admission issuer accepts no caller-selected target/result/recorder/clock parameters.
        #expect(
            compact.contains(
                "funcissueCaptureAdmission(startedAt:Date=Date())throws->PassiveBluetoothExperimentOneCaptureAdmission"
            )
        )
        #expect(!compact.contains("funcissueCaptureAdmission(peripheralIdentifier:"))
        #expect(!compact.contains("funcissueCaptureAdmission(result:"))
        #expect(!compact.contains("funcissueCaptureAdmission(recorder:"))
        #expect(!compact.contains("funcissueCaptureAdmission(issuedAtUptimeNanoseconds:"))

        // The producer-owned monotonic stamp crosses the sealed payload boundary. It is software
        // callback chronology only and will be consumed downstream to reject pre-admission cache.
        #expect(compact.contains("letissuedAtUptimeNanoseconds:UInt64"))
        #expect(compact.contains("issuedAtUptimeNanoseconds:issuedAtUptimeNanoseconds"))

        // Aliased admission references share one consumed bit; replay cannot yield a second payload.
        #expect(compact.contains("privatevarhasBeenConsumed=false"))
        #expect(compact.contains("guard!hasBeenConsumedelse{throwConsumptionError.alreadyConsumed}"))
        #expect(compact.contains("hasBeenConsumed=true"))
        #expect(compact.contains("admissionIdentity:UUID()"))
    }
}
