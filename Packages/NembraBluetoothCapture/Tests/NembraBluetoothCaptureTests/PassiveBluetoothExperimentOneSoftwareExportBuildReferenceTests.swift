import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Experiment One software export external build reference")
struct PassiveBluetoothExperimentOneSoftwareExportBuildReferenceTests {
    private typealias Codec = PassiveBluetoothExperimentOneSoftwareExportCodec
    private typealias ReferenceError = PassiveBluetoothExperimentOneSoftwareExportBuildReferenceError

    private let scooter = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let buildInstance = "12345678-90ab-cdef-1234-567890abcdef"
    private let commit = "0123456789abcdef0123456789abcdef01234567"

    @Test("exact external build reference binds the wire-carried executable digest")
    func exactExternalBuildReferenceBindsExecutableDigest() throws {
        let identity = try makeBuildIdentity()
        let export = try makeExport(identity: identity)
        let reference = try makeReference(identity: identity)

        let verified = try Codec.decodeAndVerify(
            Codec.encode(export),
            matching: reference
        )

        #expect(verified == export)
        #expect(verified.build.executableSHA256 == identity.executableSHA256)
    }

    @Test("detached executable digest remains software-only and fails exact build matching")
    func detachedExecutableDigestFailsExactBuildMatching() throws {
        let identity = try makeBuildIdentity()
        let export = try makeExport(identity: identity)
        var root = try #require(
            JSONSerialization.jsonObject(with: Codec.encode(export)) as? [String: Any]
        )
        var build = try #require(root["build"] as? [String: Any])
        build["executableSHA256"] = String(repeating: "f", count: 64)
        root["build"] = build
        let tampered = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])

        // The package's one-argument decoder intentionally establishes only software/recipe
        // consistency. The executable digest is not independently attested by self-authored JSON.
        let softwareOnly = try Codec.decodeAndVerify(tampered)
        #expect(softwareOnly.build.executableSHA256 == String(repeating: "f", count: 64))

        #expect(throws: ReferenceError.mismatch) {
            _ = try Codec.decodeAndVerify(tampered, matching: makeReference(identity: identity))
        }
    }

    @Test("comparison reference itself must use canonical exact-build spelling")
    func comparisonReferenceRequiresCanonicalValues() throws {
        let identity = try makeBuildIdentity()
        #expect(throws: ReferenceError.malformedReference) {
            _ = try PassiveBluetoothExperimentOneSoftwareExportBuildReference(
                buildIdentifier: identity.buildIdentifier,
                buildInstanceID: identity.buildInstanceID.uppercased(),
                sourceCommitSHA: identity.sourceCommitSHA,
                executableSHA256: identity.executableSHA256
            )
        }
        #expect(throws: ReferenceError.malformedReference) {
            _ = try PassiveBluetoothExperimentOneSoftwareExportBuildReference(
                buildIdentifier: identity.buildIdentifier,
                buildInstanceID: identity.buildInstanceID,
                sourceCommitSHA: identity.sourceCommitSHA,
                executableSHA256: identity.executableSHA256.uppercased()
            )
        }
    }

    private func makeReference(
        identity: PassiveBluetoothCaptureRuntimeBuildIdentity
    ) throws -> PassiveBluetoothExperimentOneSoftwareExportBuildReference {
        try .init(
            buildIdentifier: identity.buildIdentifier,
            buildInstanceID: identity.buildInstanceID,
            sourceCommitSHA: identity.sourceCommitSHA,
            executableSHA256: identity.executableSHA256
        )
    }

    private func makeExport(
        identity: PassiveBluetoothCaptureRuntimeBuildIdentity
    ) throws -> PassiveBluetoothExperimentOneSoftwareExport {
        try Codec.make(
            captureJSON: makeCaptureJSON(),
            powerCycleResult: makePowerCycleResult(),
            runtimeBuildIdentity: identity,
            setup: .init(
                chargerState: .disconnected,
                executionContext: .foregroundUnlockedScreenOn,
                stockAppReferenceSetup: .none
            )
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

    private func makePowerCycleResult() throws -> PassiveBluetoothPowerCycleObservationResult {
        let duration = PassiveBluetoothExperimentOneCapturePolicy.minimumPowerCycleWindowDurationNanoseconds
        var ledger = PassiveBluetoothPowerCycleObservationLedger(minimumWindowDurationNanoseconds: 1)
        _ = try ledger.completeWindow(
            phase: .firstPoweredOff,
            startedAtUptimeNanoseconds: 0,
            endedAtUptimeNanoseconds: duration,
            candidates: []
        )
        _ = try ledger.completeWindow(
            phase: .firstPoweredOn,
            startedAtUptimeNanoseconds: 20_000_000_000,
            endedAtUptimeNanoseconds: 20_000_000_000 + duration,
            candidates: [.init(id: scooter, isConnectable: true)]
        )
        _ = try ledger.completeWindow(
            phase: .secondPoweredOff,
            startedAtUptimeNanoseconds: 40_000_000_000,
            endedAtUptimeNanoseconds: 40_000_000_000 + duration,
            candidates: []
        )
        let completed = try ledger.completeWindow(
            phase: .secondPoweredOn,
            startedAtUptimeNanoseconds: 60_000_000_000,
            endedAtUptimeNanoseconds: 60_000_000_000 + duration,
            candidates: [.init(id: scooter, isConnectable: true)]
        )
        return try #require(completed)
    }

    private func makeCaptureJSON() throws -> Data {
        let startedAt = Date(timeIntervalSince1970: 1_750_000_000)
        var session = try PassiveBluetoothCaptureSession(
            id: UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!,
            vehicleIdentity: VehicleIdentity(
                manufacturer: "AOVOPRO",
                model: "ES80",
                displayName: "AOVOPRO ES80",
                protocolFamily: "unverified-tuya"
            ),
            startedAt: startedAt
        )
        try session.append(
            .service(try PassiveBluetoothServiceObservation(
                peripheralIdentifier: scooter.uuidString,
                serviceUUID: "FFE0",
                isPrimary: true
            )),
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 1_000_000_000,
            receivedAtDate: startedAt
        )
        try session.append(
            .characteristic(try PassiveBluetoothCharacteristicObservation(
                peripheralIdentifier: scooter.uuidString,
                serviceUUID: "FFE0",
                characteristicUUID: "FFE1",
                properties: [.notify]
            )),
            sequenceNumber: 2,
            receivedAtUptimeNanoseconds: 2_000_000_000,
            receivedAtDate: startedAt.addingTimeInterval(1)
        )
        try session.append(
            .value(try PassiveBluetoothValueObservation(
                peripheralIdentifier: scooter.uuidString,
                serviceUUID: "FFE0",
                characteristicUUID: "FFE1",
                origin: .subscriptionUpdate,
                payload: Data([0x01, 0x02])
            )),
            sequenceNumber: 3,
            receivedAtUptimeNanoseconds: 3_000_000_000,
            receivedAtDate: startedAt.addingTimeInterval(2)
        )
        try session.appendObservationBoundary(
            .init(
                kind: .finiteAcquisitionReady,
                recordSequenceWatermark: 3,
                observedAtUptimeNanoseconds: 4_000_000_000,
                observedAtDate: startedAt.addingTimeInterval(3)
            )
        )
        try session.appendObservationBoundary(
            .init(
                kind: .observationHorizon,
                recordSequenceWatermark: 3,
                observedAtUptimeNanoseconds:
                    4_000_000_000 + PassiveBluetoothExperimentOneCapturePolicy.minimumPostReadyObservationDurationNanoseconds,
                observedAtDate: startedAt.addingTimeInterval(63)
            )
        )
        return try PassiveBluetoothCaptureJSON.encode(session)
    }
}
