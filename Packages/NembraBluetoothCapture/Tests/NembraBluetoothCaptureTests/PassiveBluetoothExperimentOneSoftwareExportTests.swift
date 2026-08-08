import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Experiment One software export provenance")
struct PassiveBluetoothExperimentOneSoftwareExportTests {
    private typealias Codec = PassiveBluetoothExperimentOneSoftwareExportCodec
    private typealias ExportError = PassiveBluetoothExperimentOneSoftwareExportError

    private let scooter = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let neighbor = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    private let buildInstance = "12345678-90ab-cdef-1234-567890abcdef"
    private let commit = "0123456789abcdef0123456789abcdef01234567"

    @Test("round trip preserves exact bytes, producer authority, declared setup, target, and build rendezvous")
    func roundTripPreservesBoundEvidence() throws {
        let captureJSON = try makeCaptureJSON()
        let result = try makePowerCycleResult()
        let identity = try makeBuildIdentity()
        let declaredSetup = setup()

        let export = try Codec.make(
            captureJSON: captureJSON,
            powerCycleResult: result,
            runtimeBuildIdentity: identity,
            setup: declaredSetup
        )
        let encoded = try Codec.encode(export)
        let verified = try Codec.decodeAndVerify(encoded)

        #expect(verified == export)
        #expect(verified.captureJSON == captureJSON)
        #expect(verified.experimentRecipeID == .es80FingerprintV1)
        #expect(Set(verified.correlationWindows.map(\.observationSeriesIdentity)).count == 1)
        #expect(
            verified.correlationWindows.map(\.observationSeriesIdentity) ==
            result.observationSnapshots.map { $0.observationSeriesIdentity.rawValue }
        )
        #expect(verified.build.buildInstanceID == buildInstance)
        #expect(verified.build.sourceCommitSHA == commit)

