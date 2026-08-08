import Foundation
import Testing
@testable import NembraBluetoothCapture

struct PassiveBluetoothExperimentOneFieldArtifactTests {
    private let target = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let alternateTarget = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let captureSessionID = UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!
    private let buildIdentifier = "Capture Build V14-field-envelope"
    private let buildInstanceID = "A1B2C3D4-E5F6-47A8-90BC-DEF123456789"
    private let commit = "abcdef0123456789abcdef0123456789abcdef01"
    private let preparedAt = Date(timeIntervalSince1970: 1_750_000_100)

    @Test
    func finalEnvelopeBindsCaptureCorrelationManifestAndRuntimeBuild() throws {
        let captureJSON = try makeCapture(target: target)
        let powerCycleResult = try makePowerCycleResult(targets: [target])
        let runtimeIdentity = try makeRuntimeIdentity()

        let artifact = try PassiveBluetoothExperimentOneFieldArtifactBuilder.make(
            captureJSON: captureJSON,
            powerCycleResult: powerCycleResult,
            runtimeBuildIdentity: runtimeIdentity,
            setup: defaultSetup(),
            preparedAt: preparedAt
        )
        let encoded = try PassiveBluetoothExperimentOneFieldArtifactJSON.encode(artifact)
        let verified = try PassiveBluetoothExperimentOneFieldArtifactJSON
            .verifyInternalConsistency(encoded)

        #expect(verified == artifact)
        #expect(verified.captureJSON == captureJSON)
        #expect(verified.powerCycleResult == powerCycleResult)
        #expect(verified.stationaryManifest.experimentRecipeID == .es80FingerprintV1)
        #expect(
            verified.stationaryManifest.experimentID
                == powerCycleResult.correlation.observationSeriesIdentities[0].rawValue
        )
        #expect(verified.stationaryManifest.sourceArtifact.selectedPeripheralIdentifier == target.uuidString)
        #expect(verified.stationaryManifest.nembraBuildIdentifier == runtimeIdentity.buildIdentifier)
        #expect(verified.stationaryManifest.nembraBuildInstanceID == runtimeIdentity.buildInstanceID)
        #expect(verified.stationaryManifest.nembraBuildCommitSHA == runtimeIdentity.sourceCommitSHA)
        #expect(verified.runtimeBuildProvenance.executableSHA256 == runtimeIdentity.executableSHA256)
    }

    @Test
    func verifierRejectsCorrelationTargetThatNoLongerMatchesBoundCaptureManifest() throws {
        let encoded = try makeEncodedArtifact()
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var powerCycle = try #require(object["powerCycle"] as? [String: Any])
        var snapshots = try #require(powerCycle["observationSnapshots"] as? [[String: Any]])

        for index in [1, 3] {
            var snapshot = snapshots[index]
            var candidates = try #require(snapshot["candidates"] as? [[String: Any]])
            var candidate = candidates[0]
            candidate["id"] = alternateTarget.uuidString
            candidates[0] = candidate
            snapshot["candidates"] = candidates
            snapshots[index] = snapshot
        }
        powerCycle["observationSnapshots"] = snapshots
        object["powerCycle"] = powerCycle
        let tampered = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])

        #expect(
            throws: PassiveBluetoothExperimentOneFieldArtifactError.manifestTargetMismatch(
                expected: alternateTarget.uuidString,
                actual: target.uuidString
            )
        ) {
            _ = try PassiveBluetoothExperimentOneFieldArtifactJSON.verifyInternalConsistency(tampered)
        }
    }

    @Test
    func verifierRejectsRuntimeBuildSubstitutionAndInvalidExecutableDigest() throws {
        let encoded = try makeEncodedArtifact()
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var runtime = try #require(object["runtimeBuild"] as? [String: Any])
        runtime["buildInstanceID"] = "12345678-1234-1234-1234-123456789abc"
        object["runtimeBuild"] = runtime
        let substituted = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])

        #expect(
            throws: PassiveBluetoothExperimentOneFieldArtifactError
                .runtimeBuildProvenanceMismatch("buildInstanceID")
        ) {
            _ = try PassiveBluetoothExperimentOneFieldArtifactJSON.verifyInternalConsistency(substituted)
        }

        object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        runtime = try #require(object["runtimeBuild"] as? [String: Any])
        let invalidDigest = String(repeating: "A", count: 64)
        runtime["executableSHA256"] = invalidDigest
        object["runtimeBuild"] = runtime
        let invalid = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])

        #expect(
            throws: PassiveBluetoothExperimentOneFieldArtifactError
                .invalidRuntimeExecutableSHA256(invalidDigest)
        ) {
            _ = try PassiveBluetoothExperimentOneFieldArtifactJSON.verifyInternalConsistency(invalid)
        }
    }

    @Test
    func closedWorldEnvelopeRejectsAuthorityLikeUnknownFields() throws {
        let encoded = try makeEncodedArtifact()
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["fieldAuthorized"] = true
        let tampered = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])

        #expect(
            throws: PassiveBluetoothExperimentOneFieldArtifactError
                .unexpectedField("fieldAuthorized")
        ) {
            _ = try PassiveBluetoothExperimentOneFieldArtifactJSON.verifyInternalConsistency(tampered)
        }
    }

    @Test
    func producerRefusesAmbiguousPhysicalCorrelation() throws {
        let captureJSON = try makeCapture(target: target)
        let ambiguous = try makePowerCycleResult(targets: [target, alternateTarget])
        let runtimeIdentity = try makeRuntimeIdentity()

        #expect(throws: PassiveBluetoothExperimentOneFieldArtifactError.correlationNotUnique) {
            _ = try PassiveBluetoothExperimentOneFieldArtifactBuilder.make(
                captureJSON: captureJSON,
                powerCycleResult: ambiguous,
                runtimeBuildIdentity: runtimeIdentity,
                setup: defaultSetup(),
                preparedAt: preparedAt
            )
        }
    }

    private func makeEncodedArtifact() throws -> Data {
        let artifact = try PassiveBluetoothExperimentOneFieldArtifactBuilder.make(
            captureJSON: try makeCapture(target: target),
            powerCycleResult: try makePowerCycleResult(targets: [target]),
            runtimeBuildIdentity: try makeRuntimeIdentity(),
            setup: defaultSetup(),
            preparedAt: preparedAt
        )
        return try PassiveBluetoothExperimentOneFieldArtifactJSON.encode(artifact)
    }

    private func makeRuntimeIdentity() throws -> PassiveBluetoothCaptureRuntimeBuildIdentity {
        try PassiveBluetoothCaptureRuntimeBuildIdentityReader.resolveEmbeddedMetadata(
            infoDictionary: [
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildIdentifierInfoDictionaryKey:
                    buildIdentifier,
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildInstanceIDInfoDictionaryKey:
                    buildInstanceID,
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.sourceCommitSHAInfoDictionaryKey:
                    commit,
            ],
            executableData: Data("signed-field-build-fixture".utf8)
        )
    }

    private func defaultSetup() -> PassiveBluetoothStationaryCaptureSetup {
        .init(
            chargerState: .disconnected,
            executionContext: .foregroundUnlockedScreenOn,
            stockAppReferenceSetup: .none
        )
    }

    private func makePowerCycleResult(
        targets: [UUID]
    ) throws -> PassiveBluetoothPowerCycleObservationResult {
        var ledger = PassiveBluetoothPowerCycleObservationLedger(
            minimumWindowDurationNanoseconds: 1
        )
        let onCandidates = targets.map {
            PassiveBluetoothCandidateObservationSnapshot.Candidate(
                id: $0,
                isConnectable: true
            )
        }

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
            candidates: onCandidates
        )
        _ = try ledger.completeWindow(
            phase: .secondPoweredOff,
            startedAtUptimeNanoseconds: 30,
            endedAtUptimeNanoseconds: 31,
            candidates: []
        )
        let completed = try ledger.completeWindow(
            phase: .secondPoweredOn,
            startedAtUptimeNanoseconds: 40,
            endedAtUptimeNanoseconds: 41,
            candidates: onCandidates
        )
        return try #require(completed)
    }

    private func makeCapture(target: UUID) throws -> Data {
        var session = try PassiveBluetoothCaptureSession(
            id: captureSessionID,
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
