import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Experiment One software export window integrity")
struct PassiveBluetoothExperimentOneSoftwareExportWindowIntegrityTests {
    private typealias Codec = PassiveBluetoothExperimentOneSoftwareExportCodec
    private typealias ExportError = PassiveBluetoothExperimentOneSoftwareExportError

    private let scooter = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let neighbor = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    private let buildInstance = "12345678-90ab-cdef-1234-567890abcdef"
    private let commit = "0123456789abcdef0123456789abcdef01234567"

    @Test("serialized receipt cannot shorten the package-fixed ten-second Experiment One window")
    func shortWindowFailsClosed() throws {
        var root = try exportJSONObject()
        var windows = try #require(root["correlationWindows"] as? [[String: Any]])
        let minimum = PassiveBluetoothExperimentOneCapturePolicy
            .minimumPowerCycleWindowDurationNanoseconds
        windows[0]["endedAtUptimeNanoseconds"] = UInt64(10) + minimum - 1
        root["correlationWindows"] = windows

        #expect(throws: ExportError.correlationEvidenceInvalid) {
            _ = try Codec.decodeAndVerify(encode(root))
        }
    }

    @Test("serialized receipt sequence remains the exact producer-issued one through four")
    func nonCanonicalSequenceFailsClosed() throws {
        var root = try exportJSONObject()
        var windows = try #require(root["correlationWindows"] as? [[String: Any]])
        windows[0]["windowSequence"] = UInt64(10)
        windows[1]["windowSequence"] = UInt64(20)
        windows[2]["windowSequence"] = UInt64(30)
        windows[3]["windowSequence"] = UInt64(40)
        root["correlationWindows"] = windows

        #expect(throws: ExportError.correlationWindowSequenceMismatch(index: 0)) {
            _ = try Codec.decodeAndVerify(encode(root))
        }
    }

    @Test("serialized receipt windows cannot overlap in local monotonic chronology")
    func overlappingWindowFailsClosed() throws {
        var root = try exportJSONObject()
        var windows = try #require(root["correlationWindows"] as? [[String: Any]])
        let minimum = PassiveBluetoothExperimentOneCapturePolicy
            .minimumPowerCycleWindowDurationNanoseconds
        windows[1]["startedAtUptimeNanoseconds"] = UInt64(10) + minimum - 1
        root["correlationWindows"] = windows

        #expect(throws: ExportError.correlationEvidenceInvalid) {
            _ = try Codec.decodeAndVerify(encode(root))
        }
    }

    @Test("valid package-fixed windows continue to round-trip unchanged")
    func canonicalWindowsStillRoundTrip() throws {
        let export = try Codec.make(
            captureJSON: makeCaptureJSON(),
            powerCycleResult: makePowerCycleResult(),
            runtimeBuildIdentity: makeBuildIdentity()
        )
        let verified = try Codec.decodeAndVerify(Codec.encode(export))

        #expect(verified == export)
        #expect(verified.correlationWindows.map(\.windowSequence) == [1, 2, 3, 4])
    }

    private func exportJSONObject() throws -> [String: Any] {
        let export = try Codec.make(
            captureJSON: makeCaptureJSON(),
            powerCycleResult: makePowerCycleResult(),
            runtimeBuildIdentity: makeBuildIdentity()
        )
        return try #require(
            JSONSerialization.jsonObject(with: Codec.encode(export)) as? [String: Any]
        )
    }

    private func encode(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
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
            executableData: Data("window integrity fixture executable".utf8)
        )
    }

    private func makePowerCycleResult() throws -> PassiveBluetoothPowerCycleObservationResult {
        let minimum = PassiveBluetoothExperimentOneCapturePolicy
            .minimumPowerCycleWindowDurationNanoseconds
        var ledger = PassiveBluetoothPowerCycleObservationLedger(
            minimumWindowDurationNanoseconds: minimum
        )
        let starts: [UInt64] = [
            10,
            10 + minimum + 10,
            10 + (minimum + 10) * 2,
            10 + (minimum + 10) * 3
        ]

        _ = try ledger.completeWindow(
            phase: .firstPoweredOff,
            startedAtUptimeNanoseconds: starts[0],
            endedAtUptimeNanoseconds: starts[0] + minimum,
            candidates: [candidate(neighbor)]
        )
        _ = try ledger.completeWindow(
            phase: .firstPoweredOn,
            startedAtUptimeNanoseconds: starts[1],
            endedAtUptimeNanoseconds: starts[1] + minimum,
            candidates: [candidate(neighbor), candidate(scooter)]
        )
        _ = try ledger.completeWindow(
            phase: .secondPoweredOff,
            startedAtUptimeNanoseconds: starts[2],
            endedAtUptimeNanoseconds: starts[2] + minimum,
            candidates: [candidate(neighbor)]
        )
        return try #require(ledger.completeWindow(
            phase: .secondPoweredOn,
            startedAtUptimeNanoseconds: starts[3],
            endedAtUptimeNanoseconds: starts[3] + minimum,
            candidates: [candidate(neighbor), candidate(scooter)]
        ))
    }

    private func candidate(
        _ id: UUID
    ) -> PassiveBluetoothCandidateObservationSnapshot.Candidate {
        .init(id: id, isConnectable: true)
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
        try session.append(
            .characteristic(try PassiveBluetoothCharacteristicObservation(
                peripheralIdentifier: scooter.uuidString,
                serviceUUID: "FFE0",
                characteristicUUID: "FFE1",
                properties: [.notify]
            )),
            sequenceNumber: 2,
            receivedAtUptimeNanoseconds: 2,
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
            receivedAtUptimeNanoseconds: 3,
            receivedAtDate: startedAt.addingTimeInterval(2)
        )
        return try PassiveBluetoothCaptureJSON.encode(session)
    }
}
