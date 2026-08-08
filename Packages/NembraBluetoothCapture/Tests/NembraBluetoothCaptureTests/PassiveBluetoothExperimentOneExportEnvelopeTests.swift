import CryptoKit
import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Experiment One export envelope")
struct PassiveBluetoothExperimentOneExportEnvelopeTests {
    private let scooter = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let neighbor = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let otherCandidate = UUID(uuidString: "99999999-8888-7777-6666-555555555555")!
    private let commit = "0123456789abcdef0123456789abcdef01234567"
    private let buildInstanceID = "12345678-90ab-cdef-1234-567890abcdef"

    @Test("round trip preserves exact capture, four-window evidence, manifest v3, and runtime build provenance")
    func roundTrip() throws {
        let capture = try makeCapture()
        let result = try makePowerCycleResult()
        let artifact = PassiveBluetoothExperimentOneCoordinator.FinalizedArtifact(
            captureJSON: capture,
            powerCycleResult: result
        )
        let identity = try runtimeIdentity()

        let encoded = try PassiveBluetoothExperimentOneExportEnvelopeJSON.make(
            finalizedArtifact: artifact,
            runtimeBuildIdentity: identity,
            preparedAt: Date(timeIntervalSince1970: 1_760_000_000),
            setup: setup()
        )
        let verified = try PassiveBluetoothExperimentOneExportEnvelopeJSON.decodeAndVerify(encoded)

        #expect(verified.schemaVersion == 1)
        #expect(verified.experimentRecipeID == .es80FingerprintV1)
        #expect(verified.captureJSON == capture)
        #expect(verified.powerCycleResult == result)
        #expect(verified.powerCycleResult.windows.map(\.phase) == PassiveBluetoothPowerCycleObservationPhase.allCases)
        #expect(verified.stationaryManifest.schemaVersion == 3)
        #expect(verified.stationaryManifest.experimentRecipeID == .es80FingerprintV1)
        #expect(verified.stationaryManifest.sourceArtifact.selectedPeripheralIdentifier == scooter.uuidString)
        #expect(verified.stationaryManifest.nembraBuildIdentifier == identity.buildIdentifier)
        #expect(verified.stationaryManifest.nembraBuildInstanceID == identity.buildInstanceID)
        #expect(verified.stationaryManifest.nembraBuildCommitSHA == identity.sourceCommitSHA)
        #expect(verified.runtimeBuildProvenance.executableSHA256 == identity.executableSHA256)
        #expect(verified.stationaryManifest.sourceArtifact.sha256 == verified.integrityHashes.captureSHA256)
    }

