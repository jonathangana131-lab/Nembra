import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Experiment One software Share-envelope integrity")
struct PassiveBluetoothExperimentOneSoftwareExportIntegrityTests {
    private let scooter = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let sessionID = UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!

    @Test("exact shared envelope earns deterministic readability facts")
    func exactSharedEnvelopeEarnsReport() throws {
        let export = try PassiveBluetoothExperimentOneSoftwareExportCodec.make(
            captureJSON: makeCaptureJSON(),
            powerCycleResult: makePowerCycleResult(),
            runtimeBuildIdentity: makeBuildIdentity(),
            setup: .init(
                chargerState: .disconnected,
                executionContext: .foregroundUnlockedScreenOn,
                stockAppReferenceSetup: .none
            )
        )
        let exactBytes = try PassiveBluetoothExperimentOneSoftwareExportCodec.encode(export)

        let report = try PassiveBluetoothExperimentOneSoftwareExportIntegrity.inspect(exactBytes)

        #expect(report.envelopeByteCount == exactBytes.count)
        #expect(report.envelopeSHA256 == PassiveBluetoothFinalizedArtifactIntegrity.sha256Hex(of: exactBytes))
        #expect(report.capture.captureSessionID == sessionID)
        #expect(report.capture.byteCount == export.captureJSON.count)
        #expect(report.experimentRecipeID == .es80FingerprintV1)
        #expect(report.buildInstanceID == export.build.buildInstanceID)
    }

    @Test("malformed outer bytes never earn analysis readiness")
    func malformedOuterBytesFailClosed() {
        #expect(throws: (any Error).self) {
            _ = try PassiveBluetoothExperimentOneSoftwareExportIntegrity.inspect(
                Data("{not-an-export".utf8)
            )
        }
    }

    private func makeBuildIdentity() throws -> PassiveBluetoothCaptureRuntimeBuildIdentity {
        try PassiveBluetoothCaptureRuntimeBuildIdentityReader.resolveEmbeddedMetadata(
            infoDictionary: [
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildIdentifierInfoDictionaryKey:
                    "Capture Build V14-F1",
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildInstanceIDInfoDictionaryKey:
                    "12345678-90ab-cdef-1234-567890abcdef",
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.sourceCommitSHAInfoDictionaryKey:
                    "0123456789abcdef0123456789abcdef01234567",
            ],
            executableData: Data("fixture executable".utf8),
            infoPlistData: Data("fixture Info.plist".utf8)
        )
    }

    private func makePowerCycleResult() throws -> PassiveBluetoothPowerCycleObservationResult {
        let duration = PassiveBluetoothExperimentOneCapturePolicy.minimumPowerCycleWindowDurationNanoseconds
        var ledger = PassiveBluetoothPowerCycleObservationLedger(
            minimumWindowDurationNanoseconds: duration
        )
        _ = try ledger.completeWindow(
            phase: .firstPoweredOff,
            startedAtUptimeNanoseconds: 10,
            endedAtUptimeNanoseconds: 10 + duration,
            candidates: []
        )
        _ = try ledger.completeWindow(
            phase: .firstPoweredOn,
            startedAtUptimeNanoseconds: 20_000_000_020,
            endedAtUptimeNanoseconds: 20_000_000_020 + duration,
            candidates: [.init(id: scooter, isConnectable: true)]
        )
        _ = try ledger.completeWindow(
            phase: .secondPoweredOff,
            startedAtUptimeNanoseconds: 40_000_000_030,
            endedAtUptimeNanoseconds: 40_000_000_030 + duration,
            candidates: []
        )
        let completed = try ledger.completeWindow(
            phase: .secondPoweredOn,
            startedAtUptimeNanoseconds: 60_000_000_040,
            endedAtUptimeNanoseconds: 60_000_000_040 + duration,
            candidates: [.init(id: scooter, isConnectable: true)]
        )
        return try #require(completed)
    }

    private func makeCaptureJSON() throws -> Data {
        let startedAt = Date(timeIntervalSince1970: 1_750_000_000)
        let service = PassiveBluetoothCaptureRecord(
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 1,
            receivedAtDate: startedAt,
            event: .service(
                try PassiveBluetoothServiceObservation(
                    peripheralIdentifier: scooter.uuidString,
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
                    peripheralIdentifier: scooter.uuidString,
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
            vehicleIdentity: VehicleIdentity(
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
