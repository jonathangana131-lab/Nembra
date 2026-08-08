import CryptoKit
import Foundation
import Testing
@testable import NembraBluetoothCapture

struct PassiveBluetoothExperimentOneFinalShareArtifactTests {
    private let target = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let ambient = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let seriesID = UUID(uuidString: "12345678-1234-4234-8234-123456789ABC")!
    private let buildInstanceID = "A1B2C3D4-E5F6-47A8-90BC-DEF123456789"
    private let commit = "abcdef0123456789abcdef0123456789abcdef01"

    @Test
    func finalShareBindsExactSoftwareExportToRecipeProcedureExperimentAndBuildInstance() throws {
        let softwareExport = try makeSoftwareExport()
        let artifact = try PassiveBluetoothExperimentOneFinalShareArtifactCodec.make(
            softwareExport: softwareExport
        )
        let verified = try PassiveBluetoothExperimentOneFinalShareArtifactCodec
            .decodeAndVerify(artifact.json)

        #expect(verified.softwareExport == softwareExport)
        #expect(verified.experimentRecipeID == .es80FingerprintV1)
        #expect(verified.procedureVersion == "V14")
        #expect(verified.buildInstanceID == buildInstanceID.lowercased())
        #expect(verified.softwareExportSHA256.count == 64)
        #expect(sha256Hex(verified.softwareExportJSON) == verified.softwareExportSHA256)

        let manifest = try PassiveBluetoothStationaryCaptureManifestJSON.verifyCaptureBinding(
            manifestJSON: softwareExport.stationaryManifestJSON,
            captureJSON: softwareExport.captureJSON
        )
        #expect(verified.experimentID == manifest.experimentID)
        #expect(artifact.suggestedFilename == "Nembra-ES80-Fingerprint-\(manifest.experimentID.uuidString).json")
    }

