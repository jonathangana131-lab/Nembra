import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Experiment One software export executable provenance")
struct PassiveBluetoothExperimentOneSoftwareExportExecutableDigestBindingTests {
    private typealias Codec = PassiveBluetoothExperimentOneSoftwareExportCodec
    private typealias ExportError = PassiveBluetoothExperimentOneSoftwareExportError

    private let scooter = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let commit = "0123456789abcdef0123456789abcdef01234567"

    @Test("decoder must not silently accept a detached executable digest as verified provenance")
    func detachedExecutableDigestFailsClosed() throws {
        let export = try Codec.make(
            captureJSON: makeCaptureJSON(),
            powerCycleResult: makePowerCycleResult(),
            runtimeBuildIdentity: makeBuildIdentity()
        )
        let encoded = try Codec.encode(export)
        var root = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var build = try #require(root["build"] as? [String: Any])
        build["executableSHA256"] = String(repeating: "f", count: 64)
        root["build"] = build
        let tampered = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])

        // The manifest binds the build label, build-instance rendezvous, and source SHA, but schema v3
        // does not bind the running executable digest. A plain decode must therefore not imply that
        // this independently editable digest was verified. Keep this expected RED until the export
        // either binds the digest to package-owned immutable provenance or moves digest comparison
        // behind an explicit independently supplied trusted-build verification API.
        #expect(throws: ExportError.manifestBuildMismatch) {
            _ = try Codec.decodeAndVerify(tampered)
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
                    commit,
            ],
            executableData: Data("fixture executable".utf8)
        )
    }

    private func makePowerCycleResult() throws -> PassiveBluetoothPowerCycleObservationResult {
        var ledger = PassiveBluetoothPowerCycleObservationLedger(minimumWindowDurationNanoseconds: 1)
        _ = try ledger.completeWindow(
            phase: .firstPoweredOff,
            startedAtUptimeNanoseconds: 10,
            endedAtUptimeNanoseconds: 11,
            candidates: []
        )
        _ = try ledger.completeWindow(
            phase: .firstPoweredOn,
            startedAtUptimeNanoseconds: 20,
            endedAtUptimeNanoseconds: 21,
            candidates: [.init(id: scooter, isConnectable: true)]
        )
        _ = try ledger.completeWindow(
            phase: .secondPoweredOff,
            startedAtUptimeNanoseconds: 30,
            endedAtUptimeNanoseconds: 31,
            candidates: []
        )
        return try #require(ledger.completeWindow(
            phase: .secondPoweredOn,
            startedAtUptimeNanoseconds: 40,
            endedAtUptimeNanoseconds: 41,
            candidates: [.init(id: scooter, isConnectable: true)]
        ))
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
            receivedAtUptimeNanoseconds: 1,
            receivedAtDate: startedAt
        )
        return try PassiveBluetoothCaptureJSON.encode(session)
    }
}
