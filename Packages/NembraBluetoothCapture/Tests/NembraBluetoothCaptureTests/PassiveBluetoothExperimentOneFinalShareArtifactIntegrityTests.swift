import Foundation
import Testing
@testable import NembraBluetoothCapture

struct PassiveBluetoothExperimentOneFinalShareArtifactIntegrityTests {
    private let target = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let ambient = UUID(uuidString: "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE")!
    private let seriesID = UUID(uuidString: "12345678-1234-4234-8234-123456789ABC")!
    private let sessionID = UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!
    private let buildInstanceID = "a1b2c3d4-e5f6-47a8-90bc-def123456789"
    private let commit = "abcdef0123456789abcdef0123456789abcdef01"

    @Test
    func exactFinalShareReportBindsOuterInnerAndCaptureBytes() throws {
        let artifact = try makeArtifact()
        let report = try PassiveBluetoothExperimentOneFinalShareArtifactIntegrity.inspect(
            artifact.json
        )
        let verified = try PassiveBluetoothExperimentOneFinalShareArtifactCodec.decodeAndVerify(
            artifact.json
        )

        #expect(report.finalShareByteCount == artifact.json.count)
        #expect(
            report.finalShareSHA256 ==
            PassiveBluetoothFinalizedArtifactIntegrity.sha256Hex(of: artifact.json)
        )
        #expect(report.experimentID == verified.experimentID)
        #expect(report.experimentRecipeID == .es80FingerprintV1)
        #expect(report.procedureVersion == "V14")
        #expect(report.buildInstanceID == buildInstanceID)
        #expect(report.softwareExport.envelopeSHA256 == verified.softwareExportSHA256)
        #expect(report.softwareExport.capture.captureSessionID == sessionID)
        #expect(report.softwareExport.capture.recordCount == 2)
        #expect(report.softwareExport.capture.rawValueRecordCount == 1)
        #expect(report.softwareExport.capture.sha256 ==
                PassiveBluetoothFinalizedArtifactIntegrity.sha256Hex(
                    of: verified.softwareExport.captureJSON
                ))
    }

    @Test
    func outerWhitespaceChangesExactFinalShareDigestWithoutChangingNestedEvidence() throws {
        let artifact = try makeArtifact()
        let original = try PassiveBluetoothExperimentOneFinalShareArtifactIntegrity.inspect(
            artifact.json
        )
        var sameJSONWithDifferentBytes = artifact.json
        sameJSONWithDifferentBytes.append(0x0A)
        let changed = try PassiveBluetoothExperimentOneFinalShareArtifactIntegrity.inspect(
            sameJSONWithDifferentBytes
        )

        #expect(changed.finalShareSHA256 != original.finalShareSHA256)
        #expect(changed.finalShareByteCount == original.finalShareByteCount + 1)
        #expect(changed.softwareExport == original.softwareExport)
    }

    @Test
    func authorityLookingOuterFieldCannotEarnAnalysisReadyReport() throws {
        let artifact = try makeArtifact()
        var root = try #require(
            JSONSerialization.jsonObject(with: artifact.json) as? [String: Any]
        )
        root["physicalGO"] = true
        let tampered = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])

        #expect(
            throws: PassiveBluetoothExperimentOneFinalShareArtifactError
                .unexpectedWireField("physicalGO")
        ) {
            _ = try PassiveBluetoothExperimentOneFinalShareArtifactIntegrity.inspect(tampered)
        }
    }

    private func makeArtifact() throws -> PassiveBluetoothExperimentOneFinalShareArtifact {
        let softwareExport = try PassiveBluetoothExperimentOneSoftwareExportCodec.make(
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
            softwareExport: softwareExport
        )
    }

    private func makeRuntimeIdentity() throws -> PassiveBluetoothCaptureRuntimeBuildIdentity {
        try PassiveBluetoothCaptureRuntimeBuildIdentityReader.resolveEmbeddedMetadata(
            infoDictionary: [
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildIdentifierInfoDictionaryKey:
                    "Capture Build V14-integrity",
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildInstanceIDInfoDictionaryKey:
                    buildInstanceID,
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.sourceCommitSHAInfoDictionaryKey:
                    commit,
            ],
            executableData: Data("final-share-integrity-fixture".utf8)
        )
    }

    private func makePowerCycleResult() throws -> PassiveBluetoothPowerCycleObservationResult {
        let authority = PassiveBluetoothCandidateObservationSeriesIdentity(rawValue: seriesID)
        let duration = PassiveBluetoothExperimentOneCapturePolicy.minimumPowerCycleWindowDurationNanoseconds
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
        let startedAt = Date(timeIntervalSince1970: 1_750_000_000)
        let service = PassiveBluetoothCaptureRecord(
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 1,
            receivedAtDate: startedAt,
            event: .service(
                try PassiveBluetoothServiceObservation(
                    peripheralIdentifier: target.uuidString,
                    serviceUUID: "FFE0",
                    isPrimary: true
                )
            )
        )
        let value = PassiveBluetoothCaptureRecord(
            sequenceNumber: 2,
            receivedAtUptimeNanoseconds: 2,
            receivedAtDate: startedAt.addingTimeInterval(1),
            event: .value(
                try PassiveBluetoothValueObservation(
                    peripheralIdentifier: target.uuidString,
                    serviceUUID: "FFE0",
                    characteristicUUID: "FFE1",
                    origin: .subscriptionUpdate,
                    payload: Data([0x01, 0x02])
                )
            )
        )
        let readyUptime: UInt64 = 1_000
        let observationDuration = PassiveBluetoothExperimentOneCapturePolicy
            .minimumPostReadyObservationDurationNanoseconds
        let ready = PassiveBluetoothObservationBoundary(
            kind: .finiteAcquisitionReady,
            recordSequenceWatermark: 2,
            observedAtUptimeNanoseconds: readyUptime,
            observedAtDate: startedAt.addingTimeInterval(2)
        )
        let horizon = PassiveBluetoothObservationBoundary(
            kind: .observationHorizon,
            recordSequenceWatermark: 2,
            observedAtUptimeNanoseconds: readyUptime + observationDuration,
            observedAtDate: startedAt.addingTimeInterval(62)
        )
        let session = try PassiveBluetoothCaptureSession(
            id: sessionID,
            vehicleIdentity: .init(
                manufacturer: "AOVOPRO",
                model: "ES80",
                displayName: "AOVOPRO ES80",
                protocolFamily: "unverified-tuya"
            ),
            startedAt: startedAt,
            records: [service, value],
            observationBoundaries: [ready, horizon]
        )
        return try PassiveBluetoothCaptureJSON.encode(session)
    }
}