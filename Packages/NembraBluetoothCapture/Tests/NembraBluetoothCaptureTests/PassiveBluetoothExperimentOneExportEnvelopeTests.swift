import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive Bluetooth Experiment One export envelope")
struct PassiveBluetoothExperimentOneExportEnvelopeTests {
    private typealias Reader = PassiveBluetoothCaptureRuntimeBuildIdentityReader

    private let target = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let noise = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let sessionID = UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!
    private let experimentID = UUID(uuidString: "99999999-8888-7777-6666-555555555555")!
    private let preparedAt = Date(timeIntervalSince1970: 1_750_000_100)

    @Test("final JSON binds capture, repeated correlation, recipe, and produced build identity")
    func bindsCompleteSoftwareEvidence() throws {
        let captureJSON = try makeCapture()
        let result = try makePowerCycleResult()
        let identity = try makeRuntimeIdentity()

        let data = try PassiveBluetoothExperimentOneExportEnvelopeJSON.make(
            captureJSON: captureJSON,
            powerCycleResult: result,
            setup: defaultSetup(),
            runtimeIdentity: identity,
            experimentID: experimentID,
            preparedAt: preparedAt,
            prettyPrinted: false
        )
        let verified = try PassiveBluetoothExperimentOneExportEnvelopeJSON.verify(data)

        #expect(verified.schemaVersion == 1)
        #expect(verified.experimentRecipeID == .es80FingerprintV1)
        #expect(verified.correlatedPeripheralIdentifier == target)
        #expect(verified.nembraBuildIdentifier == identity.buildIdentifier)
        #expect(verified.nembraBuildInstanceID == identity.buildInstanceID)
        #expect(verified.nembraBuildCommitSHA == identity.sourceCommitSHA)
        #expect(verified.runtimeExecutableSHA256 == identity.executableSHA256)
        #expect(verified.captureJSON == captureJSON)
        #expect(verified.powerCycleEvidence.windows.count == 4)
        #expect(verified.powerCycleEvidence.observationSnapshots.count == 4)
        #expect(verified.powerCycleEvidence.correlation.disposition == .singleRepeatableCandidate)
        #expect(verified.powerCycleEvidence.correlation.repeatableCandidateIdentifiers == [target])

        let manifest = try PassiveBluetoothStationaryCaptureManifestJSON.verifyCaptureBinding(
            manifestJSON: verified.stationaryManifestJSON,
            captureJSON: verified.captureJSON
        )
        #expect(manifest.schemaVersion == 3)
        #expect(manifest.experimentID == experimentID)
        #expect(manifest.experimentRecipeID == .es80FingerprintV1)
        #expect(manifest.nembraBuildInstanceID == identity.buildInstanceID)
        #expect(manifest.sourceArtifact.selectedPeripheralIdentifier == target.uuidString)
    }

