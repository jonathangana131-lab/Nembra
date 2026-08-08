import Foundation
import Testing
@testable import NembraBluetoothCapture

struct PassiveBluetoothExperimentOneExportEnvelopeTests {
    private let target = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let background = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let sessionID = UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!
    private let experimentID = UUID(uuidString: "99999999-8888-7777-6666-555555555555")!
    private let preparedAt = Date(timeIntervalSince1970: 1_750_000_100)

    @Test
    func envelopeBindsExactSealCorrelationManifestAndRuntimeBuildWithoutSelfAuthorizing() throws {
        let captureJSON = try makeCapture()
        let correlationResult = try makeCorrelationResult()
        let runtime = try makeRuntimeIdentity()

        let envelope = try PassiveBluetoothExperimentOneExportEnvelopeBuilder.make(
            captureJSON: captureJSON,
            powerCycleResult: correlationResult,
            runtimeBuildIdentity: runtime,
            experimentID: experimentID,
            preparedAt: preparedAt,
            setup: defaultSetup()
        )
        let encoded = try PassiveBluetoothExperimentOneExportEnvelopeJSON.encode(envelope)
        let verified = try PassiveBluetoothExperimentOneExportEnvelopeJSON.decodeAndVerify(encoded)

        #expect(verified == envelope)
        #expect(verified.schemaVersion == 1)
        #expect(verified.recipeID == .es80FingerprintV1)
        #expect(verified.fieldAuthorization == .notContained)
        #expect(verified.sealedCaptureJSON == captureJSON)
        #expect(verified.runtimeBuild.buildIdentifier == runtime.buildIdentifier)
        #expect(verified.runtimeBuild.buildInstanceID == runtime.buildInstanceID)
        #expect(verified.runtimeBuild.sourceCommitSHA == runtime.sourceCommitSHA)
        #expect(verified.runtimeBuild.executableSHA256 == runtime.executableSHA256)
        #expect(verified.powerCycleEvidence.windows.count == 4)
        #expect(verified.powerCycleEvidence.observationSnapshots.count == 4)
        #expect(verified.powerCycleEvidence.correlation.disposition == .singleRepeatableCandidate)
        #expect(verified.powerCycleEvidence.correlation.dispositionCandidateIdentifiers == [target])

        let manifest = try PassiveBluetoothStationaryCaptureManifestJSON.verifyCaptureBinding(
            manifestJSON: verified.stationaryManifestJSON,
            captureJSON: captureJSON
        )
        #expect(manifest.experimentRecipeID == .es80FingerprintV1)
        #expect(manifest.sourceArtifact.selectedPeripheralIdentifier == target.uuidString)
        #expect(manifest.nembraBuildIdentifier == runtime.buildIdentifier)
        #expect(manifest.nembraBuildInstanceID == runtime.buildInstanceID)
        #expect(manifest.nembraBuildCommitSHA == runtime.sourceCommitSHA)
    }

