import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive Bluetooth Experiment One export envelope")
struct PassiveBluetoothExperimentOneExportEnvelopeTests {
    private let target = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let other = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let sessionID = UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!
    private let startedAt = Date(timeIntervalSince1970: 1_750_000_000)
    private let preparedAt = Date(timeIntervalSince1970: 1_750_000_100)
    private let validCommit = "0123456789abcdef0123456789abcdef01234567"
    private let validBuildInstanceID = "12345678-90ab-cdef-1234-567890abcdef"

    @Test("round trip binds sealed bytes, repeated correlation, recipe, build identity, and explicit no-GO status")
    func roundTrip() throws {
        let captureJSON = try makeCaptureJSON()
        let result = try makePowerCycleResult()
        let identity = try makeRuntimeBuildIdentity()

        let envelopeJSON = try PassiveBluetoothExperimentOneExportEnvelopeBuilder.make(
            captureJSON: captureJSON,
            powerCycleResult: result,
            runtimeBuildIdentity: identity,
            preparedAt: preparedAt,
            setup: setup()
        )
        let decoded = try PassiveBluetoothExperimentOneExportEnvelopeJSON.verifyAndDecode(
            envelopeJSON
        )

        #expect(decoded.schemaVersion == 1)
        #expect(decoded.experimentRecipeID == .es80FingerprintV1)
        #expect(decoded.fieldAuthorizationStatus == .notAttached)
        #expect(decoded.captureJSON == captureJSON)
        #expect(decoded.selectedPeripheralIdentifier == target)
        #expect(decoded.observationWindowCount == 4)
        #expect(decoded.runtimeBuild.buildIdentifier == identity.buildIdentifier)
        #expect(decoded.runtimeBuild.buildInstanceID == identity.buildInstanceID)
        #expect(decoded.runtimeBuild.sourceCommitSHA == identity.sourceCommitSHA)
        #expect(decoded.runtimeBuild.executableSHA256 == identity.executableSHA256)

        let manifest = try PassiveBluetoothStationaryCaptureManifestJSON.verifyCaptureBinding(
            manifestJSON: decoded.stationaryManifestJSON,
            captureJSON: decoded.captureJSON
        )
        #expect(manifest.experimentRecipeID == .es80FingerprintV1)
        #expect(manifest.nembraBuildInstanceID == identity.buildInstanceID)
        #expect(manifest.sourceArtifact.selectedPeripheralIdentifier == target.uuidString)
    }

