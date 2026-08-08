import Foundation
import Testing
@testable import NembraBluetoothCapture

struct PassiveBluetoothExperimentOneExportEnvelopeTests {
    private let target = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let foreignTarget = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let seriesID = UUID(uuidString: "99999999-8888-7777-6666-555555555555")!
    private let captureSessionID = UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!
    private let commit = "abcdef0123456789abcdef0123456789abcdef01"
    private let buildIdentifier = "Capture Build V14-export"
    private let buildInstanceID = "A1B2C3D4-E5F6-47A8-90BC-DEF123456789"

    @Test
    func primaryEnvelopePreservesExactCaptureAndReplaysSameRunCorrelation() throws {
        let capture = try makeCapture(target: target)
        let correlation = try makeCorrelation(target: target)
        let identity = try makeBuildIdentity()

        let envelope = try PassiveBluetoothExperimentOneExportEnvelopeJSON.make(
            captureJSON: capture,
            powerCycleResult: correlation,
            setup: defaultSetup(),
            buildIdentity: identity,
            preparedAt: Date(timeIntervalSince1970: 1_750_000_100)
        )
        let verified = try PassiveBluetoothExperimentOneExportEnvelopeJSON.verifyAndDecode(envelope)

        #expect(verified.captureJSON == capture)
        #expect(verified.powerCycleResult == correlation)
        #expect(verified.recipeID == .es80FingerprintV1)
        #expect(verified.stationaryManifest.schemaVersion == 3)
        #expect(verified.stationaryManifest.experimentID == seriesID)
        #expect(verified.stationaryManifest.sourceArtifact.selectedPeripheralIdentifier == target.uuidString)
        #expect(verified.buildIdentifier == buildIdentifier)
        #expect(verified.buildInstanceID == buildInstanceID.lowercased())
        #expect(verified.sourceCommitSHA == commit)
        #expect(verified.executableSHA256 == identity.executableSHA256)
    }

