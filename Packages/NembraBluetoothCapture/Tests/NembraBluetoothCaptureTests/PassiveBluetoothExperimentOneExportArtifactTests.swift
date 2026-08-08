import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

struct PassiveBluetoothExperimentOneExportArtifactTests {
    private let target = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let other = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let replacement = UUID(uuidString: "99999999-8888-7777-6666-555555555555")!
    private let experimentID = UUID(uuidString: "12345678-1234-1234-1234-123456789ABC")!
    private let buildInstanceID = "4e2c20db-78e6-41f5-a2fe-0123456789ab"
    private let commit = "abcdef0123456789abcdef0123456789abcdef01"

    @Test
    func finalExportBindsExactCaptureCorrelationManifestAndRuntimeBuild() throws {
        let captureJSON = try makeCapture()
        let correlation = try makeCorrelationResult()
        let runtime = try makeRuntimeBuildIdentity()

        let artifact = try PassiveBluetoothExperimentOneExportArtifactJSON.make(
            captureJSON: captureJSON,
            powerCycleResult: correlation,
            runtimeBuildIdentity: runtime,
            setup: defaultSetup(),
            preparedAt: Date(timeIntervalSince1970: 1_750_000_100),
            experimentID: experimentID
        )
        let verified = try PassiveBluetoothExperimentOneExportArtifactJSON.verify(artifact.json)

        #expect(artifact.experimentID == experimentID)
        #expect(artifact.selectedPeripheralIdentifier == target.uuidString)
        #expect(artifact.captureByteCount == captureJSON.count)
        #expect(artifact.nembraBuildIdentifier == "Capture Build V14-F1")
        #expect(artifact.nembraBuildInstanceID == buildInstanceID)
        #expect(artifact.nembraBuildCommitSHA == commit)
        #expect(artifact.executableSHA256 == runtime.executableSHA256)

        #expect(verified.experimentID == experimentID)
        #expect(verified.captureJSON == captureJSON)
        #expect(verified.selectedPeripheralIdentifier == target.uuidString)
        #expect(verified.correlationResult == correlation)
        #expect(verified.manifest.schemaVersion == 3)
        #expect(verified.manifest.experimentRecipeID == .es80FingerprintV1)
        #expect(verified.manifest.sourceArtifact.selectedPeripheralIdentifier == target.uuidString)
        #expect(verified.manifest.nembraBuildIdentifier == runtime.buildIdentifier)
        #expect(verified.manifest.nembraBuildInstanceID == runtime.buildInstanceID)
        #expect(verified.manifest.nembraBuildCommitSHA == runtime.sourceCommitSHA)
        #expect(verified.executableSHA256 == runtime.executableSHA256)
    }