    @Test("correlation selection cannot be relabeled after sealing")
    func selectedTargetTamperFailsClosed() throws {
        let envelopeJSON = try makeEnvelopeJSON()
        var object = try #require(JSONSerialization.jsonObject(with: envelopeJSON) as? [String: Any])
        var correlation = try #require(object["correlation"] as? [String: Any])
        correlation["selectedPeripheralIdentifier"] = other.uuidString
        object["correlation"] = correlation
        let tampered = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])

        #expect(throws: PassiveBluetoothExperimentOneExportEnvelopeError.correlationNotUnique) {
            _ = try PassiveBluetoothExperimentOneExportEnvelopeJSON.verifyAndDecode(tampered)
        }
    }

    @Test("exact sealed capture bytes remain bound to the embedded stationary manifest")
    func captureByteTamperFailsClosed() throws {
        let envelopeJSON = try makeEnvelopeJSON()
        var object = try #require(JSONSerialization.jsonObject(with: envelopeJSON) as? [String: Any])
        var changedCapture = try #require(Data(base64Encoded: try #require(object["captureJSON"] as? String)))
        changedCapture.append(0x0A)
        object["captureJSON"] = changedCapture.base64EncodedString()
        let tampered = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])

        #expect(throws: PassiveBluetoothStationaryCaptureManifestError.manifestDoesNotMatchCapture) {
            _ = try PassiveBluetoothExperimentOneExportEnvelopeJSON.verifyAndDecode(tampered)
        }
    }

    @Test("unknown authority-looking fields are rejected instead of ignored")
    func unknownAuthorityFieldFailsClosed() throws {
        let envelopeJSON = try makeEnvelopeJSON()
        var object = try #require(JSONSerialization.jsonObject(with: envelopeJSON) as? [String: Any])
        object["physicalFieldGO"] = true
        let tampered = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])

        #expect(
            throws: PassiveBluetoothExperimentOneExportEnvelopeError
                .unexpectedEnvelopeField("physicalFieldGO")
        ) {
            _ = try PassiveBluetoothExperimentOneExportEnvelopeJSON.verifyAndDecode(tampered)
        }
    }

    @Test("builder refuses correlation evidence without one repeatable candidate")
    func nonUniqueCorrelationCannotBeExported() throws {
        let captureJSON = try makeCaptureJSON()
        let result = try makePowerCycleResult(includeTargetInSecondOn: false)

        #expect(throws: PassiveBluetoothExperimentOneExportEnvelopeError.correlationNotUnique) {
            _ = try PassiveBluetoothExperimentOneExportEnvelopeBuilder.make(
                captureJSON: captureJSON,
                powerCycleResult: result,
                runtimeBuildIdentity: makeRuntimeBuildIdentity(),
                preparedAt: preparedAt,
                setup: setup()
            )
        }
    }

    private func makeEnvelopeJSON() throws -> Data {
        try PassiveBluetoothExperimentOneExportEnvelopeBuilder.make(
            captureJSON: makeCaptureJSON(),
            powerCycleResult: makePowerCycleResult(),
            runtimeBuildIdentity: makeRuntimeBuildIdentity(),
            preparedAt: preparedAt,
            setup: setup()
        )
    }

    private func makeRuntimeBuildIdentity() throws -> PassiveBluetoothCaptureRuntimeBuildIdentity {
        try PassiveBluetoothCaptureRuntimeBuildIdentityReader.resolveEmbeddedMetadata(
            infoDictionary: [
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildIdentifierInfoDictionaryKey:
                    "Capture Build V14-F1",
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildInstanceIDInfoDictionaryKey:
                    validBuildInstanceID,
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.sourceCommitSHAInfoDictionaryKey:
                    validCommit,
            ],
            executableData: Data("fixture executable".utf8)
        )
    }

    private func makePowerCycleResult(
        includeTargetInSecondOn: Bool = true
    ) throws -> PassiveBluetoothPowerCycleObservationResult {
        var ledger = PassiveBluetoothPowerCycleObservationLedger(
            minimumWindowDurationNanoseconds: 1
        )
        let targetCandidate = PassiveBluetoothCandidateObservationSnapshot.Candidate(
            id: target,
            isConnectable: true
        )
        let unrelatedCandidate = PassiveBluetoothCandidateObservationSnapshot.Candidate(
            id: other,
            isConnectable: true
        )

        #expect(try ledger.completeWindow(
            phase: .firstPoweredOff,
            startedAtUptimeNanoseconds: 10,
            endedAtUptimeNanoseconds: 11,
            candidates: [unrelatedCandidate]
        ) == nil)
        #expect(try ledger.completeWindow(
            phase: .firstPoweredOn,
            startedAtUptimeNanoseconds: 20,
            endedAtUptimeNanoseconds: 21,
            candidates: [unrelatedCandidate, targetCandidate]
        ) == nil)
        #expect(try ledger.completeWindow(
            phase: .secondPoweredOff,
            startedAtUptimeNanoseconds: 30,
            endedAtUptimeNanoseconds: 31,
            candidates: [unrelatedCandidate]
        ) == nil)

        return try #require(ledger.completeWindow(
            phase: .secondPoweredOn,
            startedAtUptimeNanoseconds: 40,
            endedAtUptimeNanoseconds: 41,
            candidates: includeTargetInSecondOn
                ? [unrelatedCandidate, targetCandidate]
                : [unrelatedCandidate]
        ))
    }

    private func makeCaptureJSON() throws -> Data {
        var session = try PassiveBluetoothCaptureSession(
            id: sessionID,
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
            peripheralIdentifier: target.uuidString,
            serviceUUID: "FFE0",
            isPrimary: true
        )))
        try append(.characteristic(try PassiveBluetoothCharacteristicObservation(
            peripheralIdentifier: target.uuidString,
            serviceUUID: "FFE0",
            characteristicUUID: "FFE1",
            properties: [.notify]
        )))
        try append(.value(try PassiveBluetoothValueObservation(
            peripheralIdentifier: target.uuidString,
            serviceUUID: "FFE0",
            characteristicUUID: "FFE1",
            origin: .subscriptionUpdate,
            payload: Data([0x01, 0x02])
        )))

        return try PassiveBluetoothCaptureJSON.encode(session)
    }

    private func setup() -> PassiveBluetoothStationaryCaptureSetup {
        .init(
            chargerState: .disconnected,
            executionContext: .foregroundUnlockedScreenOn,
            stockAppReferenceSetup: .none
        )
    }
}
