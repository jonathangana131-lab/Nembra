import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Experiment One software evidence export")
struct PassiveBluetoothExperimentOneSoftwareExportTests {
    private typealias Codec = PassiveBluetoothExperimentOneSoftwareExportCodec
    private typealias ExportError = PassiveBluetoothExperimentOneSoftwareExportError
    private typealias RuntimeReader = PassiveBluetoothCaptureRuntimeBuildIdentityReader

    private let scooter = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let stableNeighbor = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    private let buildInstanceID = "12345678-90ab-cdef-1234-567890abcdef"
    private let commitSHA = "0123456789abcdef0123456789abcdef01234567"

    @Test("round trip preserves exact bytes, recipe, build, and original correlation authority")
    func roundTripPreservesOriginalAuthority() throws {
        let result = try makePowerCycleResult()
        let captureJSON = try makeCaptureJSON()
        let identity = try makeBuildIdentity()

        let export = try Codec.makeValidatedInputs(
            captureJSON: captureJSON,
            powerCycleResult: result,
            runtimeBuildIdentity: identity
        )
        let encoded = try Codec.encode(export)
        let decoded = try Codec.decodeAndVerify(encoded)

        #expect(decoded == export)
        #expect(decoded.captureJSON == captureJSON)
        #expect(decoded.experimentRecipeID == .es80FingerprintV1)
        #expect(decoded.build.buildInstanceID == buildInstanceID)
        #expect(decoded.build.sourceCommitSHA == commitSHA)
        #expect(decoded.correlationWindows.map(\.observationSeriesIdentity) ==
            result.observationSnapshots.map { $0.observationSeriesIdentity.rawValue })
        #expect(decoded.correlationWindows.map(\.windowSequence) == [1, 2, 3, 4])
    }

    @Test("one substituted authority identity invalidates the imported four-window correlation")
    func substitutedObservationAuthorityFailsClosed() throws {
        let data = try makeEncodedExport()
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var windows = try #require(object["correlationWindows"] as? [[String: Any]])
        windows[2]["observationSeriesIdentity"] = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        object["correlationWindows"] = windows
        let tampered = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])

        #expect(throws: ExportError.correlationEvidenceInvalid) {
            _ = try Codec.decodeAndVerify(tampered)
        }
    }

    @Test("nested unknown fields cannot smuggle ignored physical claims")
    func nestedUnknownFieldFailsClosed() throws {
        let data = try makeEncodedExport()
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var windows = try #require(object["correlationWindows"] as? [[String: Any]])
        var candidates = try #require(windows[1]["candidates"] as? [[String: Any]])
        candidates[0]["physicallyVerified"] = true
        windows[1]["candidates"] = candidates
        object["correlationWindows"] = windows
        let tampered = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])

        #expect(throws: ExportError.unexpectedWireField("correlationWindows[1].candidates[0].physicallyVerified")) {
            _ = try Codec.decodeAndVerify(tampered)
        }
    }

    @Test("changing sealed capture bytes without the manifest fails exact binding verification")
    func changedCaptureBytesFailManifestBinding() throws {
        let data = try makeEncodedExport()
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let original = try #require(Data(base64Encoded: try #require(object["captureJSONBase64"] as? String)))
        var changed = original
        changed.append(0x0A)
        object["captureJSONBase64"] = changed.base64EncodedString()
        let tampered = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])

        #expect(throws: PassiveBluetoothStationaryCaptureManifestError.manifestDoesNotMatchCapture) {
            _ = try Codec.decodeAndVerify(tampered)
        }
    }

    private func makeEncodedExport() throws -> Data {
        let export = try Codec.makeValidatedInputs(
            captureJSON: makeCaptureJSON(),
            powerCycleResult: makePowerCycleResult(),
            runtimeBuildIdentity: makeBuildIdentity()
        )
        return try Codec.encode(export)
    }

    private func makeBuildIdentity() throws -> PassiveBluetoothCaptureRuntimeBuildIdentity {
        try RuntimeReader.resolveEmbeddedMetadata(
            infoDictionary: [
                RuntimeReader.buildIdentifierInfoDictionaryKey: "Capture Build V14-F1",
                RuntimeReader.buildInstanceIDInfoDictionaryKey: buildInstanceID,
                RuntimeReader.sourceCommitSHAInfoDictionaryKey: commitSHA
            ],
            executableData: Data("exact fixture executable".utf8)
        )
    }

    private func makePowerCycleResult() throws -> PassiveBluetoothPowerCycleObservationResult {
        var ledger = PassiveBluetoothPowerCycleObservationLedger(minimumWindowDurationNanoseconds: 1)
        _ = try ledger.completeWindow(
            phase: .firstPoweredOff,
            startedAtUptimeNanoseconds: 10,
            endedAtUptimeNanoseconds: 11,
            candidates: [candidate(stableNeighbor)]
        )
        _ = try ledger.completeWindow(
            phase: .firstPoweredOn,
            startedAtUptimeNanoseconds: 20,
            endedAtUptimeNanoseconds: 21,
            candidates: [candidate(stableNeighbor), candidate(scooter)]
        )
        _ = try ledger.completeWindow(
            phase: .secondPoweredOff,
            startedAtUptimeNanoseconds: 30,
            endedAtUptimeNanoseconds: 31,
            candidates: [candidate(stableNeighbor)]
        )
        return try #require(ledger.completeWindow(
            phase: .secondPoweredOn,
            startedAtUptimeNanoseconds: 40,
            endedAtUptimeNanoseconds: 41,
            candidates: [candidate(stableNeighbor), candidate(scooter)]
        ))
    }

    private func candidate(
        _ id: UUID,
        connectable: Bool? = true
    ) -> PassiveBluetoothCandidateObservationSnapshot.Candidate {
        .init(id: id, isConnectable: connectable)
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
        var sequence: UInt64 = 1

        func append(_ event: PassiveBluetoothCaptureEvent) throws {
            try session.append(
                event,
                sequenceNumber: sequence,
                receivedAtUptimeNanoseconds: sequence,
                receivedAtDate: startedAt.addingTimeInterval(Double(sequence))
            )
            sequence += 1
        }

        try append(.service(try PassiveBluetoothServiceObservation(
            peripheralIdentifier: scooter.uuidString,
            serviceUUID: "FFE0",
            isPrimary: true
        )))
        try append(.characteristic(try PassiveBluetoothCharacteristicObservation(
            peripheralIdentifier: scooter.uuidString,
            serviceUUID: "FFE0",
            characteristicUUID: "FFE1",
            properties: [.notify]
        )))
        try append(.value(try PassiveBluetoothValueObservation(
            peripheralIdentifier: scooter.uuidString,
            serviceUUID: "FFE0",
            characteristicUUID: "FFE1",
            origin: .subscriptionUpdate,
            payload: Data([0x01, 0x02])
        )))

        return try PassiveBluetoothCaptureJSON.encode(session)
    }
}
