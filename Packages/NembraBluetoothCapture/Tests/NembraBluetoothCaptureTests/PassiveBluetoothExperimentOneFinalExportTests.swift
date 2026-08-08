import Foundation
import Testing
@testable import NembraBluetoothCapture

struct PassiveBluetoothExperimentOneFinalExportTests {
    private let target = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let other = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let experimentID = UUID(uuidString: "99999999-8888-7777-6666-555555555555")!
    private let preparedAt = Date(timeIntervalSince1970: 1_750_000_100)
    private let buildIdentifier = "Capture Build V14-abcdef012345"
    private let buildInstanceID = "A1B2C3D4-E5F6-47A8-90BC-DEF123456789"
    private let commit = "abcdef0123456789abcdef0123456789abcdef01"

    @Test
    func packageBoundaryDerivesTargetRecipeAndProducedBuildProvenance() throws {
        let captureJSON = try makeCapture(target: target)
        let result = try makePowerCycleResult(onCandidates: [target])
        let setup = defaultSetup()
        let buildIdentity = try makeBuildIdentity()

        let envelope = try PassiveBluetoothExperimentOneFinalExport.makeValidatedEnvelope(
            captureJSON: captureJSON,
            powerCycleResult: result,
            setup: setup,
            buildIdentity: buildIdentity,
            experimentID: experimentID,
            preparedAt: preparedAt
        )

        #expect(envelope.captureJSON == captureJSON)
        #expect(envelope.powerCycleResult == result)
        #expect(envelope.manifest.schemaVersion == PassiveBluetoothStationaryCaptureManifest.currentSchemaVersion)
        #expect(envelope.manifest.experimentID == experimentID)
        #expect(envelope.manifest.experimentRecipeID == .es80FingerprintV1)
        #expect(envelope.manifest.preparedAt == preparedAt)
        #expect(envelope.manifest.nembraBuildIdentifier == buildIdentifier)
        #expect(envelope.manifest.nembraBuildInstanceID == buildInstanceID.lowercased())
        #expect(envelope.manifest.nembraBuildCommitSHA == commit)
        #expect(envelope.manifest.setup == setup)
        #expect(envelope.manifest.sourceArtifact.selectedPeripheralIdentifier == target.uuidString)

        let encoded = try PassiveBluetoothExperimentOneExportEnvelopeJSON.encode(envelope)
        let verified = try PassiveBluetoothExperimentOneExportEnvelopeJSON.decodeAndVerify(encoded)
        #expect(verified == envelope)
    }

    @Test
    func packageBoundaryRejectsNonUniqueCorrelationInsteadOfAcceptingCallerTargetMetadata() throws {
        let captureJSON = try makeCapture(target: target)
        let ambiguousResult = try makePowerCycleResult(onCandidates: [target, other])

        #expect(throws: PassiveBluetoothExperimentOneExportEnvelopeError.correlationNotUnique) {
            _ = try PassiveBluetoothExperimentOneFinalExport.makeValidatedEnvelope(
                captureJSON: captureJSON,
                powerCycleResult: ambiguousResult,
                setup: defaultSetup(),
                buildIdentity: makeBuildIdentity(),
                experimentID: experimentID,
                preparedAt: preparedAt
            )
        }
    }

    private func makeBuildIdentity() throws -> PassiveBluetoothCaptureRuntimeBuildIdentity {
        try PassiveBluetoothCaptureRuntimeBuildIdentityReader.resolveEmbeddedMetadata(
            infoDictionary: [
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildIdentifierInfoDictionaryKey: buildIdentifier,
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildInstanceIDInfoDictionaryKey: buildInstanceID,
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.sourceCommitSHAInfoDictionaryKey: commit,
            ],
            executableData: Data("final-export-test-executable".utf8)
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
        onCandidates: [UUID]
    ) throws -> PassiveBluetoothPowerCycleObservationResult {
        let series = PassiveBluetoothCandidateObservationSeriesIdentity(
            rawValue: UUID(uuidString: "12345678-1234-5678-9ABC-DEF012345678")!
        )
        let poweredOn = onCandidates.map {
            PassiveBluetoothCandidateObservationSnapshot.Candidate(id: $0, isConnectable: true)
        }
        let catalogs: [[PassiveBluetoothCandidateObservationSnapshot.Candidate]] = [
            [], poweredOn, [], poweredOn,
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
        return .init(
            windows: windows,
            observationSnapshots: snapshots,
            correlation: correlation
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
