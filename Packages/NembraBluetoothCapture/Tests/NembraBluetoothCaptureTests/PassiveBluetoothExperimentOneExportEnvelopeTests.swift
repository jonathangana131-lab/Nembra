import Foundation
import Testing
@testable import NembraBluetoothCapture

struct PassiveBluetoothExperimentOneExportEnvelopeTests {
    private let target = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let alternateTarget = UUID(uuidString: "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE")!
    private let noise = UUID(uuidString: "99999999-8888-4777-8666-555555555555")!
    private let sessionID = UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!
    private let seriesID = UUID(uuidString: "12345678-1234-4ABC-8DEF-123456789ABC")!
    private let preparedAt = Date(timeIntervalSince1970: 1_750_000_100)
    private let commit = "abcdef0123456789abcdef0123456789abcdef01"
    private let buildIdentifier = "Capture Build V14-envelope"
    private let buildInstanceID = "a1b2c3d4-e5f6-47a8-90bc-def123456789"

    @Test
    func roundTripBindsCaptureCorrelationManifestRecipeAndRuntimeBuild() throws {
        let captureJSON = try makeCapture(payload: Data([0x01, 0x02]))
        let result = try makePowerCycleResult(target: target)
        let runtime = try makeRuntimeBuildIdentity()

        let envelopeJSON = try PassiveBluetoothExperimentOneExportEnvelopeJSON._testingEncode(
            captureJSON: captureJSON,
            powerCycleResult: result,
            runtimeBuildIdentity: runtime,
            setup: defaultSetup(),
            preparedAt: preparedAt
        )
        let verified = try PassiveBluetoothExperimentOneExportEnvelopeJSON.verify(envelopeJSON)

        #expect(PassiveBluetoothExperimentOneExportEnvelopeJSON.currentSchemaVersion == 1)
        #expect(verified.schemaVersion == 1)
        #expect(verified.experimentRecipeID == .es80FingerprintV1)
        #expect(verified.captureJSON == captureJSON)
        #expect(verified.powerCycleResult == result)
        #expect(verified.stationaryManifest.schemaVersion == 3)
        #expect(verified.stationaryManifest.experimentRecipeID == .es80FingerprintV1)
        #expect(verified.stationaryManifest.sourceArtifact.selectedPeripheralIdentifier == target.uuidString)
        #expect(verified.stationaryManifest.nembraBuildIdentifier == buildIdentifier)
        #expect(verified.stationaryManifest.nembraBuildInstanceID == buildInstanceID)
        #expect(verified.stationaryManifest.nembraBuildCommitSHA == commit)
        #expect(verified.runtimeBuild.buildIdentifier == buildIdentifier)
        #expect(verified.runtimeBuild.buildInstanceID == buildInstanceID)
        #expect(verified.runtimeBuild.sourceCommitSHA == commit)
        #expect(verified.runtimeBuild.executableSHA256 == runtime.executableSHA256)

        let root = try #require(JSONSerialization.jsonObject(with: envelopeJSON) as? [String: Any])
        #expect(root["fieldAuthorized"] == nil)
        #expect(root["physicalGO"] == nil)
        #expect(root["targetIdentifier"] == nil)
    }