    @Test
    func procedureVersionTamperFailsClosed() throws {
        let artifact = try makeArtifact()
        var root = try jsonObject(artifact.json)
        root["procedureVersion"] = "V15"
        let tampered = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])

        #expect(
            throws: PassiveBluetoothExperimentOneFinalShareArtifactError
                .unsupportedProcedureVersion("V15")
        ) {
            _ = try PassiveBluetoothExperimentOneFinalShareArtifactCodec.decodeAndVerify(tampered)
        }
    }

    @Test
    func detachedBuildInstanceCannotReplaceInnerProducedBuildRendezvous() throws {
        let artifact = try makeArtifact()
        var root = try jsonObject(artifact.json)
        root["buildInstanceID"] = "99999999-8888-4777-8666-555555555555"
        let tampered = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])

        #expect(
            throws: PassiveBluetoothExperimentOneFinalShareArtifactError
                .softwareExportBuildInstanceMismatch
        ) {
            _ = try PassiveBluetoothExperimentOneFinalShareArtifactCodec.decodeAndVerify(tampered)
        }
    }

    @Test
    func exactInnerByteTamperBreaksOuterDigestBeforeEvidencePromotion() throws {
        let artifact = try makeArtifact()
        var root = try jsonObject(artifact.json)
        var softwareExportJSON = try #require(
            Data(base64Encoded: try #require(root["softwareExportJSONBase64"] as? String))
        )
        softwareExportJSON.append(0x20)
        root["softwareExportJSONBase64"] = softwareExportJSON.base64EncodedString()
        let tampered = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])

        #expect(
            throws: PassiveBluetoothExperimentOneFinalShareArtifactError
                .softwareExportDigestMismatch
        ) {
            _ = try PassiveBluetoothExperimentOneFinalShareArtifactCodec.decodeAndVerify(tampered)
        }
    }

    @Test
    func recomputingOuterDigestCannotBypassInnerClosedWorldAuthorityFence() throws {
        let artifact = try makeArtifact()
        var root = try jsonObject(artifact.json)
        let originalInner = try #require(
            Data(base64Encoded: try #require(root["softwareExportJSONBase64"] as? String))
        )
        var inner = try jsonObject(originalInner)
        inner["fieldAuthorized"] = true
        let forgedInner = try JSONSerialization.data(withJSONObject: inner, options: [.sortedKeys])
        root["softwareExportJSONBase64"] = forgedInner.base64EncodedString()
        root["softwareExportSHA256"] = sha256Hex(forgedInner)
        let tampered = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])

        #expect(
            throws: PassiveBluetoothExperimentOneSoftwareExportError
                .unexpectedWireField("fieldAuthorized")
        ) {
            _ = try PassiveBluetoothExperimentOneFinalShareArtifactCodec.decodeAndVerify(tampered)
        }
    }

    @Test
    func authorityLookingOuterFieldIsRejectedRatherThanIgnored() throws {
        let artifact = try makeArtifact()
        var root = try jsonObject(artifact.json)
        root["physicalGO"] = true
        let tampered = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])

        #expect(
            throws: PassiveBluetoothExperimentOneFinalShareArtifactError
                .unexpectedWireField("physicalGO")
        ) {
            _ = try PassiveBluetoothExperimentOneFinalShareArtifactCodec.decodeAndVerify(tampered)
        }
    }

    @Test
    func validFinalShareContainsProcedureProvenanceButNoPhysicalAuthorizationField() throws {
        let artifact = try makeArtifact()
        let root = try jsonObject(artifact.json)

        #expect(root["procedureVersion"] as? String == "V14")
        #expect(root["experimentRecipeID"] as? String == "ES80-FINGERPRINT-v1")
        #expect(root["buildInstanceID"] as? String == buildInstanceID.lowercased())
        #expect(root["fieldAuthorized"] == nil)
        #expect(root["physicalGO"] == nil)
        #expect(root["permitsPhysicalProcedure"] == nil)
    }

    @Test
    func duplicateTopLevelSchemaVersionIsRejectedBeforeFinalShareDecode() throws {
        let artifact = try makeArtifact()
        let tampered = try injectingDuplicateTopLevelField(
            "schemaVersion",
            jsonValue: "999",
            into: artifact.json
        )

        #expect(
            throws: PassiveBluetoothExperimentOneFinalShareArtifactError.malformedWireData
        ) {
            _ = try PassiveBluetoothExperimentOneFinalShareArtifactCodec.decodeAndVerify(tampered)
        }
    }

    @Test
    func duplicateTopLevelSchemaVersionIsRejectedBeforeSoftwareExportDecode() throws {
        let softwareExport = try makeSoftwareExport()
        let json = try PassiveBluetoothExperimentOneSoftwareExportCodec.encode(
            softwareExport,
            prettyPrinted: false
        )
        let tampered = try injectingDuplicateTopLevelField(
            "schemaVersion",
            jsonValue: "999",
            into: json
        )

        #expect(
            throws: PassiveBluetoothExperimentOneSoftwareExportError.malformedWireData
        ) {
            _ = try PassiveBluetoothExperimentOneSoftwareExportCodec.decodeAndVerify(tampered)
        }
    }

    private func makeArtifact() throws -> PassiveBluetoothExperimentOneFinalShareArtifact {
        try PassiveBluetoothExperimentOneFinalShareArtifactCodec.make(
            softwareExport: makeSoftwareExport()
        )
    }

    private func makeSoftwareExport() throws -> PassiveBluetoothExperimentOneSoftwareExport {
        try PassiveBluetoothExperimentOneSoftwareExportCodec.make(
            captureJSON: makeCapture(),
            powerCycleResult: makePowerCycleResult(),
            runtimeBuildIdentity: makeRuntimeIdentity(),
            setup: .init(
                chargerState: .disconnected,
                executionContext: .foregroundUnlockedScreenOn,
                stockAppReferenceSetup: .none
            )
        )
    }

    private func makeRuntimeIdentity() throws -> PassiveBluetoothCaptureRuntimeBuildIdentity {
        try PassiveBluetoothCaptureRuntimeBuildIdentityReader.resolveEmbeddedMetadata(
            infoDictionary: [
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildIdentifierInfoDictionaryKey:
                    "Capture Build V14-abcdef012345",
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildInstanceIDInfoDictionaryKey:
                    buildInstanceID,
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.sourceCommitSHAInfoDictionaryKey:
                    commit,
            ],
            executableData: Data("final-share-test-executable".utf8)
        )
    }

    private func makePowerCycleResult() throws -> PassiveBluetoothPowerCycleObservationResult {
        let authority = PassiveBluetoothCandidateObservationSeriesIdentity(rawValue: seriesID)
        let duration = PassiveBluetoothExperimentOneCapturePolicy.minimumPowerCycleWindowDurationNanoseconds
        var receipts: [PassiveBluetoothPowerCycleObservationWindowReceipt] = []
        var snapshots: [PassiveBluetoothCandidateObservationSnapshot] = []

        for (index, phase) in PassiveBluetoothPowerCycleObservationPhase.allCases.enumerated() {
            let sequence = PassiveBluetoothCandidateObservationWindowSequence(rawValue: UInt64(index + 1))
            var candidates = [
                PassiveBluetoothCandidateObservationSnapshot.Candidate(
                    id: ambient,
                    isConnectable: true
                ),
            ]
            if phase.operatorExpectedPowerOn {
                candidates.append(.init(id: target, isConnectable: true))
            }
            let snapshot = try PassiveBluetoothCandidateObservationSnapshot(
                observationSeriesIdentity: authority,
                windowSequence: sequence,
                candidates: candidates
            )
            snapshots.append(snapshot)
            let start = UInt64(index) * 20_000_000_000 + 1_000
            receipts.append(.init(
                phase: phase,
                windowSequence: sequence,
                startedAtUptimeNanoseconds: start,
                endedAtUptimeNanoseconds: start + duration,
                observedCandidateCount: snapshot.candidates.count
            ))
        }

        let correlation = PassiveBluetoothPowerCycleTargetCorrelation.assess(
            firstOff: snapshots[0],
            firstOn: snapshots[1],
            secondOff: snapshots[2],
            secondOn: snapshots[3]
        )
        return .init(
            windows: receipts,
            observationSnapshots: snapshots,
            correlation: correlation
        )
    }

    private func makeCapture() throws -> Data {
        let startedAt = Date(timeIntervalSince1970: 1_750_000_000)
        let service = PassiveBluetoothCaptureRecord(
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 1,
            receivedAtDate: startedAt,
            event: .service(
                try PassiveBluetoothServiceObservation(
                    peripheralIdentifier: target.uuidString,
                    serviceUUID: "FFE0",
                    isPrimary: true
                )
            )
        )
        let characteristic = PassiveBluetoothCaptureRecord(
            sequenceNumber: 2,
            receivedAtUptimeNanoseconds: 2,
            receivedAtDate: startedAt.addingTimeInterval(1),
            event: .characteristic(
                try PassiveBluetoothCharacteristicObservation(
                    peripheralIdentifier: target.uuidString,
                    serviceUUID: "FFE0",
                    characteristicUUID: "FFE1",
                    properties: [.notify]
                )
            )
        )
        let value = PassiveBluetoothCaptureRecord(
            sequenceNumber: 3,
            receivedAtUptimeNanoseconds: 3,
            receivedAtDate: startedAt.addingTimeInterval(2),
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
            recordSequenceWatermark: 3,
            observedAtUptimeNanoseconds: readyUptime,
            observedAtDate: startedAt.addingTimeInterval(3)
        )
        let horizon = PassiveBluetoothObservationBoundary(
            kind: .observationHorizon,
            recordSequenceWatermark: 3,
            observedAtUptimeNanoseconds:
                readyUptime + PassiveBluetoothExperimentOneCapturePolicy.minimumPostReadyObservationDurationNanoseconds,
            observedAtDate: startedAt.addingTimeInterval(63)
        )
        let session = try PassiveBluetoothCaptureSession(
            id: UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!,
            vehicleIdentity: VehicleIdentity(
                manufacturer: "AOVOPRO",
                model: "ES80",
                displayName: "AOVOPRO ES80",
                protocolFamily: "unverified-tuya"
            ),
            startedAt: startedAt,
            records: [service, characteristic, value],
            observationBoundaries: [ready, horizon]
        )
        return try PassiveBluetoothCaptureJSON.encode(session)
    }

    private func injectingDuplicateTopLevelField(
        _ field: String,
        jsonValue: String,
        into data: Data
    ) throws -> Data {
        var text = try #require(String(data: data, encoding: .utf8))
        let opening = try #require(text.firstIndex(of: "{"))
        let insertion = text.index(after: opening)
        text.insert(contentsOf: "\"\(field)\":\(jsonValue),", at: insertion)
        return Data(text.utf8)
    }

    private func jsonObject(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
