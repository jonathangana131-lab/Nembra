import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Experiment One software export structural gate")
struct PassiveBluetoothExperimentOneSoftwareExportStructuralGateTests {
    private let target = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let neighbor = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let sessionID = UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!
    private let commit = "abcdef0123456789abcdef0123456789abcdef01"
    private let buildIdentifier = "Capture Build V14-abcdef012345"
    private let buildInstanceID = "a1b2c3d4-e5f6-47a8-90bc-def123456789"

    private var declaredSetup: PassiveBluetoothStationaryCaptureSetup {
        .init(
            chargerState: .disconnected,
            executionContext: .foregroundUnlockedScreenOn,
            stockAppReferenceSetup: .none
        )
    }

    @Test("fully recipe-compliant software evidence still round-trips")
    func compliantEvidenceRoundTrips() throws {
        let captureJSON = try makeCapture(includeObservationHorizon: true)
        let result = try makePowerCycleResult(
            windowDurationNanoseconds:
                PassiveBluetoothExperimentOneCapturePolicy.minimumPowerCycleWindowDurationNanoseconds
        )
        let softwareExport = try PassiveBluetoothExperimentOneSoftwareExportCodec.make(
            captureJSON: captureJSON,
            powerCycleResult: result,
            runtimeBuildIdentity: makeRuntimeBuildIdentity(),
            setup: declaredSetup
        )

        let encoded = try PassiveBluetoothExperimentOneSoftwareExportCodec.encode(softwareExport)
        let verified = try PassiveBluetoothExperimentOneSoftwareExportCodec.decodeAndVerify(encoded)

        #expect(verified == softwareExport)
        #expect(verified.experimentRecipeID == .es80FingerprintV1)
        #expect(verified.correlationWindows.count == 4)
    }

