import Foundation
import Testing
@testable import NembraBluetoothCapture

struct PassiveBluetoothExperimentOneFinalShareIntegrityTests {
    private let target = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let ambient = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let buildInstanceID = "A1B2C3D4-E5F6-47A8-90BC-DEF123456789"
    private let commit = "abcdef0123456789abcdef0123456789abcdef01"

    @Test("exact final-share bytes produce outer digest plus nested capture facts")
    func exactFinalShareProducesAnalysisFacts() throws {
        let artifact = try makeArtifact()
        let report = try PassiveBluetoothExperimentOneFinalShareIntegrity.inspect(artifact.json)
        let verified = try PassiveBluetoothExperimentOneFinalShareArtifactCodec
            .decodeAndVerify(artifact.json)

        #expect(report.finalShareByteCount == artifact.json.count)
        #expect(report.finalShareSHA256 ==
            PassiveBluetoothFinalizedArtifactIntegrity.sha256Hex(of: artifact.json))
        #expect(report.experimentID == verified.experimentID)
        #expect(report.experimentRecipeID == .es80FingerprintV1)
        #expect(report.procedureVersion == "V14")
        #expect(report.buildInstanceID == buildInstanceID.lowercased())
        #expect(report.softwareExportSHA256 == verified.softwareExportSHA256)
        #expect(report.capture.captureSessionID ==
            UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!)
        #expect(report.capture.recordCount == 3)
        #expect(report.capture.rawValueRecordCount == 1)
        #expect(report.capture.byteCount == verified.softwareExport.captureJSON.count)
        #expect(report.buildIdentifier == "Capture Build V14-abcdef012345")
        #expect(report.sourceCommitSHA == commit)
        #expect(report.executableSHA256.count == 64)
    }

    @Test("outer authority tamper is rejected before an analysis-ready report exists")
    func outerAuthorityTamperFailsClosed() throws {
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
            _ = try PassiveBluetoothExperimentOneFinalShareIntegrity.inspect(tampered)
        }
    }

    private func makeArtifact() throws -> PassiveBluetoothExperimentOneFinalShareArtifact {
        let export = try PassiveBluetoothExperimentOneSoftwareExportCodec.make(
            captureJSON: makeCaptureJSON(),
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
        var ledger = PassiveBluetoothPowerCycleObservationLedger(minimumWindowDurationNanoseconds: 1)
        var result: PassiveBluetoothPowerCycleObservationResult?
        let duration = PassiveBluetoothExperimentOneCapturePolicy
            .minimumPowerCycleWindowDurationNanoseconds

        for (index, phase) in PassiveBluetoothPowerCycleObservationPhase.allCases.enumerated() {
            let start = UInt64(index) * 20_000_000_000
            let candidates = phase.operatorExpectedPowerOn
                ? [candidate(ambient), candidate(target)]
                : [candidate(ambient)]
            result = try ledger.completeWindow(
                phase: phase,
                startedAtUptimeNanoseconds: start,
                endedAtUptimeNanoseconds: start + duration,
                candidates: candidates
            ) ?? result
        }
        return try #require(result)
    }

    private func candidate(_ id: UUID) -> PassiveBluetoothCandidateObservationSnapshot.Candidate {
        .init(id: id, isConnectable: true)
    }

    private func makeCaptureJSON() throws -> Data {
        let startedAt = Date(timeIntervalSince1970: 1_750_000_000)
        let service = PassiveBluetoothCaptureRecord(
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 1,
            receivedAtDate: startedAt,
            event: .service(try PassiveBluetoothServiceObservation(
                peripheralIdentifier: target.uuidString,
                serviceUUID: "FFE0",
                isPrimary: true
            ))
        )
        let characteristic = PassiveBluetoothCaptureRecord(
            sequenceNumber: 2,
            receivedAtUptimeNanoseconds: 2,
            receivedAtDate: startedAt.addingTimeInterval(1),
            event: .characteristic(try PassiveBluetoothCharacteristicObservation(
                peripheralIdentifier: target.uuidString,
                serviceUUID: "FFE0",
                characteristicUUID: "FFE1",
                properties: [.notify]
            ))
        )
        let value = PassiveBluetoothCaptureRecord(
            sequenceNumber: 3,
            receivedAtUptimeNanoseconds: 3,
            receivedAtDate: startedAt.addingTimeInterval(2),
            event: .value(try PassiveBluetoothValueObservation(
                peripheralIdentifier: target.uuidString,
                serviceUUID: "FFE0",
                characteristicUUID: "FFE1",
                origin: .subscriptionUpdate,
                payload: Data([0x01, 0x02])
            ))
        )
        let readyUptime: UInt64 = 1_000
        let ready = PassiveBluetoothObservationBoundary(
            kind: .finiteAcquisitionReady,
            recordSequenceWatermark: 3,
            observedAtUptimeNanoseconds: readyUptime,
            observedAtDate: startedAt.addingTimeInterval(3)
        )
        let horizon = PassiveBluetoothObservationBoundary(
            kind: .observationHorizon,
            recordSequenceWatermark: 3,
            observedAtUptimeNanoseconds: readyUptime
                + PassiveBluetoothExperimentOneCapturePolicy.minimumPostReadyObservationDurationNanoseconds,
            observedAtDate: startedAt.addingTimeInterval(63)
        )
        let session = try PassiveBluetoothCaptureSession(
            id: UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!,
            vehicleIdentity: .init(
                manufacturer: "AOVOPRO",
                model: "ES80",
                displayName: "AOVOPRO ES80",
                protocolFamily: "unverified-tuya"
            ),
            startedAt: startedAt,
            records: [service, characteristic, value],
            observationBoundaries: [ready, horizon]
        )
        return try PassiveBluetoothCaptureJSON.encode(session)
    }
}
