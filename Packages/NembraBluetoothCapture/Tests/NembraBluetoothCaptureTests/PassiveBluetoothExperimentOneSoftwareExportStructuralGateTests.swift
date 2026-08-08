import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Experiment One software export structural gate")
struct PassiveBluetoothExperimentOneSoftwareExportStructuralGateTests {
    private typealias Codec = PassiveBluetoothExperimentOneSoftwareExportCodec
    private typealias ExportError = PassiveBluetoothExperimentOneSoftwareExportError

    private let target = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let neighbor = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    @Test("sub-10-second OFF ON windows cannot be promoted as the sealed recipe")
    func shortPowerCycleRejectedAtCreation() throws {
        #expect(throws: ExportError.recipeStructuralEvidenceInvalid) {
            _ = try Codec.make(
                captureJSON: makeCapture(includeHorizon: true),
                powerCycleResult: makePowerCycleResult(windowDuration: 1_000_000_000),
                runtimeBuildIdentity: makeBuildIdentity(),
                setup: setup()
            )
        }
    }

    @Test("missing Ready Horizon evidence cannot be promoted as the sealed recipe")
    func missingHorizonRejectedAtCreation() throws {
        #expect(throws: ExportError.recipeStructuralEvidenceInvalid) {
            _ = try Codec.make(
                captureJSON: makeCapture(includeHorizon: false),
                powerCycleResult: makePowerCycleResult(
                    windowDuration: PassiveBluetoothExperimentOneCapturePolicy.minimumPowerCycleWindowDurationNanoseconds
                ),
                runtimeBuildIdentity: makeBuildIdentity(),
                setup: setup()
            )
        }
    }

    @Test("import rechecks window duration instead of trusting a self-consistent target replay")
    func shortPowerCycleRejectedOnImport() throws {
        var root = try validJSONObject()
        var windows = try #require(root["correlationWindows"] as? [[String: Any]])
        var first = windows[0]
        let start = try #require(first["startedAtUptimeNanoseconds"] as? NSNumber).uint64Value
        first["endedAtUptimeNanoseconds"] = NSNumber(value: start + 1_000_000_000)
        windows[0] = first
        root["correlationWindows"] = windows

        let tampered = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        #expect(throws: ExportError.recipeStructuralEvidenceInvalid) {
            _ = try Codec.decodeAndVerify(tampered)
        }
    }

    @Test("import rejects cross-window overlap impossible for the serial producer")
    func overlappingPowerCycleWindowsRejectedOnImport() throws {
        var root = try validJSONObject()
        var windows = try #require(root["correlationWindows"] as? [[String: Any]])
        var second = windows[1]
        second["startedAtUptimeNanoseconds"] = NSNumber(value: 5_000_000_000)
        second["endedAtUptimeNanoseconds"] = NSNumber(value: 15_000_000_000)
        windows[1] = second
        root["correlationWindows"] = windows

        let tampered = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        #expect(throws: ExportError.recipeStructuralEvidenceInvalid) {
            _ = try Codec.decodeAndVerify(tampered)
        }
    }

    @Test("import independently rejects Horizon-less capture even when manifest is rebound")
    func reboundHorizonlessCaptureRejectedOnImport() throws {
        var root = try validJSONObject()
        let horizonlessCapture = try makeCapture(includeHorizon: false)
        let reboundManifest = try PassiveBluetoothStationaryCaptureManifestBuilder.make(
            captureJSON: horizonlessCapture,
            experimentRecipe: .es80FingerprintV1,
            nembraBuildIdentifier: "Capture Build V14-abcdef012345",
            nembraBuildInstanceID: "a1b2c3d4-e5f6-47a8-90bc-def123456789",
            nembraBuildCommitSHA: "abcdef0123456789abcdef0123456789abcdef01",
            selectedPeripheralIdentifier: target.uuidString,
            setup: setup()
        )
        root["captureJSONBase64"] = horizonlessCapture.base64EncodedString()
        root["stationaryManifestJSONBase64"] = try PassiveBluetoothStationaryCaptureManifestJSON
            .encode(reboundManifest)
            .base64EncodedString()

        let tampered = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        #expect(throws: ExportError.recipeStructuralEvidenceInvalid) {
            _ = try Codec.decodeAndVerify(tampered)
        }
    }

    private func validJSONObject() throws -> [String: Any] {
        let export = try Codec.make(
            captureJSON: makeCapture(includeHorizon: true),
            powerCycleResult: makePowerCycleResult(
                windowDuration: PassiveBluetoothExperimentOneCapturePolicy.minimumPowerCycleWindowDurationNanoseconds
            ),
            runtimeBuildIdentity: makeBuildIdentity(),
            setup: setup()
        )
        return try #require(JSONSerialization.jsonObject(with: Codec.encode(export)) as? [String: Any])
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
                    "Capture Build V14-abcdef012345",
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildInstanceIDInfoDictionaryKey:
                    "a1b2c3d4-e5f6-47a8-90bc-def123456789",
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.sourceCommitSHAInfoDictionaryKey:
                    "abcdef0123456789abcdef0123456789abcdef01"
            ],
            executableData: Data("structural fixture".utf8)
        )
    }

    private func makePowerCycleResult(windowDuration: UInt64) throws
        -> PassiveBluetoothPowerCycleObservationResult {
        var ledger = PassiveBluetoothPowerCycleObservationLedger(minimumWindowDurationNanoseconds: 1)
        let starts: [UInt64] = [0, 20_000_000_000, 40_000_000_000, 60_000_000_000]
        var final: PassiveBluetoothPowerCycleObservationResult?
        for (index, phase) in PassiveBluetoothPowerCycleObservationPhase.allCases.enumerated() {
            let candidates = phase.operatorExpectedPowerOn
                ? [candidate(neighbor), candidate(target)]
                : [candidate(neighbor)]
            final = try ledger.completeWindow(
                phase: phase,
                startedAtUptimeNanoseconds: starts[index],
                endedAtUptimeNanoseconds: starts[index] + windowDuration,
                candidates: candidates
            ) ?? final
        }
        return try #require(final)
    }

    private func candidate(_ id: UUID) -> PassiveBluetoothCandidateObservationSnapshot.Candidate {
        .init(id: id, isConnectable: true)
    }

    private func makeCapture(includeHorizon: Bool) throws -> Data {
        let startedAt = Date(timeIntervalSince1970: 1_750_000_000)
        var session = try PassiveBluetoothCaptureSession(
            id: UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!,
            vehicleIdentity: .init(
                manufacturer: "AOVOPRO",
                model: "ES80",
                displayName: "AOVOPRO ES80",
                protocolFamily: "unverified-tuya"
            ),
            startedAt: startedAt
        )
        try session.append(
            .service(try PassiveBluetoothServiceObservation(
                peripheralIdentifier: target.uuidString,
                serviceUUID: "FFE0",
                isPrimary: true
            )),
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 1_000_000_000,
            receivedAtDate: startedAt.addingTimeInterval(1)
        )
        if includeHorizon {
            try session.appendObservationBoundary(.init(
                kind: .finiteAcquisitionReady,
                recordSequenceWatermark: 1,
                observedAtUptimeNanoseconds: 2_000_000_000,
                observedAtDate: startedAt.addingTimeInterval(2)
            ))
            try session.appendObservationBoundary(.init(
                kind: .observationHorizon,
                recordSequenceWatermark: 1,
                observedAtUptimeNanoseconds:
                    2_000_000_000 + PassiveBluetoothExperimentOneCapturePolicy.minimumPostReadyObservationDurationNanoseconds,
                observedAtDate: startedAt.addingTimeInterval(62)
            ))
        }
        return try PassiveBluetoothCaptureJSON.encode(session)
    }
}
