import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Experiment One final Share integrity")
struct PassiveBluetoothExperimentOneFinalShareIntegrityTests {
    private let target = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let ambient = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let seriesID = UUID(uuidString: "12345678-1234-4234-8234-123456789ABC")!
    private let captureSessionID = UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!
    private let buildInstanceID = "A1B2C3D4-E5F6-47A8-90BC-DEF123456789"
    private let commit = "abcdef0123456789abcdef0123456789abcdef01"

    @Test("exact final Share bytes earn nested analysis-readiness facts without re-encoding")
    func exactBytesEarnAnalysisReadiness() throws {
        let softwareExport = try makeSoftwareExport()
        let artifact = try PassiveBluetoothExperimentOneFinalShareArtifactCodec.make(
            softwareExport: softwareExport
        )
        let verified = try PassiveBluetoothExperimentOneFinalShareArtifactCodec
            .decodeAndVerify(artifact.json)
        let report = try PassiveBluetoothExperimentOneFinalShareIntegrity.inspect(artifact.json)

        #expect(report.finalShareByteCount == artifact.json.count)
        #expect(
            report.finalShareSHA256 ==
                PassiveBluetoothFinalizedArtifactIntegrity.sha256Hex(of: artifact.json)
        )
        #expect(report.experimentID == verified.experimentID)
        #expect(report.experimentRecipeID == .es80FingerprintV1)
        #expect(report.procedureVersion == PassiveBluetoothExperimentOneFinalShareArtifact.procedureVersion)
        #expect(report.buildInstanceID == buildInstanceID.lowercased())
        #expect(report.softwareExport.envelopeSHA256 == verified.softwareExportSHA256)
        #expect(report.softwareExport.envelopeByteCount == verified.softwareExportJSON.count)
        #expect(report.softwareExport.capture.captureSessionID == captureSessionID)
        #expect(report.softwareExport.capture.recordCount == 3)
        #expect(report.softwareExport.capture.rawValueRecordCount == 1)
    }

    @Test("outer-byte tamper cannot retain analysis-ready status")
    func outerByteTamperFailsClosed() throws {
        let artifact = try PassiveBluetoothExperimentOneFinalShareArtifactCodec.make(
            softwareExport: makeSoftwareExport()
        )
        var root = try #require(
            JSONSerialization.jsonObject(with: artifact.json) as? [String: Any]
        )
        root["procedureVersion"] = "V14-tampered"
        let tampered = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])

        #expect(throws: PassiveBluetoothExperimentOneFinalShareArtifactError.unsupportedProcedureVersion("V14-tampered")) {
            _ = try PassiveBluetoothExperimentOneFinalShareIntegrity.inspect(tampered)
        }
    }

    private func makeSoftwareExport() throws -> PassiveBluetoothExperimentOneSoftwareExport {
        try PassiveBluetoothExperimentOneSoftwareExportCodec.make(
            captureJSON: makeCapture(),
            powerCycleResult: makePowerCycleResult(),
            runtimeBuildIdentity: makeRuntimeIdentity(),
            setup: .init(
                chargerState: .disconnected,
                executionContext: .foregroundUnlockedScreenOn,
                stockAppReferenceSetup: .none
            )
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
            executableData: Data("final-share-integrity-test-executable".utf8),
            infoPlistData: Data("fixture Info.plist".utf8)
        )
    }

    private func makePowerCycleResult() throws -> PassiveBluetoothPowerCycleObservationResult {
        let authority = PassiveBluetoothCandidateObservationSeriesIdentity(rawValue: seriesID)
        let duration = PassiveBluetoothExperimentOneCapturePolicy.minimumPowerCycleWindowDurationNanoseconds
        var receipts: [PassiveBluetoothPowerCycleObservationWindowReceipt] = []
        var snapshots: [PassiveBluetoothCandidateObservationSnapshot] = []

        for (index, phase) in PassiveBluetoothPowerCycleObservationPhase.allCases.enumerated() {
            let sequence = PassiveBluetoothCandidateObservationWindowSequence(rawValue: UInt64(index + 1))
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

        let correlation = PassiveBluetoothPowerCycleTargetCorrelation.assess(
            firstOff: snapshots[0],
            firstOn: snapshots[1],
            secondOff: snapshots[2],
            secondOn: snapshots[3]
        )
        return .init(
            windows: receipts,
            observationSnapshots: snapshots,
            correlation: correlation
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
        let characteristic = PassiveBluetoothCaptureRecord(
            sequenceNumber: 2,
            receivedAtUptimeNanoseconds: 2,
            receivedAtDate: startedAt.addingTimeInterval(1),
            event: .characteristic(
                try PassiveBluetoothCharacteristicObservation(
                    peripheralIdentifier: target.uuidString,
                    serviceUUID: "FFE0",
                    characteristicUUID: "FFE1",
                    properties: [.notify]
                )
            )
        )
        let value = PassiveBluetoothCaptureRecord(
            sequenceNumber: 3,
            receivedAtUptimeNanoseconds: 3,
            receivedAtDate: startedAt.addingTimeInterval(2),
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
        let ready = PassiveBluetoothObservationBoundary(
            kind: .finiteAcquisitionReady,
            recordSequenceWatermark: 3,
            observedAtUptimeNanoseconds: readyUptime,
            observedAtDate: startedAt.addingTimeInterval(3)
        )
        let horizon = PassiveBluetoothObservationBoundary(
            kind: .observationHorizon,
            recordSequenceWatermark: 3,
            observedAtUptimeNanoseconds:
                readyUptime + PassiveBluetoothExperimentOneCapturePolicy.minimumPostReadyObservationDurationNanoseconds,
            observedAtDate: startedAt.addingTimeInterval(63)
        )
        let session = try PassiveBluetoothCaptureSession(
            id: captureSessionID,
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