    @Test
    func envelopeFailsClosedWhenExactCaptureBytesAreReplaced() throws {
        let envelope = try makeEnvelope()
        var object = try #require(JSONSerialization.jsonObject(with: envelope) as? [String: Any])
        object["captureJSON"] = Data("{}".utf8).base64EncodedString()
        let tampered = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])

        #expect(throws: (any Error).self) {
            _ = try PassiveBluetoothExperimentOneExportEnvelopeJSON.verifyAndDecode(tampered)
        }
    }

    @Test
    func envelopeRejectsRuntimeBuildFieldsThatNoLongerMatchBoundManifest() throws {
        let envelope = try makeEnvelope()
        var object = try #require(JSONSerialization.jsonObject(with: envelope) as? [String: Any])
        var runtime = try #require(object["runtimeBuild"] as? [String: Any])
        runtime["sourceCommitSHA"] = "1234567890abcdef1234567890abcdef12345678"
        object["runtimeBuild"] = runtime
        let tampered = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])

        #expect(
            throws: PassiveBluetoothExperimentOneExportEnvelopeError.manifestProvenanceMismatch
        ) {
            _ = try PassiveBluetoothExperimentOneExportEnvelopeJSON.verifyAndDecode(tampered)
        }
    }

    @Test
    func envelopeRejectsReplayedCorrelationThatPointsAtDifferentTarget() throws {
        let envelope = try makeEnvelope()
        var object = try #require(JSONSerialization.jsonObject(with: envelope) as? [String: Any])
        var correlation = try #require(object["correlationEvidence"] as? [String: Any])
        var snapshots = try #require(correlation["observationSnapshots"] as? [[String: Any]])

        for index in [1, 3] {
            var snapshot = snapshots[index]
            var candidates = try #require(snapshot["candidates"] as? [[String: Any]])
            var candidate = candidates[0]
            candidate["identifier"] = foreignTarget.uuidString
            candidates[0] = candidate
            snapshot["candidates"] = candidates
            snapshots[index] = snapshot
        }
        correlation["observationSnapshots"] = snapshots
        object["correlationEvidence"] = correlation
        let tampered = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])

        #expect(
            throws: PassiveBluetoothExperimentOneExportEnvelopeError.correlationDoesNotMatchManifest
        ) {
            _ = try PassiveBluetoothExperimentOneExportEnvelopeJSON.verifyAndDecode(tampered)
        }
    }

    @Test
    func envelopeRejectsUnknownAuthorityLikeFields() throws {
        let envelope = try makeEnvelope()
        var object = try #require(JSONSerialization.jsonObject(with: envelope) as? [String: Any])
        object["fieldAuthorized"] = true
        let smuggled = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])

        #expect(
            throws: PassiveBluetoothExperimentOneExportEnvelopeError
                .unexpectedField("fieldAuthorized")
        ) {
            _ = try PassiveBluetoothExperimentOneExportEnvelopeJSON.verifyAndDecode(smuggled)
        }
    }

    private func makeEnvelope() throws -> Data {
        try PassiveBluetoothExperimentOneExportEnvelopeJSON.make(
            captureJSON: makeCapture(target: target),
            powerCycleResult: makeCorrelation(target: target),
            setup: defaultSetup(),
            buildIdentity: makeBuildIdentity(),
            preparedAt: Date(timeIntervalSince1970: 1_750_000_100)
        )
    }

    private func makeBuildIdentity() throws -> PassiveBluetoothCaptureRuntimeBuildIdentity {
        try PassiveBluetoothCaptureRuntimeBuildIdentityReader.resolveEmbeddedMetadata(
            infoDictionary: [
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildIdentifierInfoDictionaryKey: buildIdentifier,
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildInstanceIDInfoDictionaryKey: buildInstanceID,
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.sourceCommitSHAInfoDictionaryKey: commit,
            ],
            executableData: Data("nembra-export-test-executable".utf8)
        )
    }

    private func defaultSetup() -> PassiveBluetoothStationaryCaptureSetup {
        .init(
            chargerState: .disconnected,
            executionContext: .foregroundUnlockedScreenOn,
            stockAppReferenceSetup: .none
        )
    }

    private func makeCorrelation(
        target: UUID
    ) throws -> PassiveBluetoothPowerCycleObservationResult {
        let authority = PassiveBluetoothCandidateObservationSeriesIdentity(rawValue: seriesID)
        let phases = PassiveBluetoothPowerCycleObservationPhase.allCases
        let snapshots = try phases.enumerated().map { index, phase in
            let sequence = PassiveBluetoothCandidateObservationWindowSequence(
                rawValue: UInt64(index + 1)
            )
            let candidates: [PassiveBluetoothCandidateObservationSnapshot.Candidate]
            if phase.operatorExpectedPowerOn {
                candidates = [.init(id: target, isConnectable: true)]
            } else {
                candidates = []
            }
            return try PassiveBluetoothCandidateObservationSnapshot(
                observationSeriesIdentity: authority,
                windowSequence: sequence,
                candidates: candidates
            )
        }
        let windows = phases.enumerated().map { index, phase in
            PassiveBluetoothPowerCycleObservationWindowReceipt(
                phase: phase,
                windowSequence: snapshots[index].windowSequence,
                startedAtUptimeNanoseconds: UInt64((index + 1) * 100),
                endedAtUptimeNanoseconds: UInt64((index + 1) * 100 + 10),
                observedCandidateCount: snapshots[index].candidates.count
            )
        }
        let report = PassiveBluetoothPowerCycleTargetCorrelation.assess(
            firstOff: snapshots[0],
            firstOn: snapshots[1],
            secondOff: snapshots[2],
            secondOn: snapshots[3]
        )
        return PassiveBluetoothPowerCycleObservationResult(
            windows: windows,
            observationSnapshots: snapshots,
            correlation: report
        )
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
