import Foundation
import Testing
@testable import NembraBluetoothCapture

struct PassiveBluetoothExperimentOneFinalShareArtifactIntegrityTests {
    private let target = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let ambient = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let seriesID = UUID(uuidString: "12345678-1234-4234-8234-123456789ABC")!
    private let captureID = UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!
    private let buildInstanceID = "A1B2C3D4-E5F6-47A8-90BC-DEF123456789"
    private let commit = "abcdef0123456789abcdef0123456789abcdef01"

    @Test
    func exactFinalShareBytesEarnAnalysisReadinessFactsWithoutReencoding() throws {
        let artifact = try makeArtifact()
        let report = try PassiveBluetoothExperimentOneFinalShareArtifactIntegrity.inspect(
            artifact.json
        )
        let verified = try PassiveBluetoothExperimentOneFinalShareArtifactCodec.decodeAndVerify(
            artifact.json
        )

        #expect(report.finalShareByteCount == artifact.json.count)
        #expect(
            report.finalShareSHA256
                == PassiveBluetoothFinalizedArtifactIntegrity.sha256Hex(of: artifact.json)
        )
        #expect(report.experimentID == verified.experimentID)
        #expect(report.experimentRecipeID == .es80FingerprintV1)
        #expect(report.procedureVersion == "V14")
        #expect(report.buildInstanceID == buildInstanceID.lowercased())
        #expect(report.softwareExportSHA256 == verified.softwareExportSHA256)
        #expect(report.capture.captureSessionID == captureID)
        #expect(report.capture.byteCount == verified.softwareExport.captureJSON.count)
        #expect(report.capture.recordCount == 2)
        #expect(report.capture.rawValueRecordCount == 1)
        #expect(report.capture.sha256.count == 64)
        #expect(report.finalShareSHA256.count == 64)
    }

    @Test
    func outerFormattingChangeProducesDifferentExactArtifactDigestWhileRemainingReadable() throws {
        let artifact = try makeArtifact()
        let original = try PassiveBluetoothExperimentOneFinalShareArtifactIntegrity.inspect(
            artifact.json
        )
        var restagedBytes = artifact.json
        restagedBytes.append(contentsOf: "\n".utf8)
        let restaged = try PassiveBluetoothExperimentOneFinalShareArtifactIntegrity.inspect(
            restagedBytes
        )

        #expect(restaged.experimentID == original.experimentID)
        #expect(restaged.softwareExportSHA256 == original.softwareExportSHA256)
        #expect(restaged.capture == original.capture)
        #expect(restaged.finalShareByteCount == original.finalShareByteCount + 1)
        #expect(restaged.finalShareSHA256 != original.finalShareSHA256)
    }

    @Test
    func tamperedNestedSoftwareExportCannotEarnFinalShareIntegrity() throws {
        let artifact = try makeArtifact()
        var root = try #require(
            JSONSerialization.jsonObject(with: artifact.json) as? [String: Any]
        )
        var nested = try #require(
            Data(base64Encoded: try #require(root["softwareExportJSONBase64"] as? String))
        )
        nested.append(0x20)
        root["softwareExportJSONBase64"] = nested.base64EncodedString()
        let tampered = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])

        #expect(
            throws: PassiveBluetoothExperimentOneFinalShareArtifactError
                .softwareExportDigestMismatch
        ) {
            _ = try PassiveBluetoothExperimentOneFinalShareArtifactIntegrity.inspect(tampered)
        }
    }

    private func makeArtifact() throws -> PassiveBluetoothExperimentOneFinalShareArtifact {
        let export = try PassiveBluetoothExperimentOneSoftwareExportCodec.make(
            captureJSON: makeCapture(),
            powerCycleResult: makePowerCycleResult(),
            runtimeBuildIdentity: makeRuntimeIdentity(),
            setup: .init(
                chargerState: .disconnected,
                executionContext: .foregroundUnlockedScreenOn,
                stockAppReferenceSetup: .none
            )
        )
        return try PassiveBluetoothExperimentOneFinalShareArtifactCodec.make(
            softwareExport: export
        )
    }

    private func makeRuntimeIdentity() throws -> PassiveBluetoothCaptureRuntimeBuildIdentity {
        try PassiveBluetoothCaptureRuntimeBuildIdentityReader.resolveEmbeddedMetadata(
            infoDictionary: [
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildIdentifierInfoDictionaryKey:
                    "Capture Build V14-abcdef012345",
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildInstanceIDInfoDictionaryKey:
                    buildInstanceID,
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.sourceCommitSHAInfoDictionaryKey:
                    commit,
            ],
            executableData: Data("final-share-integrity-test-executable".utf8)
        )
    }

    private func makePowerCycleResult() throws -> PassiveBluetoothPowerCycleObservationResult {
        let authority = PassiveBluetoothCandidateObservationSeriesIdentity(rawValue: seriesID)
        let duration = PassiveBluetoothExperimentOneCapturePolicy
            .minimumPowerCycleWindowDurationNanoseconds
        var receipts: [PassiveBluetoothPowerCycleObservationWindowReceipt] = []
        var snapshots: [PassiveBluetoothCandidateObservationSnapshot] = []

        for (index, phase) in PassiveBluetoothPowerCycleObservationPhase.allCases.enumerated() {
            let sequence = PassiveBluetoothCandidateObservationWindowSequence(
                rawValue: UInt64(index + 1)
            )
            var candidates = [
                PassiveBluetoothCandidateObservationSnapshot.Candidate(
                    id: ambient,
                    isConnectable: true
                ),
            ]
            if phase.operatorExpectedPowerOn {
                candidates.append(.init(id: target, isConnectable: true))
            }
            let snapshot = try PassiveBluetoothCandidateObservationSnapshot(
                observationSeriesIdentity: authority,
                windowSequence: sequence,
                candidates: candidates
            )
            snapshots.append(snapshot)
            let start = UInt64(index) * 20_000_000_000 + 1_000
            receipts.append(.init(
                phase: phase,
                windowSequence: sequence,
                startedAtUptimeNanoseconds: start,
                endedAtUptimeNanoseconds: start + duration,
                observedCandidateCount: snapshot.candidates.count
            ))
        }

        return .init(
            windows: receipts,
            observationSnapshots: snapshots,
            correlation: PassiveBluetoothPowerCycleTargetCorrelation.assess(
                firstOff: snapshots[0],
                firstOn: snapshots[1],
                secondOff: snapshots[2],
                secondOn: snapshots[3]
            )
        )
    }

    private func makeCapture() throws -> Data {
        var session = try PassiveBluetoothCaptureSession(
            id: captureID,
            vehicleIdentity: .init(
                manufacturer: "AOVOPRO",
                model: "ES80",
                displayName: "AOVOPRO ES80",
                protocolFamily: "unverified-tuya"
            ),
            startedAt: Date(timeIntervalSince1970: 1_750_000_000)
        )
        try session.append(
            .service(try PassiveBluetoothServiceObservation(
                peripheralIdentifier: target.uuidString,
                serviceUUID: "FFE0",
                isPrimary: true
            )),
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 1,
            receivedAtDate: Date(timeIntervalSince1970: 1_750_000_001)
        )
        try session.append(
            .value(try PassiveBluetoothValueObservation(
                peripheralIdentifier: target.uuidString,
                serviceUUID: "FFE0",
                characteristicUUID: "FFE1",
                origin: .subscriptionUpdate,
                payload: Data([0x01, 0x02])
            )),
            sequenceNumber: 2,
            receivedAtUptimeNanoseconds: 2,
            receivedAtDate: Date(timeIntervalSince1970: 1_750_000_002)
        )
        return try PassiveBluetoothCaptureJSON.encode(session)
    }
}