    @Test("changed sealed capture bytes cannot retain the embedded manifest")
    func rejectsCaptureByteTampering() throws {
        let data = try makeEnvelopeJSON()
        var root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var capture = try #require(Data(base64Encoded: try #require(root["captureJSON"] as? String)))
        capture.append(0x0A)
        root["captureJSON"] = capture.base64EncodedString()
        let tampered = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])

        #expect(throws: PassiveBluetoothStationaryCaptureManifestError.manifestDoesNotMatchCapture) {
            _ = try PassiveBluetoothExperimentOneExportEnvelopeJSON.verify(tampered)
        }
    }

    @Test("changed correlation snapshots cannot retain the accepted target claim")
    func rejectsCorrelationTampering() throws {
        let data = try makeEnvelopeJSON()
        var root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var evidence = try #require(root["powerCycleEvidence"] as? [String: Any])
        var snapshots = try #require(evidence["observationSnapshots"] as? [[String: Any]])
        var firstOn = snapshots[1]
        var candidates = try #require(firstOn["candidates"] as? [[String: Any]])
        candidates.removeAll { ($0["id"] as? String)?.uppercased() == target.uuidString }
        firstOn["candidates"] = candidates
        snapshots[1] = firstOn
        evidence["observationSnapshots"] = snapshots
        root["powerCycleEvidence"] = evidence
        let tampered = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])

        #expect(throws: PassiveBluetoothExperimentOneExportEnvelopeError.invalidPowerCycleEvidence) {
            _ = try PassiveBluetoothExperimentOneExportEnvelopeJSON.verify(tampered)
        }
    }

    @Test("a run without one repeatable full UUID cannot be exported")
    func requiresSingleRepeatableTarget() throws {
        let identity = try makeRuntimeIdentity()
        let noTarget = try makePowerCycleResult(includeTarget: false)

        #expect(throws: PassiveBluetoothExperimentOneExportEnvelopeError.correlationNotSingleTarget) {
            _ = try PassiveBluetoothExperimentOneExportEnvelopeJSON.make(
                captureJSON: makeCapture(),
                powerCycleResult: noTarget,
                setup: defaultSetup(),
                runtimeIdentity: identity,
                experimentID: experimentID,
                preparedAt: preparedAt,
                prettyPrinted: false
            )
        }
    }

    @Test("runtime executable digest is canonical and cannot drift independently")
    func rejectsRuntimeExecutableIdentityDrift() throws {
        let data = try makeEnvelopeJSON()
        var root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        root["runtimeExecutableSHA256"] = String(repeating: "A", count: 64)
        let tampered = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])

        #expect(
            throws: PassiveBluetoothExperimentOneExportEnvelopeError
                .invalidRuntimeExecutableSHA256(String(repeating: "A", count: 64))
        ) {
            _ = try PassiveBluetoothExperimentOneExportEnvelopeJSON.verify(tampered)
        }
    }

    private func makeEnvelopeJSON() throws -> Data {
        try PassiveBluetoothExperimentOneExportEnvelopeJSON.make(
            captureJSON: makeCapture(),
            powerCycleResult: makePowerCycleResult(),
            setup: defaultSetup(),
            runtimeIdentity: makeRuntimeIdentity(),
            experimentID: experimentID,
            preparedAt: preparedAt,
            prettyPrinted: false
        )
    }

    private func makeRuntimeIdentity() throws -> PassiveBluetoothCaptureRuntimeBuildIdentity {
        try Reader.resolveEmbeddedMetadata(
            infoDictionary: [
                Reader.buildIdentifierInfoDictionaryKey: "Capture Build V14-F1",
                Reader.buildInstanceIDInfoDictionaryKey: "12345678-90ab-cdef-1234-567890abcdef",
                Reader.sourceCommitSHAInfoDictionaryKey: "0123456789abcdef0123456789abcdef01234567",
            ],
            executableData: Data("signed app fixture".utf8)
        )
    }

    private func makePowerCycleResult(
        includeTarget: Bool = true
    ) throws -> PassiveBluetoothPowerCycleObservationResult {
        let series = PassiveBluetoothCandidateObservationSeriesIdentity(
            rawValue: UUID(uuidString: "FEDCBA98-7654-3210-FEDC-BA9876543210")!
        )
        let phases = PassiveBluetoothPowerCycleObservationPhase.allCases
        let candidateSets: [[PassiveBluetoothCandidateObservationSnapshot.Candidate]] = [
            [.init(id: noise, isConnectable: true)],
            [.init(id: noise, isConnectable: true)] + (includeTarget ? [.init(id: target, isConnectable: true)] : []),
            [.init(id: noise, isConnectable: true)],
            [.init(id: noise, isConnectable: true)] + (includeTarget ? [.init(id: target, isConnectable: true)] : []),
        ]

        let snapshots = try candidateSets.enumerated().map { index, candidates in
            try PassiveBluetoothCandidateObservationSnapshot(
                observationSeriesIdentity: series,
                windowSequence: .init(rawValue: UInt64(index + 1)),
                candidates: candidates
            )
        }
        let windows = phases.enumerated().map { index, phase in
            PassiveBluetoothPowerCycleObservationWindowReceipt(
                phase: phase,
                windowSequence: .init(rawValue: UInt64(index + 1)),
                startedAtUptimeNanoseconds: UInt64(100 + index * 100),
                endedAtUptimeNanoseconds: UInt64(150 + index * 100),
                observedCandidateCount: snapshots[index].candidates.count
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

    private func makeCapture() throws -> Data {
        let startedAt = Date(timeIntervalSince1970: 1_750_000_000)
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
        try session.append(
            .service(try PassiveBluetoothServiceObservation(
                peripheralIdentifier: target.uuidString,
                serviceUUID: "FFE0",
                isPrimary: true
            )),
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 1,
            receivedAtDate: startedAt
        )
        try session.append(
            .characteristic(try PassiveBluetoothCharacteristicObservation(
                peripheralIdentifier: target.uuidString,
                serviceUUID: "FFE0",
                characteristicUUID: "FFE1",
                properties: [.notify]
            )),
            sequenceNumber: 2,
            receivedAtUptimeNanoseconds: 2,
            receivedAtDate: startedAt.addingTimeInterval(1)
        )
        try session.append(
            .value(try PassiveBluetoothValueObservation(
                peripheralIdentifier: target.uuidString,
                serviceUUID: "FFE0",
                characteristicUUID: "FFE1",
                origin: .subscriptionUpdate,
                payload: Data([0x01, 0x02])
            )),
            sequenceNumber: 3,
            receivedAtUptimeNanoseconds: 3,
            receivedAtDate: startedAt.addingTimeInterval(2)
        )
        return try PassiveBluetoothCaptureJSON.encode(session)
    }

    private func defaultSetup() -> PassiveBluetoothStationaryCaptureSetup {
        .init(
            chargerState: .disconnected,
            executionContext: .foregroundUnlockedScreenOn,
            stockAppReferenceSetup: .none
        )
    }
}