    @Test("mutating sealed capture bytes without rebinding integrity fails closed")
    func captureTamperFails() throws {
        let encoded = try makeEnvelope()
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["captureJSON"] = Data("not the sealed capture".utf8).base64EncodedString()
        let tampered = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])

        #expect(
            throws: PassiveBluetoothExperimentOneExportEnvelopeError.integrityMismatch(field: "captureSHA256")
        ) {
            _ = try PassiveBluetoothExperimentOneExportEnvelopeJSON.decodeAndVerify(tampered)
        }
    }

    @Test("recomputed integrity hash cannot promote altered correlation evidence into authority")
    func correlationEvidenceTamperStillReplays() throws {
        let encoded = try makeEnvelope()
        var root = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let evidenceBase64 = try #require(root["powerCycleEvidenceJSON"] as? String)
        let evidenceData = try #require(Data(base64Encoded: evidenceBase64))
        var evidence = try #require(JSONSerialization.jsonObject(with: evidenceData) as? [String: Any])
        var snapshots = try #require(evidence["snapshots"] as? [[String: Any]])

        // Remove the scooter from ON2 while preserving a syntactically valid four-window artifact.
        var on2 = snapshots[3]
        var candidates = try #require(on2["candidates"] as? [[String: Any]])
        candidates.removeAll { ($0["id"] as? String)?.lowercased() == scooter.uuidString.lowercased() }
        on2["candidates"] = candidates
        snapshots[3] = on2
        evidence["snapshots"] = snapshots

        // Keep the receipt's candidate count internally consistent so replay reaches correlation.
        var windows = try #require(evidence["windows"] as? [[String: Any]])
        windows[3]["observedCandidateCount"] = candidates.count
        evidence["windows"] = windows

        let mutatedEvidence = try JSONSerialization.data(withJSONObject: evidence, options: [.sortedKeys])
        root["powerCycleEvidenceJSON"] = mutatedEvidence.base64EncodedString()
        var hashes = try #require(root["hashes"] as? [String: Any])
        hashes["powerCycleEvidenceSHA256"] = sha256Hex(mutatedEvidence)
        root["hashes"] = hashes
        let tampered = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])

        #expect(throws: PassiveBluetoothExperimentOneExportEnvelopeError.correlationNotUnique) {
            _ = try PassiveBluetoothExperimentOneExportEnvelopeJSON.decodeAndVerify(tampered)
        }
    }

    @Test("unknown envelope fields are rejected instead of silently accepted")
    func unknownFieldFails() throws {
        let encoded = try makeEnvelope()
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["physicalAuthorized"] = true
        let tampered = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])

        #expect(
            throws: PassiveBluetoothExperimentOneExportEnvelopeError.unexpectedField("physicalAuthorized")
        ) {
            _ = try PassiveBluetoothExperimentOneExportEnvelopeJSON.decodeAndVerify(tampered)
        }
    }

    @Test("legacy-permissive 64-character commit cannot masquerade as runtime build provenance")
    func runtimeCommitGrammarFailsClosed() throws {
        let encoded = try makeEnvelope()
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var runtime = try #require(object["runtimeBuildIdentity"] as? [String: Any])
        runtime["sourceCommitSHA"] = String(repeating: "a", count: 64)
        object["runtimeBuildIdentity"] = runtime
        let tampered = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])

        #expect(throws: PassiveBluetoothExperimentOneExportEnvelopeError.invalidRuntimeBuildProvenance) {
            _ = try PassiveBluetoothExperimentOneExportEnvelopeJSON.decodeAndVerify(tampered)
        }
    }

    @Test("ambiguous repeated candidates cannot be exported as a final share artifact")
    func ambiguousCorrelationCannotExport() throws {
        let artifact = PassiveBluetoothExperimentOneCoordinator.FinalizedArtifact(
            captureJSON: try makeCapture(),
            powerCycleResult: try makePowerCycleResult(alsoRepeat: otherCandidate)
        )

        #expect(throws: PassiveBluetoothExperimentOneExportEnvelopeError.correlationNotUnique) {
            _ = try PassiveBluetoothExperimentOneExportEnvelopeJSON.make(
                finalizedArtifact: artifact,
                runtimeBuildIdentity: runtimeIdentity(),
                setup: setup()
            )
        }
    }

    private func makeEnvelope() throws -> Data {
        try PassiveBluetoothExperimentOneExportEnvelopeJSON.make(
            finalizedArtifact: .init(
                captureJSON: makeCapture(),
                powerCycleResult: makePowerCycleResult()
            ),
            runtimeBuildIdentity: runtimeIdentity(),
            preparedAt: Date(timeIntervalSince1970: 1_760_000_000),
            setup: setup()
        )
    }

    private func runtimeIdentity() throws -> PassiveBluetoothCaptureRuntimeBuildIdentity {
        try PassiveBluetoothCaptureRuntimeBuildIdentityReader.resolveEmbeddedMetadata(
            infoDictionary: [
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildIdentifierInfoDictionaryKey:
                    "Capture Build V14-export-envelope",
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildInstanceIDInfoDictionaryKey:
                    buildInstanceID,
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.sourceCommitSHAInfoDictionaryKey:
                    commit,
            ],
            executableData: Data("fixture executable bytes".utf8)
        )
    }

    private func setup() -> PassiveBluetoothStationaryCaptureSetup {
        .init(
            chargerState: .disconnected,
            executionContext: .foregroundUnlockedScreenOn,
            stockAppReferenceSetup: .none
        )
    }

    private func candidate(
        _ id: UUID,
        connectable: Bool? = true
    ) -> PassiveBluetoothCandidateObservationSnapshot.Candidate {
        .init(id: id, isConnectable: connectable)
    }

    private func makePowerCycleResult(
        alsoRepeat second: UUID? = nil
    ) throws -> PassiveBluetoothPowerCycleObservationResult {
        var ledger = PassiveBluetoothPowerCycleObservationLedger(minimumWindowDurationNanoseconds: 1)
        _ = try ledger.completeWindow(
            phase: .firstPoweredOff,
            startedAtUptimeNanoseconds: 10,
            endedAtUptimeNanoseconds: 11,
            candidates: [candidate(neighbor)]
        )
        var onCandidates = [candidate(neighbor), candidate(scooter)]
        if let second { onCandidates.append(candidate(second)) }
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
            candidates: [candidate(neighbor)]
        )
        let completed = try ledger.completeWindow(
            phase: .secondPoweredOn,
            startedAtUptimeNanoseconds: 40,
            endedAtUptimeNanoseconds: 41,
            candidates: onCandidates
        )
        return try #require(completed)
    }

    private func makeCapture() throws -> Data {
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
                peripheralIdentifier: scooter.uuidString,
                serviceUUID: "FFE0",
                isPrimary: true
            )),
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 1,
            receivedAtDate: Date(timeIntervalSince1970: 1_750_000_001)
        )
        try session.append(
            .value(try PassiveBluetoothValueObservation(
                peripheralIdentifier: scooter.uuidString,
                serviceUUID: "FFE0",
                characteristicUUID: "FFE1",
                origin: .subscriptionUpdate,
                payload: Data([0x01, 0x02, 0x03])
            )),
            sequenceNumber: 2,
            receivedAtUptimeNanoseconds: 2,
            receivedAtDate: Date(timeIntervalSince1970: 1_750_000_002)
        )
        return try PassiveBluetoothCaptureJSON.encode(session)
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
