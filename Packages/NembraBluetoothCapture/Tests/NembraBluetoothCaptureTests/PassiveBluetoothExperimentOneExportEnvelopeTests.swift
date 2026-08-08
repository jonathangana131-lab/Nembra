import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Experiment One final export envelope")
struct PassiveBluetoothExperimentOneExportEnvelopeTests {
    private typealias Envelope = PassiveBluetoothExperimentOneExportEnvelopeJSON
    private typealias EnvelopeError = PassiveBluetoothExperimentOneExportEnvelopeError
    private typealias BuildReader = PassiveBluetoothCaptureRuntimeBuildIdentityReader

    private let target = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let background = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let sessionID = UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!
    private let experimentID = UUID(uuidString: "99999999-8888-7777-6666-555555555555")!
    private let preparedAt = Date(timeIntervalSince1970: 1_750_000_100)
    private let commit = "abcdef0123456789abcdef0123456789abcdef01"
    private let buildIdentifier = "Capture Build V14-abcdef012345"
    private let buildInstanceID = "a1b2c3d4-e5f6-47a8-90bc-def123456789"
    private let executableSHA256 = String(repeating: "e", count: 64)

    @Test("verification replays exact capture, manifest, build, and four-window evidence")
    func verifiedEnvelopeReplaysExactCaptureManifestBuildAndFourWindowEvidence() throws {
        let captureJSON = try makeCapture()
        let result = try makePowerCycleResult()
        let envelopeJSON = try makeEnvelope(captureJSON: captureJSON, result: result)

        let verified = try Envelope.verify(envelopeJSON)

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

    @Test("package producer binds the same accepted evidence contract it later verifies")
    func packageProducerRoundTripsAcceptedEvidence() throws {
        let captureJSON = try makeCapture()
        let result = try makePowerCycleResult()
        let runtimeIdentity = try BuildReader.resolveEmbeddedMetadata(
            infoDictionary: [
                BuildReader.buildIdentifierInfoDictionaryKey: buildIdentifier,
                BuildReader.buildInstanceIDInfoDictionaryKey: buildInstanceID,
                BuildReader.sourceCommitSHAInfoDictionaryKey: commit,
            ],
            executableData: Data("accepted fixture executable".utf8)
        )

        let envelope = try Envelope.make(
            captureJSON: captureJSON,
            powerCycleResult: result,
            setup: defaultSetup(),
            runtimeIdentity: runtimeIdentity,
            experimentID: experimentID,
            preparedAt: preparedAt,
            prettyPrinted: false
        )
        let verified = try Envelope.verify(envelope)

        #expect(verified.captureJSON == captureJSON)
        #expect(verified.powerCycleResult == result)
        #expect(verified.manifest.experimentID == experimentID)
        #expect(verified.buildEvidence.buildIdentifier == runtimeIdentity.buildIdentifier)
        #expect(verified.buildEvidence.buildInstanceID == runtimeIdentity.buildInstanceID)
        #expect(verified.buildEvidence.sourceCommitSHA == runtimeIdentity.sourceCommitSHA)
        #expect(verified.buildEvidence.executableSHA256 == runtimeIdentity.executableSHA256)
    }

    @Test("one-nanosecond-short power-cycle windows fail closed")
    func shortPowerCycleWindowCannotBeProduced() throws {
        let captureJSON = try makeCapture()
        let result = try makePowerCycleResult(
            windowDurationNanoseconds:
                PassiveBluetoothExperimentOneCapturePolicy.minimumPowerCycleWindowDurationNanoseconds - 1
        )
        let runtimeIdentity = try fixtureRuntimeIdentity()

        #expect(throws: EnvelopeError.experimentEvidenceNotStructurallyCoherent) {
            _ = try Envelope.make(
                captureJSON: captureJSON,
                powerCycleResult: result,
                setup: defaultSetup(),
                runtimeIdentity: runtimeIdentity,
                experimentID: experimentID,
                preparedAt: preparedAt,
                prettyPrinted: false
            )
        }
    }