        let manifest = try PassiveBluetoothStationaryCaptureManifestJSON.verifyCaptureBinding(
            manifestJSON: verified.stationaryManifestJSON,
            captureJSON: verified.captureJSON
        )
        #expect(manifest.schemaVersion == 3)
        #expect(manifest.experimentRecipeID == .es80FingerprintV1)
        #expect(manifest.nembraBuildInstanceID == buildInstance)
        #expect(manifest.nembraBuildCommitSHA == commit)
        #expect(manifest.sourceArtifact.selectedPeripheralIdentifier == scooter.uuidString)
        #expect(manifest.setup == declaredSetup)
    }

    @Test("construction rejects a power-cycle window one nanosecond below the accepted minimum")
    func shortPowerCycleWindowFailsClosed() throws {
        let result = try makePowerCycleResult(
            windowDurationNanoseconds:
                PassiveBluetoothExperimentOneCapturePolicy.minimumPowerCycleWindowDurationNanoseconds - 1
        )

        #expect(throws: ExportError.experimentEvidenceNotStructurallyCoherent) {
            _ = try Codec.make(
                captureJSON: makeCaptureJSON(),
                powerCycleResult: result,
                runtimeBuildIdentity: makeBuildIdentity(),
                setup: setup()
            )
        }
    }

    @Test("construction rejects overlapping power-cycle windows even when each window is long enough")
    func overlappingPowerCycleWindowsFailClosed() throws {
        let duration = PassiveBluetoothExperimentOneCapturePolicy.minimumPowerCycleWindowDurationNanoseconds
        let result = try makePowerCycleResult(
            windowDurationNanoseconds: duration,
            windowStartStrideNanoseconds: duration / 2
        )

        #expect(throws: ExportError.experimentEvidenceNotStructurallyCoherent) {
            _ = try Codec.make(
                captureJSON: makeCaptureJSON(),
                powerCycleResult: result,
                runtimeBuildIdentity: makeBuildIdentity(),
                setup: setup()
            )
        }
    }

    @Test("construction rejects a Ready-to-Horizon interval one nanosecond below the accepted minimum")
    func shortObservationHorizonFailsClosed() throws {
        let captureJSON = try makeCaptureJSON(
            postReadyDurationNanoseconds:
                PassiveBluetoothExperimentOneCapturePolicy.minimumPostReadyObservationDurationNanoseconds - 1
        )

        #expect(throws: ExportError.experimentEvidenceNotStructurallyCoherent) {
            _ = try Codec.make(
                captureJSON: captureJSON,
                powerCycleResult: makePowerCycleResult(),
                runtimeBuildIdentity: makeBuildIdentity(),
                setup: setup()
            )
        }
    }

    @Test("offline verification rechecks accepted window chronology instead of trusting encoded timing")
    func encodedOverlapFailsClosed() throws {
        var root = try exportJSONObject()
        var windows = try #require(root["correlationWindows"] as? [[String: Any]])
        let firstEnd = try #require(windows[0]["endedAtUptimeNanoseconds"] as? NSNumber).uint64Value
        windows[1]["startedAtUptimeNanoseconds"] = NSNumber(value: firstEnd - 1)
        root["correlationWindows"] = windows

        let tampered = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        #expect(throws: ExportError.experimentEvidenceNotStructurallyCoherent) {
            _ = try Codec.decodeAndVerify(tampered)
        }
    }

    @Test("wire replay cannot mint one authority over catalogs from different producer lives")
    func mixedObservationAuthorityFailsClosed() throws {
        var root = try exportJSONObject()
        var windows = try #require(root["correlationWindows"] as? [[String: Any]])
        windows[1]["observationSeriesIdentity"] = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        root["correlationWindows"] = windows

        let tampered = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        #expect(throws: ExportError.correlationEvidenceInvalid) {
            _ = try Codec.decodeAndVerify(tampered)
        }
    }

    @Test("closed-world envelope rejects nested unknown authority claims")
    func nestedUnknownFieldFailsClosed() throws {
        var root = try exportJSONObject()
        var windows = try #require(root["correlationWindows"] as? [[String: Any]])
        var candidates = try #require(windows[1]["candidates"] as? [[String: Any]])
        candidates[0]["physicallyVerified"] = true
        windows[1]["candidates"] = candidates
        root["correlationWindows"] = windows

        let tampered = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        #expect(
            throws: ExportError.unexpectedWireField(
                "correlationWindows[1].candidates[0].physicallyVerified"
            )
        ) {
            _ = try Codec.decodeAndVerify(tampered)
        }
    }

    @Test("build metadata cannot diverge from stationary manifest binding")
    func detachedBuildMetadataFailsClosed() throws {
        var root = try exportJSONObject()
        var build = try #require(root["build"] as? [String: Any])
        build["sourceCommitSHA"] = "abcdef0123456789abcdef0123456789abcdef01"
        root["build"] = build

        let tampered = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        #expect(throws: ExportError.manifestBuildMismatch) {
            _ = try Codec.decodeAndVerify(tampered)
        }
    }

    @Test("exact capture bytes remain bound even when tampering preserves valid JSON")
    func captureByteTamperFailsClosed() throws {
        var root = try exportJSONObject()
        let originalBase64 = try #require(root["captureJSONBase64"] as? String)
        var capture = try #require(Data(base64Encoded: originalBase64))
        capture.append(0x0A)
        root["captureJSONBase64"] = capture.base64EncodedString()

        let tampered = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        #expect(
            throws: PassiveBluetoothStationaryCaptureManifestError.manifestDoesNotMatchCapture
        ) {
            _ = try Codec.decodeAndVerify(tampered)
        }
    }

    @Test("construction rejects detached correlation summary even when catalogs remain valid")
    func detachedCorrelationSummaryFailsClosed() throws {
        let valid = try makePowerCycleResult()
        var alteredSnapshots = valid.observationSnapshots
        alteredSnapshots[1] = try PassiveBluetoothCandidateObservationSnapshot(
            observationSeriesIdentity: PassiveBluetoothCandidateObservationSeriesIdentity(),
            windowSequence: alteredSnapshots[1].windowSequence,
            candidates: alteredSnapshots[1].candidates
        )
        let detached = PassiveBluetoothPowerCycleObservationResult(
            windows: valid.windows,
            observationSnapshots: alteredSnapshots,
            correlation: valid.correlation
        )

        #expect(throws: ExportError.correlationEvidenceInvalid) {
            _ = try Codec.make(
                captureJSON: makeCaptureJSON(),
                powerCycleResult: detached,
                runtimeBuildIdentity: makeBuildIdentity(),
                setup: setup()
            )
        }
    }

    private func exportJSONObject() throws -> [String: Any] {
        let export = try Codec.make(
            captureJSON: makeCaptureJSON(),
            powerCycleResult: makePowerCycleResult(),
            runtimeBuildIdentity: makeBuildIdentity(),
            setup: setup()
        )
        return try #require(
            JSONSerialization.jsonObject(with: Codec.encode(export)) as? [String: Any]
        )
    }

    private func setup() -> PassiveBluetoothStationaryCaptureSetup {
        .init(
            chargerState: .disconnected,
            executionContext: .foregroundUnlockedScreenOn,
            stockAppReferenceSetup: .none
        )
    }

    private func makeBuildIdentity() throws -> PassiveBluetoothCaptureRuntimeBuildIdentity {
        try PassiveBluetoothCaptureRuntimeBuildIdentityReader.resolveEmbeddedMetadata(
            infoDictionary: [
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildIdentifierInfoDictionaryKey:
                    "Capture Build V14-F1",
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildInstanceIDInfoDictionaryKey:
                    buildInstance,
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.sourceCommitSHAInfoDictionaryKey:
                    commit
            ],
            executableData: Data("fixture executable".utf8),
            infoPlistData: Data("fixture Info.plist".utf8)
        )
    }

    private func makePowerCycleResult(
        windowDurationNanoseconds: UInt64 =
            PassiveBluetoothExperimentOneCapturePolicy.minimumPowerCycleWindowDurationNanoseconds,
        windowStartStrideNanoseconds: UInt64 = 20_000_000_000
    ) throws -> PassiveBluetoothPowerCycleObservationResult {
        var ledger = PassiveBluetoothPowerCycleObservationLedger(minimumWindowDurationNanoseconds: 1)
        var result: PassiveBluetoothPowerCycleObservationResult?

        for (index, phase) in PassiveBluetoothPowerCycleObservationPhase.allCases.enumerated() {
            let start = UInt64(index) * windowStartStrideNanoseconds
            let candidates = phase.operatorExpectedPowerOn
                ? [candidate(neighbor), candidate(scooter)]
                : [candidate(neighbor)]
            result = try ledger.completeWindow(
                phase: phase,
                startedAtUptimeNanoseconds: start,
                endedAtUptimeNanoseconds: start + windowDurationNanoseconds,
                candidates: candidates
            ) ?? result
        }

        return try #require(result)
    }

    private func candidate(_ id: UUID) -> PassiveBluetoothCandidateObservationSnapshot.Candidate {
        .init(id: id, isConnectable: true)
    }

    private func makeCaptureJSON(
        postReadyDurationNanoseconds: UInt64 =
            PassiveBluetoothExperimentOneCapturePolicy.minimumPostReadyObservationDurationNanoseconds
    ) throws -> Data {
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
        let characteristic = PassiveBluetoothCaptureRecord(
            sequenceNumber: 2,
            receivedAtUptimeNanoseconds: 2,
            receivedAtDate: startedAt.addingTimeInterval(1),
            event: .characteristic(
                try PassiveBluetoothCharacteristicObservation(
                    peripheralIdentifier: scooter.uuidString,
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
                    peripheralIdentifier: scooter.uuidString,
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
            observedAtUptimeNanoseconds: readyUptime + postReadyDurationNanoseconds,
            observedAtDate: startedAt.addingTimeInterval(63)
        )
        let session = try PassiveBluetoothCaptureSession(
            id: UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!,
            vehicleIdentity: VehicleIdentity(
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
