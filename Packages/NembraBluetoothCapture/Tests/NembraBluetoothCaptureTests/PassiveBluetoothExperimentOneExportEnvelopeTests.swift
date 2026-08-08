import Foundation
import Testing
@testable import NembraBluetoothCapture

struct PassiveBluetoothExperimentOneExportEnvelopeTests {
    private let target = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let other = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    @Test
    func roundTripBindsCaptureManifestAndReplayableCorrelationEvidence() throws {
        let captureJSON = try makeCapture(target: target)
        let result = try makePowerCycleResult(target: target)
        let manifest = try makeManifest(captureJSON: captureJSON, selected: target)
        let envelope = try PassiveBluetoothExperimentOneExportEnvelopeBuilder.makeValidated(
            captureJSON: captureJSON,
            manifest: manifest,
            powerCycleResult: result
        )

        let encoded = try PassiveBluetoothExperimentOneExportEnvelopeJSON.encode(envelope)
        let decoded = try PassiveBluetoothExperimentOneExportEnvelopeJSON.decodeAndVerify(encoded)

        #expect(decoded == envelope)
        #expect(decoded.manifest.sourceArtifact.selectedPeripheralIdentifier == target.uuidString)
        #expect(decoded.powerCycleResult.correlation == result.correlation)
        #expect(decoded.powerCycleResult.observationSnapshots == result.observationSnapshots)
    }

    @Test
    func rejectsManifestTargetThatWasNotEarnedByCorrelation() throws {
        let captureJSON = try makeCapture(target: other)
        let result = try makePowerCycleResult(target: target)
        let manifest = try makeManifest(captureJSON: captureJSON, selected: other)

        #expect(
            throws: PassiveBluetoothExperimentOneExportEnvelopeError.selectedPeripheralDoesNotMatchCorrelation(
                selected: other.uuidString,
                correlated: target.uuidString
            )
        ) {
            _ = try PassiveBluetoothExperimentOneExportEnvelopeBuilder.makeValidated(
                captureJSON: captureJSON,
                manifest: manifest,
                powerCycleResult: result
            )
        }
    }

    @Test
    func rejectsTamperedCaptureBytesThroughManifestBinding() throws {
        let captureJSON = try makeCapture(target: target)
        let result = try makePowerCycleResult(target: target)
        let manifest = try makeManifest(captureJSON: captureJSON, selected: target)
        let envelope = try PassiveBluetoothExperimentOneExportEnvelopeBuilder.makeValidated(
            captureJSON: captureJSON,
            manifest: manifest,
            powerCycleResult: result
        )
        let encoded = try PassiveBluetoothExperimentOneExportEnvelopeJSON.encode(envelope)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["captureJSON"] = Data("tampered".utf8).base64EncodedString()
        let tampered = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])

        #expect(throws: Error.self) {
            _ = try PassiveBluetoothExperimentOneExportEnvelopeJSON.decodeAndVerify(tampered)
        }
    }

    @Test
    func rejectsUnknownTopLevelFieldsInsteadOfSilentlyExpandingAuthority() throws {
        let captureJSON = try makeCapture(target: target)
        let result = try makePowerCycleResult(target: target)
        let manifest = try makeManifest(captureJSON: captureJSON, selected: target)
        let envelope = try PassiveBluetoothExperimentOneExportEnvelopeBuilder.makeValidated(
            captureJSON: captureJSON,
            manifest: manifest,
            powerCycleResult: result
        )
        let encoded = try PassiveBluetoothExperimentOneExportEnvelopeJSON.encode(envelope)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["fieldAuthorized"] = true
        let smuggled = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])

        #expect(
            throws: PassiveBluetoothExperimentOneExportEnvelopeError.unexpectedEnvelopeField("fieldAuthorized")
        ) {
            _ = try PassiveBluetoothExperimentOneExportEnvelopeJSON.decodeAndVerify(smuggled)
        }
    }

    private func makePowerCycleResult(target: UUID) throws -> PassiveBluetoothPowerCycleObservationResult {
        let series = PassiveBluetoothCandidateObservationSeriesIdentity(
            rawValue: UUID(uuidString: "12345678-1234-5678-9ABC-DEF012345678")!
        )
        let catalogs: [[PassiveBluetoothCandidateObservationSnapshot.Candidate]] = [
            [],
            [.init(id: target, isConnectable: true)],
            [],
            [.init(id: target, isConnectable: true)],
        ]
        let snapshots = try catalogs.enumerated().map { index, candidates in
            try PassiveBluetoothCandidateObservationSnapshot(
                observationSeriesIdentity: series,
                windowSequence: .init(rawValue: UInt64(index + 1)),
                candidates: candidates
            )
        }
        let windows = snapshots.enumerated().map { index, snapshot in
            PassiveBluetoothPowerCycleObservationWindowReceipt(
                phase: PassiveBluetoothPowerCycleObservationPhase(rawValue: index)!,
                windowSequence: snapshot.windowSequence,
                startedAtUptimeNanoseconds: UInt64(index * 100 + 1),
                endedAtUptimeNanoseconds: UInt64(index * 100 + 51),
                observedCandidateCount: snapshot.candidates.count
            )
        }
        let correlation = PassiveBluetoothPowerCycleTargetCorrelation.assess(
            firstOff: snapshots[0],
            firstOn: snapshots[1],
            secondOff: snapshots[2],
            secondOn: snapshots[3]
        )
        return .init(windows: windows, observationSnapshots: snapshots, correlation: correlation)
    }

    private func makeManifest(
        captureJSON: Data,
        selected: UUID
    ) throws -> PassiveBluetoothStationaryCaptureManifest {
        try PassiveBluetoothStationaryCaptureManifestBuilder.make(
            captureJSON: captureJSON,
            experimentID: UUID(uuidString: "99999999-8888-7777-6666-555555555555")!,
            experimentRecipe: .es80FingerprintV1,
            preparedAt: Date(timeIntervalSince1970: 1_750_000_100),
            nembraBuildIdentifier: "Capture Build V14-abcdef012345",
            nembraBuildInstanceID: "A1B2C3D4-E5F6-47A8-90BC-DEF123456789",
            nembraBuildCommitSHA: "abcdef0123456789abcdef0123456789abcdef01",
            selectedPeripheralIdentifier: selected.uuidString,
            setup: .init(
                chargerState: .disconnected,
                executionContext: .foregroundUnlockedScreenOn,
                stockAppReferenceSetup: .none
            )
        )
    }

    private func makeCapture(target: UUID) throws -> Data {
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