    @Test("overlapping power-cycle windows fail closed even when each duration is sufficient")
    func overlappingPowerCycleWindowsCannotBeProduced() throws {
        let duration = PassiveBluetoothExperimentOneCapturePolicy.minimumPowerCycleWindowDurationNanoseconds
        let captureJSON = try makeCapture()
        let result = try makePowerCycleResult(
            windowDurationNanoseconds: duration,
            windowStartStrideNanoseconds: duration / 2
        )
        let runtimeIdentity = try fixtureRuntimeIdentity()

        #expect(throws: EnvelopeError.experimentEvidenceNotStructurallyCoherent) {
            _ = try Envelope.make(
                captureJSON: captureJSON,
                powerCycleResult: result,
                setup: defaultSetup(),
                runtimeIdentity: runtimeIdentity,
                experimentID: experimentID,
                preparedAt: preparedAt,
                prettyPrinted: false
            )
        }
    }

    @Test("one-nanosecond-short Ready-to-Horizon observation fails closed")
    func shortObservationHorizonCannotBeProduced() throws {
        let captureJSON = try makeCapture(
            postReadyDurationNanoseconds:
                PassiveBluetoothExperimentOneCapturePolicy.minimumPostReadyObservationDurationNanoseconds - 1
        )
        let result = try makePowerCycleResult()
        let runtimeIdentity = try fixtureRuntimeIdentity()

        #expect(throws: EnvelopeError.experimentEvidenceNotStructurallyCoherent) {
            _ = try Envelope.make(
                captureJSON: captureJSON,
                powerCycleResult: result,
                setup: defaultSetup(),
                runtimeIdentity: runtimeIdentity,
                experimentID: experimentID,
                preparedAt: preparedAt,
                prettyPrinted: false
            )
        }
    }

    @Test("exact capture bytes cannot change behind manifest and hash")
    func exactCaptureBytesCannotBeChangedBehindManifestAndHash() throws {
        let captureJSON = try makeCapture()
        let result = try makePowerCycleResult()
        let envelopeJSON = try makeEnvelope(captureJSON: captureJSON, result: result)
        var root = try rootObject(envelopeJSON)
        var tamperedCapture = captureJSON
        tamperedCapture.append(0x0A)
        root["captureJSON"] = tamperedCapture.base64EncodedString()

        let tampered = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        #expect(throws: EnvelopeError.captureHashMismatch) {
            _ = try Envelope.verify(tampered)
        }
    }

    @Test("build metadata cannot drift from manifest")
    func buildMetadataCannotDriftFromManifest() throws {
        let captureJSON = try makeCapture()
        let result = try makePowerCycleResult()
        let envelopeJSON = try makeEnvelope(captureJSON: captureJSON, result: result)
        var root = try rootObject(envelopeJSON)
        var build = try #require(root["build"] as? [String: Any])
        build["sourceCommitSHA"] = "0123456789abcdef0123456789abcdef01234567"
        root["build"] = build

        let tampered = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        #expect(throws: EnvelopeError.manifestBuildIdentityMismatch) {
            _ = try Envelope.verify(tampered)
        }
    }

    @Test("four-window snapshots cannot be swapped")
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
        #expect(throws: EnvelopeError.powerCycleEvidenceMalformed) {
            _ = try Envelope.verify(tampered)
        }
    }

    @Test("unknown nested evidence fields fail closed before Codable can ignore them")
    func unknownNestedEvidenceFieldFailsClosed() throws {
        let envelopeJSON = try makeEnvelope(
            captureJSON: makeCapture(),
            result: makePowerCycleResult()
        )
        var root = try rootObject(envelopeJSON)
        var evidence = try #require(root["powerCycleEvidence"] as? [String: Any])
        var windows = try #require(evidence["windows"] as? [[String: Any]])
        windows[0]["radioTimestamp"] = 123
        evidence["windows"] = windows
        root["powerCycleEvidence"] = evidence

        let tampered = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        #expect(
            throws: EnvelopeError.unexpectedEnvelopeField(
                "powerCycleEvidence.windows[0].radioTimestamp"
            )
        ) {
            _ = try Envelope.verify(tampered)
        }
    }

    @Test("current NO-GO schema rejects smuggled field authorization")
    func currentNoGoSchemaRejectsSmuggledFieldAuthorization() throws {
        let envelopeJSON = try makeEnvelope(
            captureJSON: makeCapture(),
            result: makePowerCycleResult()
        )
        var root = try rootObject(envelopeJSON)
        root["fieldAuthorizationRecordID"] = "caller-authored-go-record"

        let tampered = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        #expect(throws: EnvelopeError.fieldAuthorizationNotSupported) {
            _ = try Envelope.verify(tampered)
        }
    }

    @Test("unknown top-level authority fields fail closed")
    func unknownTopLevelAuthorityFieldFailsClosed() throws {
        let envelopeJSON = try makeEnvelope(
            captureJSON: makeCapture(),
            result: makePowerCycleResult()
        )
        var root = try rootObject(envelopeJSON)
        root["physicalGO"] = true

        let tampered = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        #expect(throws: EnvelopeError.unexpectedEnvelopeField("physicalGO")) {
            _ = try Envelope.verify(tampered)
        }
    }

    @Test("executable digest remains canonical hash evidence")
    func executableDigestMustRemainCanonicalHashEvidence() throws {
        let envelopeJSON = try makeEnvelope(
            captureJSON: makeCapture(),
            result: makePowerCycleResult()
        )
        var root = try rootObject(envelopeJSON)
        var build = try #require(root["build"] as? [String: Any])
        build["executableSHA256"] = "NOT-A-HASH"
        root["build"] = build

        let tampered = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        #expect(throws: EnvelopeError.invalidExecutableSHA256("NOT-A-HASH")) {
            _ = try Envelope.verify(tampered)
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

    private func makePowerCycleResult(
        windowDurationNanoseconds: UInt64 =
            PassiveBluetoothExperimentOneCapturePolicy.minimumPowerCycleWindowDurationNanoseconds,
        windowStartStrideNanoseconds: UInt64 = 20_000_000_000
    ) throws -> PassiveBluetoothPowerCycleObservationResult {
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
        var result: PassiveBluetoothPowerCycleObservationResult?

        for (index, phase) in PassiveBluetoothPowerCycleObservationPhase.allCases.enumerated() {
            let start = UInt64(index) * windowStartStrideNanoseconds
            let candidates = phase.operatorExpectedPowerOn
                ? [backgroundCandidate, targetCandidate]
                : [backgroundCandidate]
            result = try ledger.completeWindow(
                phase: phase,
                startedAtUptimeNanoseconds: start,
                endedAtUptimeNanoseconds: start + windowDurationNanoseconds,
                candidates: candidates
            ) ?? result
        }

        return try #require(result)
    }

    private func defaultSetup() -> PassiveBluetoothStationaryCaptureSetup {
        .init(
            chargerState: .disconnected,
            executionContext: .foregroundUnlockedScreenOn,
            stockAppReferenceSetup: .none
        )
    }

    private func fixtureRuntimeIdentity() throws -> PassiveBluetoothCaptureRuntimeBuildIdentity {
        try BuildReader.resolveEmbeddedMetadata(
            infoDictionary: [
                BuildReader.buildIdentifierInfoDictionaryKey: buildIdentifier,
                BuildReader.buildInstanceIDInfoDictionaryKey: buildInstanceID,
                BuildReader.sourceCommitSHAInfoDictionaryKey: commit,
            ],
            executableData: Data("accepted fixture executable".utf8)
        )
    }

    private func rootObject(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func makeCapture(
        postReadyDurationNanoseconds: UInt64 =
            PassiveBluetoothExperimentOneCapturePolicy.minimumPostReadyObservationDurationNanoseconds
    ) throws -> Data {
        let service = PassiveBluetoothCaptureRecord(
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 100,
            receivedAtDate: Date(timeIntervalSince1970: 1_750_000_001),
            event: .service(
                try PassiveBluetoothServiceObservation(
                    peripheralIdentifier: target.uuidString,
                    serviceUUID: "FFE0",
                    isPrimary: true
                )
            )
        )
        let value = PassiveBluetoothCaptureRecord(
            sequenceNumber: 2,
            receivedAtUptimeNanoseconds: 200,
            receivedAtDate: Date(timeIntervalSince1970: 1_750_000_002),
            event: .value(
                try PassiveBluetoothValueObservation(
                    peripheralIdentifier: target.uuidString,
                    serviceUUID: "FFE0",
                    characteristicUUID: "FFE1",
                    origin: .subscriptionUpdate,
                    payload: Data([0x01, 0x02])
                )
            )
        )
        let readyUptime: UInt64 = 1_000
        let ready = PassiveBluetoothObservationBoundary(
            kind: .finiteAcquisitionReady,
            recordSequenceWatermark: 2,
            observedAtUptimeNanoseconds: readyUptime,
            observedAtDate: Date(timeIntervalSince1970: 1_750_000_003)
        )
        let horizon = PassiveBluetoothObservationBoundary(
            kind: .observationHorizon,
            recordSequenceWatermark: 2,
            observedAtUptimeNanoseconds: readyUptime + postReadyDurationNanoseconds,
            observedAtDate: Date(timeIntervalSince1970: 1_750_000_063)
        )
        let session = try PassiveBluetoothCaptureSession(
            id: sessionID,
            vehicleIdentity: .init(
                manufacturer: "AOVOPRO",
                model: "ES80",
                displayName: "AOVOPRO ES80",
                protocolFamily: "unverified-tuya"
            ),
            startedAt: Date(timeIntervalSince1970: 1_750_000_000),
            records: [service, value],
            observationBoundaries: [ready, horizon]
        )
        return try PassiveBluetoothCaptureJSON.encode(session)
    }
}
