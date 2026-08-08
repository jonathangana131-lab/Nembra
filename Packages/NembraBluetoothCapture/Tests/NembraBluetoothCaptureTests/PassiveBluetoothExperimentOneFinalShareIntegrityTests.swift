import Foundation
import Testing
@testable import NembraBluetoothCapture

struct PassiveBluetoothExperimentOneFinalShareIntegrityTests {
    private let target = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let ambient = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    @Test
    func exactFinalShareEarnsAnalysisReadinessFactsWithoutReencodingCapture() throws {
        let captureJSON = try makeCapture()
        let softwareExport = try PassiveBluetoothExperimentOneSoftwareExportCodec.make(
            captureJSON: captureJSON,
            powerCycleResult: makePowerCycleResult(),
            runtimeBuildIdentity: makeRuntimeIdentity(),
            setup: .init(
                chargerState: .disconnected,
                executionContext: .foregroundUnlockedScreenOn,
                stockAppReferenceSetup: .none
            )
        )
        let artifact = try PassiveBluetoothExperimentOneFinalShareArtifactCodec.make(
            softwareExport: softwareExport
        )

        let report = try PassiveBluetoothExperimentOneFinalShareIntegrity.inspect(artifact.json)

        #expect(report.finalShareByteCount == artifact.json.count)
        #expect(report.finalShareSHA256 == PassiveBluetoothFinalizedArtifactIntegrity.sha256Hex(of: artifact.json))
        #expect(report.experimentRecipeID == .es80FingerprintV1)
        #expect(report.procedureVersion == "V14")
        #expect(report.capture.byteCount == captureJSON.count)
        #expect(report.capture.sha256 == PassiveBluetoothFinalizedArtifactIntegrity.sha256Hex(of: captureJSON))
        #expect(report.capture.recordCount == 2)
        #expect(report.capture.rawValueRecordCount == 1)
        #expect(report.softwareExportSHA256.count == 64)
        #expect(report.buildIdentifier == softwareExport.build.buildIdentifier)
        #expect(report.buildInstanceID == softwareExport.build.buildInstanceID)
        #expect(report.sourceCommitSHA == softwareExport.build.sourceCommitSHA)
        #expect(report.executableSHA256 == softwareExport.build.executableSHA256)
    }

    @Test
    func malformedPrimaryShareCannotEarnAnalysisReadiness() {
        #expect(throws: Error.self) {
            _ = try PassiveBluetoothExperimentOneFinalShareIntegrity.inspect(Data("{}".utf8))
        }
    }

    private func makeRuntimeIdentity() throws -> PassiveBluetoothCaptureRuntimeBuildIdentity {
        try PassiveBluetoothCaptureRuntimeBuildIdentityReader.resolveEmbeddedMetadata(
            infoDictionary: [
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildIdentifierInfoDictionaryKey:
                    "Capture Build V14-analysis-ready",
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildInstanceIDInfoDictionaryKey:
                    "A1B2C3D4-E5F6-47A8-90BC-DEF123456789",
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.sourceCommitSHAInfoDictionaryKey:
                    "abcdef0123456789abcdef0123456789abcdef01",
            ],
            executableData: Data("analysis-ready-test-executable".utf8)
        )
    }

    private func makePowerCycleResult() throws -> PassiveBluetoothPowerCycleObservationResult {
        let authority = PassiveBluetoothCandidateObservationSeriesIdentity(
            rawValue: UUID(uuidString: "12345678-1234-4234-8234-123456789ABC")!
        )
        let duration = PassiveBluetoothExperimentOneCapturePolicy.minimumPowerCycleWindowDurationNanoseconds
        var receipts: [PassiveBluetoothPowerCycleObservationWindowReceipt] = []
        var snapshots: [PassiveBluetoothCandidateObservationSnapshot] = []

        for (index, phase) in PassiveBluetoothPowerCycleObservationPhase.allCases.enumerated() {
            let sequence = PassiveBluetoothCandidateObservationWindowSequence(rawValue: UInt64(index + 1))
            var candidates = [
                PassiveBluetoothCandidateObservationSnapshot.Candidate(id: ambient, isConnectable: true)
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
            id: UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!,
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
