import Foundation
import Testing
@testable import NembraBluetoothCapture

struct PassiveBluetoothExperimentOneExportEnvelopeTests {
    private let target = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let background = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let sessionID = UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!
    private let experimentID = UUID(uuidString: "99999999-8888-7777-6666-555555555555")!
    private let preparedAt = Date(timeIntervalSince1970: 1_750_000_100)
    private let commit = "abcdef0123456789abcdef0123456789abcdef01"
    private let buildIdentifier = "Capture Build V14-abcdef012345"
    private let buildInstanceID = "a1b2c3d4-e5f6-47a8-90bc-def123456789"
    private let executableSHA256 = String(repeating: "e", count: 64)

    @Test
    func verifiedEnvelopeReplaysExactCaptureManifestBuildAndFourWindowEvidence() throws {
        let captureJSON = try makeCapture()
        let result = try makePowerCycleResult()
        let envelopeJSON = try makeEnvelope(captureJSON: captureJSON, result: result)

        let verified = try PassiveBluetoothExperimentOneExportEnvelopeJSON.verify(envelopeJSON)

        #expect(verified.captureJSON == captureJSON)
        #expect(verified.powerCycleResult == result)
        #expect(verified.recipeID == .es80FingerprintV1)
        #expect(verified.manifest.schemaVersion == 3)
        #expect(verified.manifest.experimentID == experimentID)
        #expect(verified.manifest.sourceArtifact.selectedPeripheralIdentifier == target.uuidString)
        #expect(verified.manifest.nembraBuildIdentifier == buildIdentifier)
        #expect(verified.manifest.nembraBuildInstanceID == buildInstanceID)
        #expect(verified.manifest.nembraBuildCommitSHA == commit)
        #expect(verified.buildEvidence.executableSHA256 == executableSHA256)
    }