    @Test
    func sealedCaptureTamperFailsManifestBinding() throws {
        let envelope = try makeEnvelope()
        let encoded = try PassiveBluetoothExperimentOneExportEnvelopeJSON.encode(envelope)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["sealedCaptureJSON"] = Data("forged".utf8).base64EncodedString()
        let forged = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])

        #expect(throws: Error.self) {
            _ = try PassiveBluetoothExperimentOneExportEnvelopeJSON.decodeAndVerify(forged)
        }
    }

    @Test
    func correlationProjectionTamperFailsReplay() throws {
        let envelope = try makeEnvelope()
        let encoded = try PassiveBluetoothExperimentOneExportEnvelopeJSON.encode(envelope)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var evidence = try #require(object["powerCycleEvidence"] as? [String: Any])
        var correlation = try #require(evidence["correlation"] as? [String: Any])
        correlation["repeatableCandidateIdentifiers"] = []
        evidence["correlation"] = correlation
        object["powerCycleEvidence"] = evidence
        let forged = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])

        #expect(
            throws: PassiveBluetoothExperimentOneExportEnvelopeError.envelopeDoesNotMatchCorrelation
        ) {
            _ = try PassiveBluetoothExperimentOneExportEnvelopeJSON.decodeAndVerify(forged)
        }
    }

    private func makeEnvelope() throws -> PassiveBluetoothExperimentOneExportEnvelope {
        try PassiveBluetoothExperimentOneExportEnvelopeBuilder.make(
            captureJSON: makeCapture(),
            powerCycleResult: makeCorrelationResult(),
            runtimeBuildIdentity: makeRuntimeIdentity(),
            experimentID: experimentID,
            preparedAt: preparedAt,
            setup: defaultSetup()
        )
    }

    private func makeRuntimeIdentity() throws -> PassiveBluetoothCaptureRuntimeBuildIdentity {
        try PassiveBluetoothCaptureRuntimeBuildIdentityReader.resolveEmbeddedMetadata(
            infoDictionary: [
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildIdentifierInfoDictionaryKey:
                    "Capture Build V14-abcdef012345",
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildInstanceIDInfoDictionaryKey:
                    "A1B2C3D4-E5F6-47A8-90BC-DEF123456789",
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.sourceCommitSHAInfoDictionaryKey:
                    "abcdef0123456789abcdef0123456789abcdef01",
            ],
            executableData: Data("exact-test-executable".utf8)
        )
    }

    private func makeCorrelationResult() throws -> PassiveBluetoothPowerCycleObservationResult {
        let series = PassiveBluetoothCandidateObservationSeriesIdentity(
            rawValue: UUID(uuidString: "12345678-1234-4234-8234-123456789ABC")!
        )
        let snapshots = try [
            makeSnapshot(series: series, sequence: 1, candidates: [(background, true)]),
            makeSnapshot(series: series, sequence: 2, candidates: [(background, true), (target, true)]),
            makeSnapshot(series: series, sequence: 3, candidates: [(background, true)]),
            makeSnapshot(series: series, sequence: 4, candidates: [(background, true), (target, true)]),
        ]
        let correlation = PassiveBluetoothPowerCycleTargetCorrelation.assess(
            firstOff: snapshots[0],
            firstOn: snapshots[1],
            secondOff: snapshots[2],
            secondOn: snapshots[3]
        )
        let phases: [PassiveBluetoothPowerCycleObservationPhase] = [
            .firstPoweredOff, .firstPoweredOn, .secondPoweredOff, .secondPoweredOn,
        ]
        let windows = zip(phases, snapshots).enumerated().map { index, pair in
            PassiveBluetoothPowerCycleObservationWindowReceipt(
                phase: pair.0,
                windowSequence: pair.1.windowSequence,
                startedAtUptimeNanoseconds: UInt64(index * 100 + 1),
                endedAtUptimeNanoseconds: UInt64(index * 100 + 81),
                observedCandidateCount: pair.1.candidates.count
            )
        }
        return PassiveBluetoothPowerCycleObservationResult(
            windows: windows,
            observationSnapshots: snapshots,
            correlation: correlation
        )
    }

    private func makeSnapshot(
        series: PassiveBluetoothCandidateObservationSeriesIdentity,
        sequence: UInt64,
        candidates: [(UUID, Bool?)]
    ) throws -> PassiveBluetoothCandidateObservationSnapshot {
        try PassiveBluetoothCandidateObservationSnapshot(
            observationSeriesIdentity: series,
            windowSequence: .init(rawValue: sequence),
            candidates: candidates.map {
                .init(id: $0.0, isConnectable: $0.1)
            }
        )
    }

    private func defaultSetup() -> PassiveBluetoothStationaryCaptureSetup {
        .init(
            chargerState: .disconnected,
            executionContext: .foregroundUnlockedScreenOn,
            stockAppReferenceSetup: .none
        )
    }

    private func makeCapture() throws -> Data {
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