    @Test
    func changingEmbeddedCaptureBytesBreaksManifestBinding() throws {
        let artifact = try makeExport()
        var root = try #require(JSONSerialization.jsonObject(with: artifact.json) as? [String: Any])
        let encodedCapture = try #require(root["captureJSON"] as? String)
        var capture = try #require(Data(base64Encoded: encodedCapture))
        capture.append(0x0A)
        root["captureJSON"] = capture.base64EncodedString()
        let tampered = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])

        #expect(throws: PassiveBluetoothStationaryCaptureManifestError.manifestDoesNotMatchCapture) {
            _ = try PassiveBluetoothExperimentOneExportArtifactJSON.verify(tampered)
        }
    }

    @Test
    func changingReplayableCorrelationCannotRelabelManifestTarget() throws {
        let artifact = try makeExport()
        var root = try #require(JSONSerialization.jsonObject(with: artifact.json) as? [String: Any])
        var evidence = try #require(root["correlationEvidence"] as? [String: Any])
        var snapshots = try #require(evidence["observationSnapshots"] as? [[String: Any]])

        for index in [1, 3] {
            var snapshot = snapshots[index]
            var candidates = try #require(snapshot["candidates"] as? [[String: Any]])
            for candidateIndex in candidates.indices {
                if candidates[candidateIndex]["peripheralIdentifier"] as? String == target.uuidString {
                    candidates[candidateIndex]["peripheralIdentifier"] = replacement.uuidString
                }
            }
            snapshot["candidates"] = candidates
            snapshots[index] = snapshot
        }
        evidence["observationSnapshots"] = snapshots
        root["correlationEvidence"] = evidence
        let tampered = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])

        #expect(throws: PassiveBluetoothExperimentOneExportArtifactError.manifestTargetMismatch) {
            _ = try PassiveBluetoothExperimentOneExportArtifactJSON.verify(tampered)
        }
    }

    @Test
    func unknownEnvelopeClaimsFailClosed() throws {
        let artifact = try makeExport()
        var root = try #require(JSONSerialization.jsonObject(with: artifact.json) as? [String: Any])
        root["physicallyVerified"] = true
        let tampered = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])

        #expect(
            throws: PassiveBluetoothExperimentOneExportArtifactError
                .unexpectedExportField("physicallyVerified")
        ) {
            _ = try PassiveBluetoothExperimentOneExportArtifactJSON.verify(tampered)
        }
    }

    @Test
    func runtimeExecutableHashCannotBeReplacedWithNonDigestText() throws {
        let artifact = try makeExport()
        var root = try #require(JSONSerialization.jsonObject(with: artifact.json) as? [String: Any])
        var build = try #require(root["runtimeBuild"] as? [String: Any])
        build["executableSHA256"] = "trusted"
        root["runtimeBuild"] = build
        let tampered = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])

        #expect(
            throws: PassiveBluetoothExperimentOneExportArtifactError
                .invalidExecutableSHA256("trusted")
        ) {
            _ = try PassiveBluetoothExperimentOneExportArtifactJSON.verify(tampered)
        }
    }

    private func makeExport() throws -> PassiveBluetoothExperimentOneExportArtifact {
        try PassiveBluetoothExperimentOneExportArtifactJSON.make(
            captureJSON: makeCapture(),
            powerCycleResult: makeCorrelationResult(),
            runtimeBuildIdentity: makeRuntimeBuildIdentity(),
            setup: defaultSetup(),
            preparedAt: Date(timeIntervalSince1970: 1_750_000_100),
            experimentID: experimentID
        )
    }

    private func makeRuntimeBuildIdentity() throws -> PassiveBluetoothCaptureRuntimeBuildIdentity {
        try PassiveBluetoothCaptureRuntimeBuildIdentityReader.resolveEmbeddedMetadata(
            infoDictionary: [
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildIdentifierInfoDictionaryKey: "Capture Build V14-F1",
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildInstanceIDInfoDictionaryKey: buildInstanceID,
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.sourceCommitSHAInfoDictionaryKey: commit,
            ],
            executableData: Data("exact-field-executable".utf8)
        )
    }

    private func makeCorrelationResult() throws -> PassiveBluetoothPowerCycleObservationResult {
        let series = PassiveBluetoothCandidateObservationSeriesIdentity(
            rawValue: UUID(uuidString: "0F0F0F0F-1111-2222-3333-444444444444")!
        )
        let catalogs: [[PassiveBluetoothCandidateObservationSnapshot.Candidate]] = [
            [.init(id: other, isConnectable: true)],
            [.init(id: other, isConnectable: true), .init(id: target, isConnectable: true)],
            [.init(id: other, isConnectable: true)],
            [.init(id: other, isConnectable: true), .init(id: target, isConnectable: true)],
        ]

        var windows: [PassiveBluetoothPowerCycleObservationWindowReceipt] = []
        var snapshots: [PassiveBluetoothCandidateObservationSnapshot] = []
        for index in PassiveBluetoothPowerCycleObservationPhase.allCases.indices {
            let phase = PassiveBluetoothPowerCycleObservationPhase.allCases[index]
            let sequence = PassiveBluetoothCandidateObservationWindowSequence(rawValue: UInt64(index + 1))
            snapshots.append(try PassiveBluetoothCandidateObservationSnapshot(
                observationSeriesIdentity: series,
                windowSequence: sequence,
                candidates: catalogs[index]
            ))
            windows.append(PassiveBluetoothPowerCycleObservationWindowReceipt(
                phase: phase,
                windowSequence: sequence,
                startedAtUptimeNanoseconds: UInt64(index + 1) * 20_000_000_000,
                endedAtUptimeNanoseconds: UInt64(index + 1) * 20_000_000_000 + 10_000_000_000,
                observedCandidateCount: catalogs[index].count
            ))
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

    private func makeCapture() throws -> Data {
        let startedAt = Date(timeIntervalSince1970: 1_750_000_000)
        var session = try PassiveBluetoothCaptureSession(
            id: UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!,
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