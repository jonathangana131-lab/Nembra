import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Experiment One software export structural gate")
struct PassiveBluetoothExperimentOneSoftwareExportStructuralGateTests {
    private typealias Codec = PassiveBluetoothExperimentOneSoftwareExportCodec
    private typealias ExportError = PassiveBluetoothExperimentOneSoftwareExportError

    private let scooter = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let neighbor = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    private let commit = "0123456789abcdef0123456789abcdef01234567"
    private let buildInstance = "12345678-90ab-cdef-1234-567890abcdef"

    @Test("fully compliant sealed recipe structure round trips")
    func compliantRoundTrip() throws {
        let export = try makeExport()
        let verified = try Codec.decodeAndVerify(Codec.encode(export))

        #expect(verified == export)
        #expect(verified.experimentRecipeID == .es80FingerprintV1)
        #expect(verified.correlationWindows.count == 4)
        #expect(verified.correlationWindows.allSatisfy { window in
            window.endedAtUptimeNanoseconds - window.startedAtUptimeNanoseconds
                >= PassiveBluetoothExperimentOneCapturePolicy.minimumPowerCycleWindowDurationNanoseconds
        })
    }

    @Test("construction rejects capture without Ready and Horizon evidence")
    func horizonlessCaptureCannotBeExported() throws {
        #expect(throws: ExportError.structuralEvidenceRejected) {
            _ = try Codec.make(
                captureJSON: horizonlessCaptureJSON(),
                powerCycleResult: powerCycleResult(),
                runtimeBuildIdentity: buildIdentity(),
                setup: setup()
            )
        }
    }

    @Test("construction rejects subminimum OFF ON windows")
    func shortPowerCycleCannotBeExported() throws {
        #expect(throws: ExportError.structuralEvidenceRejected) {
            _ = try Codec.make(
                captureJSON: compliantCaptureJSON(),
                powerCycleResult: powerCycleResult(
                    duration: PassiveBluetoothExperimentOneCapturePolicy
                        .minimumPowerCycleWindowDurationNanoseconds - 1
                ),
                runtimeBuildIdentity: buildIdentity(),
                setup: setup()
            )
        }
    }

    @Test("decode rejects self-consistent imported windows with impossible overlap")
    func overlappingImportedChronologyFailsClosed() throws {
        var root = try #require(
            JSONSerialization.jsonObject(with: Codec.encode(makeExport())) as? [String: Any]
        )
        var windows = try #require(root["correlationWindows"] as? [[String: Any]])
        let firstEnd = try #require(windows[0]["endedAtUptimeNanoseconds"] as? UInt64)
        windows[1]["startedAtUptimeNanoseconds"] = firstEnd - 1
        root["correlationWindows"] = windows
        let tampered = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])

        #expect(throws: ExportError.structuralEvidenceRejected) {
            _ = try Codec.decodeAndVerify(tampered)
        }
    }

    @Test("decode rejects self-consistent imported subminimum windows")
    func shortImportedWindowFailsClosed() throws {
        var root = try #require(
            JSONSerialization.jsonObject(with: Codec.encode(makeExport())) as? [String: Any]
        )
        var windows = try #require(root["correlationWindows"] as? [[String: Any]])
        let start = try #require(windows[2]["startedAtUptimeNanoseconds"] as? UInt64)
        windows[2]["endedAtUptimeNanoseconds"] = start
            + PassiveBluetoothExperimentOneCapturePolicy.minimumPowerCycleWindowDurationNanoseconds - 1
        root["correlationWindows"] = windows
        let tampered = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])

        #expect(throws: ExportError.structuralEvidenceRejected) {
            _ = try Codec.decodeAndVerify(tampered)
        }
    }

    private func makeExport() throws -> PassiveBluetoothExperimentOneSoftwareExport {
        try Codec.make(
            captureJSON: compliantCaptureJSON(),
            powerCycleResult: powerCycleResult(),
            runtimeBuildIdentity: buildIdentity(),
            setup: setup()
        )
    }

    private func setup() -> PassiveBluetoothStationaryCaptureSetup {
        .init(
            chargerState: .disconnected,
            executionContext: .foregroundUnlockedScreenOn,
            stockAppReferenceSetup: .none
        )
    }

    private func buildIdentity() throws -> PassiveBluetoothCaptureRuntimeBuildIdentity {
        try PassiveBluetoothCaptureRuntimeBuildIdentityReader.resolveEmbeddedMetadata(
            infoDictionary: [
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildIdentifierInfoDictionaryKey:
                    "Capture Build V14-structural-gate",
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildInstanceIDInfoDictionaryKey:
                    buildInstance,
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.sourceCommitSHAInfoDictionaryKey:
                    commit,
            ],
            executableData: Data("structural gate fixture executable".utf8)
        )
    }

    private func powerCycleResult(
        duration: UInt64 = PassiveBluetoothExperimentOneCapturePolicy
            .minimumPowerCycleWindowDurationNanoseconds
    ) throws -> PassiveBluetoothPowerCycleObservationResult {
        var ledger = PassiveBluetoothPowerCycleObservationLedger(minimumWindowDurationNanoseconds: 1)
        var result: PassiveBluetoothPowerCycleObservationResult?

        for (index, phase) in PassiveBluetoothPowerCycleObservationPhase.allCases.enumerated() {
            let start = UInt64(index) * 20_000_000_000
            let candidates: [PassiveBluetoothCandidateObservationSnapshot.Candidate]
            if phase.operatorExpectedPowerOn {
                candidates = [candidate(neighbor), candidate(scooter)]
            } else {
                candidates = [candidate(neighbor)]
            }
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

    private func compliantCaptureJSON() throws -> Data {
        try PassiveBluetoothCaptureJSON.encode(captureSession(includeBoundaries: true))
    }

    private func horizonlessCaptureJSON() throws -> Data {
        try PassiveBluetoothCaptureJSON.encode(captureSession(includeBoundaries: false))
    }

    private func captureSession(includeBoundaries: Bool) throws -> PassiveBluetoothCaptureSession {
        let startedAt = Date(timeIntervalSince1970: 1_750_000_000)
        let record = PassiveBluetoothCaptureRecord(
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 100,
            receivedAtDate: startedAt,
            event: .service(
                try PassiveBluetoothServiceObservation(
                    peripheralIdentifier: scooter.uuidString,
                    serviceUUID: "FFE0",
                    isPrimary: true
                )
            )
        )

        let boundaries: [PassiveBluetoothObservationBoundary]
        if includeBoundaries {
            let readyUptime: UInt64 = 1_000
            boundaries = [
                .init(
                    kind: .finiteAcquisitionReady,
                    recordSequenceWatermark: 1,
                    observedAtUptimeNanoseconds: readyUptime,
                    observedAtDate: startedAt.addingTimeInterval(1)
                ),
                .init(
                    kind: .observationHorizon,
                    recordSequenceWatermark: 1,
                    observedAtUptimeNanoseconds: readyUptime
                        + PassiveBluetoothExperimentOneCapturePolicy
                            .minimumPostReadyObservationDurationNanoseconds,
                    observedAtDate: startedAt.addingTimeInterval(61)
                ),
            ]
        } else {
            boundaries = []
        }

        return try PassiveBluetoothCaptureSession(
            id: UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!,
            vehicleIdentity: VehicleProfile.aovoproES80.identity,
            startedAt: startedAt,
            records: [record],
            observationBoundaries: boundaries
        )
    }
}