    @Test("sub-10-second power windows cannot be promoted as ES80-FINGERPRINT-v1")
    func shortPowerCycleWindowsMustFailClosedAtExportCreation() throws {
        let minimum = PassiveBluetoothExperimentOneCapturePolicy
            .minimumPowerCycleWindowDurationNanoseconds
        let captureJSON = try makeCapture(includeObservationHorizon: true)
        let result = try makePowerCycleResult(windowDurationNanoseconds: minimum - 1)

        #expect(throws: PassiveBluetoothExperimentOneSoftwareExportError.experimentOneStructuralEvidenceRejected) {
            _ = try PassiveBluetoothExperimentOneSoftwareExportCodec.make(
                captureJSON: captureJSON,
                powerCycleResult: result,
                runtimeBuildIdentity: makeRuntimeBuildIdentity(),
                setup: declaredSetup
            )
        }
    }

    @Test("capture without Ready/Horizon evidence cannot be promoted as Experiment One software export")
    func missingObservationHorizonMustFailClosedAtExportCreation() throws {
        let captureJSON = try makeCapture(includeObservationHorizon: false)
        let result = try makePowerCycleResult(
            windowDurationNanoseconds:
                PassiveBluetoothExperimentOneCapturePolicy.minimumPowerCycleWindowDurationNanoseconds
        )

        #expect(throws: PassiveBluetoothExperimentOneSoftwareExportError.experimentOneStructuralEvidenceRejected) {
            _ = try PassiveBluetoothExperimentOneSoftwareExportCodec.make(
                captureJSON: captureJSON,
                powerCycleResult: result,
                runtimeBuildIdentity: makeRuntimeBuildIdentity(),
                setup: declaredSetup
            )
        }
    }

    @Test("decoder rechecks the ten-second recipe threshold instead of trusting self-consistent correlation")
    func decodedShortWindowMustFailClosed() throws {
        let encoded = try makeValidEncodedExport()
        var root = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var windows = try #require(root["correlationWindows"] as? [[String: Any]])
        var first = windows[0]
        let started = try #require(first["startedAtUptimeNanoseconds"] as? NSNumber).uint64Value
        first["endedAtUptimeNanoseconds"] = NSNumber(
            value: started
                + PassiveBluetoothExperimentOneCapturePolicy.minimumPowerCycleWindowDurationNanoseconds
                - 1
        )
        windows[0] = first
        root["correlationWindows"] = windows
        let tampered = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])

        #expect(throws: PassiveBluetoothExperimentOneSoftwareExportError.experimentOneStructuralEvidenceRejected) {
            _ = try PassiveBluetoothExperimentOneSoftwareExportCodec.decodeAndVerify(tampered)
        }
    }

    @Test("decoder rejects cross-window clock overlap that the one-window-at-a-time producer cannot issue")
    func decodedCrossWindowClockOverlapMustFailClosed() throws {
        let encoded = try makeValidEncodedExport()
        var root = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var windows = try #require(root["correlationWindows"] as? [[String: Any]])
        var second = windows[1]
        second["startedAtUptimeNanoseconds"] = NSNumber(value: 5_000_000_000)
        second["endedAtUptimeNanoseconds"] = NSNumber(value: 15_000_000_000)
        windows[1] = second
        root["correlationWindows"] = windows
        let tampered = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])

        #expect(throws: PassiveBluetoothExperimentOneSoftwareExportError.experimentOneStructuralEvidenceRejected) {
            _ = try PassiveBluetoothExperimentOneSoftwareExportCodec.decodeAndVerify(tampered)
        }
    }

    @Test("decoder rejects horizonless capture bytes even when the outer envelope started valid")
    func decodedHorizonlessCaptureTamperMustFailClosed() throws {
        let encoded = try makeValidEncodedExport()
        var root = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let horizonless = try makeCapture(includeObservationHorizon: false)
        root["captureJSONBase64"] = horizonless.base64EncodedString()
        let tampered = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])

        #expect(throws: PassiveBluetoothExperimentOneSoftwareExportError.experimentOneStructuralEvidenceRejected) {
            _ = try PassiveBluetoothExperimentOneSoftwareExportCodec.decodeAndVerify(tampered)
        }
    }

    @Test("decoder rejects a Ready-to-Horizon interval one nanosecond below policy")
    func decodedShortObservationHorizonMustFailClosed() throws {
        let encoded = try makeValidEncodedExport()
        var root = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let tooShort = try makeCapture(
            includeObservationHorizon: true,
            postReadyDurationNanoseconds:
                PassiveBluetoothExperimentOneCapturePolicy.minimumPostReadyObservationDurationNanoseconds - 1
        )
        root["captureJSONBase64"] = tooShort.base64EncodedString()
        let tampered = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])

        #expect(throws: PassiveBluetoothExperimentOneSoftwareExportError.experimentOneStructuralEvidenceRejected) {
            _ = try PassiveBluetoothExperimentOneSoftwareExportCodec.decodeAndVerify(tampered)
        }
    }

    private func makeValidEncodedExport() throws -> Data {
        let softwareExport = try PassiveBluetoothExperimentOneSoftwareExportCodec.make(
            captureJSON: makeCapture(includeObservationHorizon: true),
            powerCycleResult: makePowerCycleResult(
                windowDurationNanoseconds:
                    PassiveBluetoothExperimentOneCapturePolicy.minimumPowerCycleWindowDurationNanoseconds
            ),
            runtimeBuildIdentity: makeRuntimeBuildIdentity(),
            setup: declaredSetup
        )
        return try PassiveBluetoothExperimentOneSoftwareExportCodec.encode(softwareExport)
    }

    private func makeRuntimeBuildIdentity() throws -> PassiveBluetoothCaptureRuntimeBuildIdentity {
        try PassiveBluetoothCaptureRuntimeBuildIdentityReader.resolveEmbeddedMetadata(
            infoDictionary: [
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildIdentifierInfoDictionaryKey: buildIdentifier,
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildInstanceIDInfoDictionaryKey: buildInstanceID,
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.sourceCommitSHAInfoDictionaryKey: commit,
            ],
            executableData: Data([0x4E, 0x45, 0x4D, 0x42, 0x52, 0x41])
        )
    }

    private func candidate(
        _ id: UUID,
        connectable: Bool? = true
    ) -> PassiveBluetoothCandidateObservationSnapshot.Candidate {
        .init(id: id, isConnectable: connectable)
    }

    private func makePowerCycleResult(
        windowDurationNanoseconds duration: UInt64
    ) throws -> PassiveBluetoothPowerCycleObservationResult {
        var ledger = PassiveBluetoothPowerCycleObservationLedger(
            minimumWindowDurationNanoseconds: 1
        )
        let starts: [UInt64] = [
            1,
            20_000_000_000,
            40_000_000_000,
            60_000_000_000,
        ]
        _ = try ledger.completeWindow(
            phase: .firstPoweredOff,
            startedAtUptimeNanoseconds: starts[0],
            endedAtUptimeNanoseconds: starts[0] + duration,
            candidates: [candidate(neighbor)]
        )
        _ = try ledger.completeWindow(
            phase: .firstPoweredOn,
            startedAtUptimeNanoseconds: starts[1],
            endedAtUptimeNanoseconds: starts[1] + duration,
            candidates: [candidate(neighbor), candidate(target)]
        )
        _ = try ledger.completeWindow(
            phase: .secondPoweredOff,
            startedAtUptimeNanoseconds: starts[2],
            endedAtUptimeNanoseconds: starts[2] + duration,
            candidates: [candidate(neighbor)]
        )
        let completed = try ledger.completeWindow(
            phase: .secondPoweredOn,
            startedAtUptimeNanoseconds: starts[3],
            endedAtUptimeNanoseconds: starts[3] + duration,
            candidates: [candidate(neighbor), candidate(target)]
        )
        return try #require(completed)
    }

    private func makeCapture(
        includeObservationHorizon: Bool,
        postReadyDurationNanoseconds: UInt64 =
            PassiveBluetoothExperimentOneCapturePolicy.minimumPostReadyObservationDurationNanoseconds
    ) throws -> Data {
        var session = try PassiveBluetoothCaptureSession(
            id: sessionID,
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
            receivedAtUptimeNanoseconds: 1_000_000_000,
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
            receivedAtUptimeNanoseconds: 2_000_000_000,
            receivedAtDate: Date(timeIntervalSince1970: 1_750_000_002)
        )

        if includeObservationHorizon {
            let readyUptime: UInt64 = 3_000_000_000
            try session.appendObservationBoundary(
                .init(
                    kind: .finiteAcquisitionReady,
                    recordSequenceWatermark: 2,
                    observedAtUptimeNanoseconds: readyUptime,
                    observedAtDate: Date(timeIntervalSince1970: 1_750_000_003)
                )
            )
            try session.appendObservationBoundary(
                .init(
                    kind: .observationHorizon,
                    recordSequenceWatermark: 2,
                    observedAtUptimeNanoseconds: readyUptime + postReadyDurationNanoseconds,
                    observedAtDate: Date(timeIntervalSince1970: 1_750_000_063)
                )
            )
        }

        return try PassiveBluetoothCaptureJSON.encode(session)
    }
}