    @Test
    func exactCaptureBytesCannotBeChangedBehindManifestAndHash() throws {
        let captureJSON = try makeCapture()
        let result = try makePowerCycleResult()
        let envelopeJSON = try makeEnvelope(captureJSON: captureJSON, result: result)
        var root = try rootObject(envelopeJSON)
        var tamperedCapture = captureJSON
        tamperedCapture.append(0x0A)
        root["captureJSON"] = tamperedCapture.base64EncodedString()

        let tampered = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        #expect(throws: PassiveBluetoothExperimentOneExportEnvelopeError.captureHashMismatch) {
            _ = try PassiveBluetoothExperimentOneExportEnvelopeJSON.verify(tampered)
        }
    }

    @Test
    func buildMetadataCannotDriftFromManifest() throws {
        let captureJSON = try makeCapture()
        let result = try makePowerCycleResult()
        let envelopeJSON = try makeEnvelope(captureJSON: captureJSON, result: result)
        var root = try rootObject(envelopeJSON)
        var build = try #require(root["build"] as? [String: Any])
        build["sourceCommitSHA"] = "0123456789abcdef0123456789abcdef01234567"
        root["build"] = build

        let tampered = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        #expect(
            throws: PassiveBluetoothExperimentOneExportEnvelopeError.manifestBuildIdentityMismatch
        ) {
            _ = try PassiveBluetoothExperimentOneExportEnvelopeJSON.verify(tampered)
        }
    }

    @Test
    func fourWindowEvidenceCannotBeSwappedOrDetachedFromManifestTarget() throws {
        let captureJSON = try makeCapture()
        let result = try makePowerCycleResult()
        let envelopeJSON = try makeEnvelope(captureJSON: captureJSON, result: result)
        var root = try rootObject(envelopeJSON)
        var evidence = try #require(root["powerCycleEvidence"] as? [String: Any])
        var snapshots = try #require(evidence["observationSnapshots"] as? [[String: Any]])
        snapshots.swapAt(1, 2)
        evidence["observationSnapshots"] = snapshots
        root["powerCycleEvidence"] = evidence

        let tampered = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        #expect(throws: PassiveBluetoothExperimentOneExportEnvelopeError.powerCycleEvidenceMalformed) {
            _ = try PassiveBluetoothExperimentOneExportEnvelopeJSON.verify(tampered)
        }
    }

    @Test
    func currentNoGoSchemaRejectsSmuggledFieldAuthorization() throws {
        let captureJSON = try makeCapture()
        let result = try makePowerCycleResult()
        let envelopeJSON = try makeEnvelope(captureJSON: captureJSON, result: result)
        var root = try rootObject(envelopeJSON)
        root["fieldAuthorizationRecordID"] = "caller-authored-go-record"

        let tampered = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        #expect(throws: PassiveBluetoothExperimentOneExportEnvelopeError.fieldAuthorizationNotSupported) {
            _ = try PassiveBluetoothExperimentOneExportEnvelopeJSON.verify(tampered)
        }
    }

    @Test
    func unknownTopLevelAuthorityFieldFailsClosed() throws {
        let captureJSON = try makeCapture()
        let result = try makePowerCycleResult()
        let envelopeJSON = try makeEnvelope(captureJSON: captureJSON, result: result)
        var root = try rootObject(envelopeJSON)
        root["physicalGO"] = true

        let tampered = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        #expect(
            throws: PassiveBluetoothExperimentOneExportEnvelopeError
                .unexpectedEnvelopeField("physicalGO")
        ) {
            _ = try PassiveBluetoothExperimentOneExportEnvelopeJSON.verify(tampered)
        }
    }

    @Test
    func executableDigestMustRemainCanonicalHashEvidence() throws {
        let captureJSON = try makeCapture()
        let result = try makePowerCycleResult()
        let envelopeJSON = try makeEnvelope(captureJSON: captureJSON, result: result)
        var root = try rootObject(envelopeJSON)
        var build = try #require(root["build"] as? [String: Any])
        build["executableSHA256"] = "NOT-A-HASH"
        root["build"] = build

        let tampered = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        #expect(
            throws: PassiveBluetoothExperimentOneExportEnvelopeError
                .invalidExecutableSHA256("NOT-A-HASH")
        ) {
            _ = try PassiveBluetoothExperimentOneExportEnvelopeJSON.verify(tampered)
        }
    }

    private func makeEnvelope(
        captureJSON: Data,
        result: PassiveBluetoothPowerCycleObservationResult
    ) throws -> Data {
        let manifest = try PassiveBluetoothStationaryCaptureManifestBuilder.make(
            captureJSON: captureJSON,
            experimentID: experimentID,
            experimentRecipe: .es80FingerprintV1,
            preparedAt: preparedAt,
            nembraBuildIdentifier: buildIdentifier,
            nembraBuildInstanceID: buildInstanceID,
            nembraBuildCommitSHA: commit,
            selectedPeripheralIdentifier: target.uuidString,
            setup: defaultSetup()
        )
        let manifestJSON = try PassiveBluetoothStationaryCaptureManifestJSON.encode(
            manifest,
            prettyPrinted: false
        )

        let root: [String: Any] = [
            "schemaVersion": 1,
            "recipeID": PassiveBluetoothExperimentRecipeID.es80FingerprintV1.rawValue,
            "captureJSON": captureJSON.base64EncodedString(),
            "captureSHA256": manifest.sourceArtifact.sha256,
            "manifestJSON": manifestJSON.base64EncodedString(),
            "powerCycleEvidence": powerCycleEvidenceObject(result),
            "build": [
                "buildIdentifier": buildIdentifier,
                "buildInstanceID": buildInstanceID,
                "sourceCommitSHA": commit,
                "executableSHA256": executableSHA256,
            ],
        ]
        return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
    }

    private func powerCycleEvidenceObject(
        _ result: PassiveBluetoothPowerCycleObservationResult
    ) -> [String: Any] {
        [
            "windows": result.windows.map { receipt in
                [
                    "phaseRawValue": receipt.phase.rawValue,
                    "windowSequence": receipt.windowSequence.rawValue,
                    "startedAtUptimeNanoseconds": receipt.startedAtUptimeNanoseconds,
                    "endedAtUptimeNanoseconds": receipt.endedAtUptimeNanoseconds,
                    "observedCandidateCount": receipt.observedCandidateCount,
                ] as [String: Any]
            },
            "observationSnapshots": result.observationSnapshots.map { snapshot in
                [
                    "observationSeriesIdentity": snapshot.observationSeriesIdentity.rawValue.uuidString,
                    "windowSequence": snapshot.windowSequence.rawValue,
                    "candidates": snapshot.candidates.map { candidate in
                        var object: [String: Any] = [
                            "peripheralIdentifier": candidate.id.uuidString,
                        ]
                        if let isConnectable = candidate.isConnectable {
                            object["isConnectable"] = isConnectable
                        }
                        return object
                    },
                ] as [String: Any]
            },
        ]
    }

    private func makePowerCycleResult() throws -> PassiveBluetoothPowerCycleObservationResult {
        var ledger = PassiveBluetoothPowerCycleObservationLedger(
            minimumWindowDurationNanoseconds: 1
        )
        let backgroundCandidate = PassiveBluetoothCandidateObservationSnapshot.Candidate(
            id: background,
            isConnectable: true
        )
        let targetCandidate = PassiveBluetoothCandidateObservationSnapshot.Candidate(
            id: target,
            isConnectable: true
        )

        _ = try ledger.completeWindow(
            phase: .firstPoweredOff,
            startedAtUptimeNanoseconds: 10,
            endedAtUptimeNanoseconds: 20,
            candidates: [backgroundCandidate]
        )
        _ = try ledger.completeWindow(
            phase: .firstPoweredOn,
            startedAtUptimeNanoseconds: 30,
            endedAtUptimeNanoseconds: 40,
            candidates: [backgroundCandidate, targetCandidate]
        )
        _ = try ledger.completeWindow(
            phase: .secondPoweredOff,
            startedAtUptimeNanoseconds: 50,
            endedAtUptimeNanoseconds: 60,
            candidates: [backgroundCandidate]
        )
        let result = try ledger.completeWindow(
            phase: .secondPoweredOn,
            startedAtUptimeNanoseconds: 70,
            endedAtUptimeNanoseconds: 80,
            candidates: [backgroundCandidate, targetCandidate]
        )
        return try #require(result)
    }

    private func defaultSetup() -> PassiveBluetoothStationaryCaptureSetup {
        .init(
            chargerState: .disconnected,
            executionContext: .foregroundUnlockedScreenOn,
            stockAppReferenceSetup: .none
        )
    }

    private func rootObject(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
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