    @Test
    func changedCaptureBytesCannotReuseTheEmbeddedManifest() throws {
        let envelopeJSON = try makeEnvelopeJSON()
        var root = try #require(JSONSerialization.jsonObject(with: envelopeJSON) as? [String: Any])
        let changedCapture = try makeCapture(payload: Data([0xFE, 0xED]))
        root["captureJSON"] = changedCapture.base64EncodedString()
        let tampered = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])

        #expect(
            throws: PassiveBluetoothStationaryCaptureManifestError.manifestDoesNotMatchCapture
        ) {
            _ = try PassiveBluetoothExperimentOneExportEnvelopeJSON.verify(tampered)
        }
    }

    @Test
    func changedReplayableCorrelationCannotKeepTheOriginalManifestTarget() throws {
        let envelopeJSON = try makeEnvelopeJSON()
        var root = try #require(JSONSerialization.jsonObject(with: envelopeJSON) as? [String: Any])
        var powerCycle = try #require(root["powerCycleObservation"] as? [String: Any])
        var snapshots = try #require(powerCycle["snapshots"] as? [[String: Any]])

        for index in [1, 3] {
            var candidates = try #require(snapshots[index]["candidates"] as? [[String: Any]])
            let targetIndex = try #require(candidates.firstIndex(where: {
                ($0["id"] as? String)?.uppercased() == target.uuidString
            }))
            candidates[targetIndex]["id"] = alternateTarget.uuidString
            snapshots[index]["candidates"] = candidates
        }
        powerCycle["snapshots"] = snapshots
        root["powerCycleObservation"] = powerCycle
        let tampered = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])

        #expect(
            throws: PassiveBluetoothExperimentOneExportEnvelopeError.manifestTargetDoesNotMatchCorrelation
        ) {
            _ = try PassiveBluetoothExperimentOneExportEnvelopeJSON.verify(tampered)
        }
    }

    @Test
    func selfDeclaredFieldAuthorizationIsRejectedAsUnknownAuthority() throws {
        let envelopeJSON = try makeEnvelopeJSON()
        var root = try #require(JSONSerialization.jsonObject(with: envelopeJSON) as? [String: Any])
        root["fieldAuthorized"] = true
        let tampered = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])

        #expect(
            throws: PassiveBluetoothExperimentOneExportEnvelopeError
                .unexpectedEnvelopeField("fieldAuthorized")
        ) {
            _ = try PassiveBluetoothExperimentOneExportEnvelopeJSON.verify(tampered)
        }
    }

    @Test
    func importedRuntimeExecutableDigestMustKeepCanonicalMeasuredShape() throws {
        let envelopeJSON = try makeEnvelopeJSON()
        var root = try #require(JSONSerialization.jsonObject(with: envelopeJSON) as? [String: Any])
        var runtime = try #require(root["runtimeBuild"] as? [String: Any])
        runtime["executableSHA256"] = String(repeating: "A", count: 64)
        root["runtimeBuild"] = runtime
        let tampered = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])

        #expect(
            throws: PassiveBluetoothExperimentOneExportEnvelopeError.invalidRuntimeExecutableSHA256
        ) {
            _ = try PassiveBluetoothExperimentOneExportEnvelopeJSON.verify(tampered)
        }
    }

    @Test
    func builderRejectsShortOrOverlappingCorrelationReceipts() throws {
        let captureJSON = try makeCapture(payload: Data([0x01]))
        let runtime = try makeRuntimeBuildIdentity()
        let short = try makePowerCycleResult(target: target, duration: 9_999_999_999)

        #expect(
            throws: PassiveBluetoothExperimentOneExportEnvelopeError.powerCycleWindowTooShort(index: 0)
        ) {
            _ = try PassiveBluetoothExperimentOneExportEnvelopeJSON._testingEncode(
                captureJSON: captureJSON,
                powerCycleResult: short,
                runtimeBuildIdentity: runtime,
                setup: defaultSetup(),
                preparedAt: preparedAt
            )
        }

        let valid = try makePowerCycleResult(target: target)
        var windows = valid.windows
        let second = windows[1]
        windows[1] = PassiveBluetoothPowerCycleObservationWindowReceipt(
            phase: second.phase,
            windowSequence: second.windowSequence,
            startedAtUptimeNanoseconds: windows[0].endedAtUptimeNanoseconds - 1,
            endedAtUptimeNanoseconds: windows[0].endedAtUptimeNanoseconds - 1 + 10_000_000_000,
            observedCandidateCount: second.observedCandidateCount
        )
        let overlapping = PassiveBluetoothPowerCycleObservationResult(
            windows: windows,
            observationSnapshots: valid.observationSnapshots,
            correlation: valid.correlation
        )

        #expect(
            throws: PassiveBluetoothExperimentOneExportEnvelopeError.overlappingPowerCycleWindows(index: 1)
        ) {
            _ = try PassiveBluetoothExperimentOneExportEnvelopeJSON._testingEncode(
                captureJSON: captureJSON,
                powerCycleResult: overlapping,
                runtimeBuildIdentity: runtime,
                setup: defaultSetup(),
                preparedAt: preparedAt
            )
        }
    }

    @Test
    func builderReplaysCorrelationInsteadOfTrustingDetachedSummary() throws {
        let captureJSON = try makeCapture(payload: Data([0x01]))
        let runtime = try makeRuntimeBuildIdentity()
        let valid = try makePowerCycleResult(target: target)
        let other = try makePowerCycleResult(target: alternateTarget)
        let forgedSummary = PassiveBluetoothPowerCycleObservationResult(
            windows: valid.windows,
            observationSnapshots: valid.observationSnapshots,
            correlation: other.correlation
        )

        #expect(
            throws: PassiveBluetoothExperimentOneExportEnvelopeError.correlationDoesNotMatchSnapshots
        ) {
            _ = try PassiveBluetoothExperimentOneExportEnvelopeJSON._testingEncode(
                captureJSON: captureJSON,
                powerCycleResult: forgedSummary,
                runtimeBuildIdentity: runtime,
                setup: defaultSetup(),
                preparedAt: preparedAt
            )
        }
    }

    @Test
    func nestedUnknownFieldsFailClosed() throws {
        let envelopeJSON = try makeEnvelopeJSON()
        var root = try #require(JSONSerialization.jsonObject(with: envelopeJSON) as? [String: Any])
        var powerCycle = try #require(root["powerCycleObservation"] as? [String: Any])
        var snapshots = try #require(powerCycle["snapshots"] as? [[String: Any]])
        snapshots[0]["radioComplete"] = true
        powerCycle["snapshots"] = snapshots
        root["powerCycleObservation"] = powerCycle
        let tampered = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])

        #expect(
            throws: PassiveBluetoothExperimentOneExportEnvelopeError
                .unexpectedEnvelopeField("powerCycleObservation.snapshots[0].radioComplete")
        ) {
            _ = try PassiveBluetoothExperimentOneExportEnvelopeJSON.verify(tampered)
        }
    }

    private func makeEnvelopeJSON() throws -> Data {
        try PassiveBluetoothExperimentOneExportEnvelopeJSON._testingEncode(
            captureJSON: makeCapture(payload: Data([0x01, 0x02])),
            powerCycleResult: makePowerCycleResult(target: target),
            runtimeBuildIdentity: makeRuntimeBuildIdentity(),
            setup: defaultSetup(),
            preparedAt: preparedAt
        )
    }

    private func makeRuntimeBuildIdentity() throws -> PassiveBluetoothCaptureRuntimeBuildIdentity {
        try PassiveBluetoothCaptureRuntimeBuildIdentityReader.resolveEmbeddedMetadata(
            infoDictionary: [
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildIdentifierInfoDictionaryKey: buildIdentifier,
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildInstanceIDInfoDictionaryKey: buildInstanceID,
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.sourceCommitSHAInfoDictionaryKey: commit,
            ],
            executableData: Data("fixture executable".utf8)
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
        target: UUID,
        duration: UInt64 = 10_000_000_000
    ) throws -> PassiveBluetoothPowerCycleObservationResult {
        let authority = PassiveBluetoothCandidateObservationSeriesIdentity(rawValue: seriesID)
        let candidateSets: [[PassiveBluetoothCandidateObservationSnapshot.Candidate]] = [
            [.init(id: noise, isConnectable: true)],
            [.init(id: noise, isConnectable: true), .init(id: target, isConnectable: true)],
            [.init(id: noise, isConnectable: true)],
            [.init(id: noise, isConnectable: true), .init(id: target, isConnectable: true)],
        ]

        var snapshots: [PassiveBluetoothCandidateObservationSnapshot] = []
        var windows: [PassiveBluetoothPowerCycleObservationWindowReceipt] = []
        for index in PassiveBluetoothPowerCycleObservationPhase.allCases.indices {
            let sequence = PassiveBluetoothCandidateObservationWindowSequence(rawValue: UInt64(index + 1))
            let snapshot = try PassiveBluetoothCandidateObservationSnapshot(
                observationSeriesIdentity: authority,
                windowSequence: sequence,
                candidates: candidateSets[index]
            )
            let start = UInt64(index) * 20_000_000_000
            snapshots.append(snapshot)
            windows.append(
                PassiveBluetoothPowerCycleObservationWindowReceipt(
                    phase: PassiveBluetoothPowerCycleObservationPhase.allCases[index],
                    windowSequence: sequence,
                    startedAtUptimeNanoseconds: start,
                    endedAtUptimeNanoseconds: start + duration,
                    observedCandidateCount: snapshot.candidates.count
                )
            )
        }

        let correlation = PassiveBluetoothPowerCycleTargetCorrelation.assess(
            firstOff: snapshots[0],
            firstOn: snapshots[1],
            secondOff: snapshots[2],
            secondOn: snapshots[3]
        )
        return PassiveBluetoothPowerCycleObservationResult(
            windows: windows,
            observationSnapshots: snapshots,
            correlation: correlation
        )
    }

    private func makeCapture(payload: Data) throws -> Data {
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
                payload: payload
            )),
            sequenceNumber: 2,
            receivedAtUptimeNanoseconds: 2,
            receivedAtDate: Date(timeIntervalSince1970: 1_750_000_002)
        )
        return try PassiveBluetoothCaptureJSON.encode(session)
    }
}