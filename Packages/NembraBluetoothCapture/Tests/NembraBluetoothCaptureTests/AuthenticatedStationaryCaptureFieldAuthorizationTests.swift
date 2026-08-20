import CryptoKit
import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Authenticated stationary field authorization")
struct AuthenticatedStationaryCaptureFieldAuthorizationTests {
    private let startedWall: Int64 = 2_000_000
    private let nowWall: Int64 = 2_001_000
    private let startedUptime: UInt64 = 10_000_000_000
    private let nowUptime: UInt64 = 11_000_000_000

    @Test("valid current-procedure GO consumes once and mints the opaque capability")
    func validAuthorization() throws {
        let fixture = try makeFixture()
        let store = MemoryConsumptionStore()
        let capability = try verify(fixture, store: store)

        #expect(capability.authorizationID == fixture.payload["authorizationID"] as? String)
        #expect(capability.procedureID == "ES80-AUTHENTICATED-STATIONARY-v1")
        #expect(capability.maximumOFF1Starts == 1)
        #expect(capability.expiresAtUptimeNanoseconds == 110_000_000_000)
        #expect(store.requests == [capability.consumptionRequest])
        #expect(capability.consumptionRequest.requestIdentitySHA256.utf8.count == 64)
    }

    @Test("production trust anchor is deliberately absent and capability stays opaque")
    func productionSurfaceFailsClosed() throws {
        #expect(
            AuthenticatedStationaryCaptureFieldAuthorizationTrustAnchor
                .publicKeyX963Representation == nil
        )
        let source = try sourceText()
        #expect(source.contains("static let publicKeyX963Representation: Data? = nil"))
        #expect(source.contains("public final class AuthenticatedStationaryCaptureAttemptCapability"))
        #expect(source.contains("fileprivate init("))
        #expect(!source.contains("AuthenticatedStationaryCaptureAttemptCapability: Codable"))
        #expect(!source.contains("Bundle.main.infoDictionary"))
    }

    @Test("a different signer and a malformed key cannot authorize")
    func signerBoundary() throws {
        let fixture = try makeFixture()
        let store = MemoryConsumptionStore()
        #expect(throws: AuthenticatedStationaryCaptureFieldAuthorizationError.invalidSignature) {
            _ = try verify(
                fixture,
                store: store,
                publicKey: P256.Signing.PrivateKey().publicKey.x963Representation
            )
        }
        #expect(throws: AuthenticatedStationaryCaptureFieldAuthorizationError.invalidPublicKey) {
            _ = try verify(fixture, store: store, publicKey: Data([0x01]))
        }
        #expect(store.requests.isEmpty)
    }

    @Test("one signed authorization cannot be replayed")
    func replayFailsClosed() throws {
        let fixture = try makeFixture()
        let store = MemoryConsumptionStore()
        _ = try verify(fixture, store: store)
        #expect(
            throws: AuthenticatedStationaryCaptureFieldAuthorizationError
                .authorizationAlreadyConsumed
        ) {
            _ = try verify(fixture, store: store)
        }
        #expect(store.requests.count == 2)
        #expect(store.requests[0] == store.requests[1])
    }

    @Test("a replay-store failure never mints capability")
    func replayStoreFailure() throws {
        let fixture = try makeFixture()
        let store = MemoryConsumptionStore(throwsOnConsume: true)
        #expect(
            throws: AuthenticatedStationaryCaptureFieldAuthorizationError.consumptionStoreFailed
        ) {
            _ = try verify(fixture, store: store)
        }
    }

    @Test("unknown, duplicate, noncanonical, and oversized envelope bytes fail")
    func strictEnvelope() throws {
        let fixture = try makeFixture()
        let store = MemoryConsumptionStore()
        var unknown = try object(fixture.envelope)
        unknown["fieldAuthorized"] = true
        #expect(
            throws: AuthenticatedStationaryCaptureFieldAuthorizationError
                .unexpectedEnvelopeField("fieldAuthorized")
        ) {
            _ = try verify(fixture, envelope: try json(unknown), store: store)
        }

        let duplicate = Data(
            ("{\"schema\":\"\(AuthenticatedStationaryCaptureFieldAuthorizationVerifier.envelopeSchema)\"," +
                String(decoding: fixture.envelope.dropFirst(), as: UTF8.self)).utf8
        )
        #expect(
            throws: AuthenticatedStationaryCaptureFieldAuthorizationError
                .duplicateEnvelopeField("schema")
        ) {
            _ = try verify(fixture, envelope: duplicate, store: store)
        }

        var trailing = fixture.envelope
        trailing.append(0x0A)
        #expect(throws: AuthenticatedStationaryCaptureFieldAuthorizationError.nonCanonicalEnvelope) {
            _ = try verify(fixture, envelope: trailing, store: store)
        }
        let oversized = Data(
            repeating: 0x20,
            count: AuthenticatedStationaryCaptureFieldAuthorizationVerifier
                .maximumEnvelopeByteCount + 1
        )
        #expect(
            throws: AuthenticatedStationaryCaptureFieldAuthorizationError.inputByteLimitExceeded
        ) {
            _ = try verify(fixture, envelope: oversized, store: store)
        }
        #expect(store.requests.isEmpty)
    }

    @Test("unknown, duplicate, noncanonical, and oversized payload bytes fail")
    func strictPayload() throws {
        let fixture = try makeFixture()
        let store = MemoryConsumptionStore()
        var unknown = fixture.payload
        unknown["physicalGO"] = true
        #expect(
            throws: AuthenticatedStationaryCaptureFieldAuthorizationError
                .unexpectedPayloadField("physicalGO")
        ) {
            _ = try verify(
                try fixture.replacingPayload(json(unknown)),
                store: store
            )
        }

        let canonicalPayload = try json(fixture.payload)
        let duplicate = Data(
            ("{\"decision\":\"GO\"," + String(decoding: canonicalPayload.dropFirst(), as: UTF8.self))
                .utf8
        )
        #expect(
            throws: AuthenticatedStationaryCaptureFieldAuthorizationError
                .duplicatePayloadField("decision")
        ) {
            _ = try verify(try fixture.replacingPayload(duplicate), store: store)
        }

        let pretty = try JSONSerialization.data(
            withJSONObject: fixture.payload,
            options: [.prettyPrinted, .sortedKeys]
        )
        #expect(throws: AuthenticatedStationaryCaptureFieldAuthorizationError.nonCanonicalPayload) {
            _ = try verify(try fixture.replacingPayload(pretty), store: store)
        }

        let oversizedPayload = Data(
            repeating: 0x20,
            count: AuthenticatedStationaryCaptureFieldAuthorizationVerifier
                .maximumPayloadByteCount + 1
        )
        let oversizedEnvelope = try fixture.envelopeFor(
            payload: oversizedPayload,
            signature: Data([0x01])
        )
        #expect(
            throws: AuthenticatedStationaryCaptureFieldAuthorizationError.payloadByteLimitExceeded
        ) {
            _ = try verify(fixture, envelope: oversizedEnvelope, store: store)
        }
        #expect(store.requests.isEmpty)
    }

    @Test("historical envelopes, wrong procedure, non-GO, and OFF1 counts other than one fail")
    func procedureIsClosedWorld() throws {
        let fixture = try makeFixture()
        let store = MemoryConsumptionStore()
        var historicalEnvelope: [String: Any] = [
            "schemaVersion": 2,
            "externalBuildRecordBase64": "",
            "fieldBuildEvidenceRecordBase64": "",
            "authorizationPayloadBase64": "",
            "signatureDERBase64": "",
        ]
        #expect(throws: AuthenticatedStationaryCaptureFieldAuthorizationError.self) {
            _ = try verify(fixture, envelope: try json(historicalEnvelope), store: store)
        }
        historicalEnvelope.removeAll()

        for (field, value, expected) in [
            ("procedureID", "ES80-FINGERPRINT-v1", .unsupportedProcedure),
            ("decision", "NO-GO", .unsupportedDecision),
        ] as [(String, Any, AuthenticatedStationaryCaptureFieldAuthorizationError)] {
            var payload = fixture.payload
            payload[field] = value
            #expect(throws: expected) {
                _ = try verify(try fixture.replacingPayload(json(payload)), store: store)
            }
        }
        var count = fixture.payload
        count["maximumOFF1Starts"] = 2
        #expect(
            throws: AuthenticatedStationaryCaptureFieldAuthorizationError
                .invalidMaximumOFF1Starts
        ) {
            _ = try verify(try fixture.replacingPayload(json(count)), store: store)
        }
    }

    @Test("authorization, challenge, runtime, evidence, and intended-device bindings are exact")
    func exactBindings() throws {
        let fixture = try makeFixture()
        let store = MemoryConsumptionStore()
        var badID = fixture.payload
        badID["authorizationID"] = "aaaaaaaa-bbbb-1ccc-8ddd-eeeeeeeeeeee"
        #expect(
            throws: AuthenticatedStationaryCaptureFieldAuthorizationError.invalidAuthorizationID
        ) {
            _ = try verify(try fixture.replacingPayload(json(badID)), store: store)
        }

        for field in [
            "attemptChallengeSHA256", "tuyaDependencyLockSHA256",
            "externalBuildRecordSHA256", "signedBuildEvidenceSHA256",
            "finalGORecordSHA256", "intendedDevicePseudonymSHA256",
        ] {
            var payload = fixture.payload
            payload[field] = String(repeating: "9", count: 64)
            #expect(
                throws: AuthenticatedStationaryCaptureFieldAuthorizationError.currentAttemptMismatch
            ) {
                _ = try verify(try fixture.replacingPayload(json(payload)), store: store)
            }
        }

        for field in [
            "bundleIdentifier", "sourceCommitSHA", "buildIdentifier", "buildInstanceID",
            "executableSHA256",
            "infoPlistSHA256",
        ] {
            var payload = fixture.payload
            payload[field] = field == "bundleIdentifier"
                ? "com.example.other"
                : String(repeating: "8", count: field == "sourceCommitSHA" ? 40 : 64)
            #expect(
                throws: AuthenticatedStationaryCaptureFieldAuthorizationError.runtimeBindingMismatch
            ) {
                _ = try verify(try fixture.replacingPayload(json(payload)), store: store)
            }
        }
        #expect(store.requests.isEmpty)
    }

    @Test("wall validity and current monotonic chronology fail closed")
    func clockBounds() throws {
        let fixture = try makeFixture()
        let store = MemoryConsumptionStore()

        #expect(
            throws: AuthenticatedStationaryCaptureFieldAuthorizationError.authorizationNotYetValid
        ) {
            _ = try verify(fixture, store: store, nowWall: startedWall)
        }
        #expect(throws: AuthenticatedStationaryCaptureFieldAuthorizationError.authorizationExpired) {
            _ = try verify(fixture, store: store, nowWall: 2_100_000, nowUptime: 110_000_000_000)
        }
        #expect(
            throws: AuthenticatedStationaryCaptureFieldAuthorizationError.monotonicClockRegressed
        ) {
            _ = try verify(fixture, store: store, nowUptime: startedUptime - 1)
        }
        #expect(
            throws: AuthenticatedStationaryCaptureFieldAuthorizationError
                .wallAndMonotonicClockDiverged
        ) {
            _ = try verify(fixture, store: store, nowUptime: nowUptime + 6_000_000_000)
        }

        var longLived = fixture.payload
        longLived["expiresAtUnixMilliseconds"] = 3_000_001
        #expect(
            throws: AuthenticatedStationaryCaptureFieldAuthorizationError
                .authorizationLifetimeExceeded
        ) {
            _ = try verify(try fixture.replacingPayload(json(longLived)), store: store)
        }

        var staleAttempt = fixture.payload
        staleAttempt["issuedAtUnixMilliseconds"] = 2_100_000
        staleAttempt["notBeforeUnixMilliseconds"] = 2_100_000
        staleAttempt["expiresAtUnixMilliseconds"] = 2_900_001
        #expect(
            throws: AuthenticatedStationaryCaptureFieldAuthorizationError
                .authorizationLifetimeExceeded
        ) {
            _ = try verify(try fixture.replacingPayload(json(staleAttempt)), store: store)
        }
        #expect(store.requests.isEmpty)
    }

    private func makeFixture() throws -> Fixture {
        let key = P256.Signing.PrivateKey()
        let runtime = try PassiveBluetoothCaptureRuntimeBuildIdentityReader.resolveEmbeddedMetadata(
            infoDictionary: [
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildIdentifierInfoDictionaryKey:
                    "Capture Build Auth-Test",
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildInstanceIDInfoDictionaryKey:
                    "a1b2c3d4-e5f6-47a8-90bc-def123456789",
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.sourceCommitSHAInfoDictionaryKey:
                    "abcdef0123456789abcdef0123456789abcdef01",
            ],
            executableData: Data("executable".utf8),
            infoPlistData: Data("plist".utf8)
        )
        let bindings = try AuthenticatedStationaryCaptureExternalBindings(
            tuyaDependencyLockSHA256: String(repeating: "1", count: 64),
            externalBuildRecordSHA256: String(repeating: "2", count: 64),
            signedBuildEvidenceSHA256: String(repeating: "3", count: 64),
            finalGORecordSHA256: String(repeating: "4", count: 64),
            intendedDevicePseudonymSHA256: String(repeating: "5", count: 64)
        )
        let attempt = try AuthenticatedStationaryCaptureFieldAuthorizationVerifier.makeAttempt(
            externalBindings: bindings,
            challenge: Data(repeating: 0xA5, count: 32),
            bundleIdentifier: "com.nembra.capture",
            runtimeBuildIdentity: runtime,
            wallClockUnixMilliseconds: startedWall,
            uptimeNanoseconds: startedUptime
        )
        let payload: [String: Any] = [
            "schema": AuthenticatedStationaryCaptureFieldAuthorizationVerifier.payloadSchema,
            "version": 1,
            "procedureID": "ES80-AUTHENTICATED-STATIONARY-v1",
            "decision": "GO",
            "authorizationID": "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee",
            "attemptChallengeSHA256": attempt.challengeSHA256,
            "issuedAtUnixMilliseconds": 2_000_100,
            "notBeforeUnixMilliseconds": 2_000_100,
            "expiresAtUnixMilliseconds": 2_100_000,
            "maximumOFF1Starts": 1,
            "bundleIdentifier": "com.nembra.capture",
            "sourceCommitSHA": runtime.sourceCommitSHA,
            "buildIdentifier": runtime.buildIdentifier,
            "buildInstanceID": runtime.buildInstanceID,
            "executableSHA256": runtime.executableSHA256,
            "infoPlistSHA256": runtime.infoPlistSHA256,
            "tuyaDependencyLockSHA256": bindings.tuyaDependencyLockSHA256,
            "externalBuildRecordSHA256": bindings.externalBuildRecordSHA256,
            "signedBuildEvidenceSHA256": bindings.signedBuildEvidenceSHA256,
            "finalGORecordSHA256": bindings.finalGORecordSHA256,
            "intendedDevicePseudonymSHA256": bindings.intendedDevicePseudonymSHA256,
        ]
        return try Fixture(key: key, runtime: runtime, attempt: attempt, payload: payload)
    }

    private func verify(
        _ fixture: Fixture,
        envelope: Data? = nil,
        store: MemoryConsumptionStore,
        publicKey: Data? = nil,
        nowWall: Int64? = nil,
        nowUptime: UInt64? = nil
    ) throws -> AuthenticatedStationaryCaptureAttemptCapability {
        try AuthenticatedStationaryCaptureFieldAuthorizationVerifier.verify(
            envelope ?? fixture.envelope,
            attempt: fixture.attempt,
            publicKeyX963Representation: publicKey ?? fixture.key.publicKey.x963Representation,
            currentRuntimeBuildIdentity: fixture.runtime,
            currentBundleIdentifier: "com.nembra.capture",
            nowWallClockUnixMilliseconds: nowWall ?? self.nowWall,
            nowUptimeNanoseconds: nowUptime ?? self.nowUptime,
            consumptionStore: store
        )
    }

    private func sourceText() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent(
                "Sources/NembraBluetoothCapture/AuthenticatedStationaryCaptureFieldAuthorization.swift"
            ),
            encoding: .utf8
        )
    }
}

private struct Fixture {
    let key: P256.Signing.PrivateKey
    let runtime: PassiveBluetoothCaptureRuntimeBuildIdentity
    let attempt: AuthenticatedStationaryCaptureAttempt
    let payload: [String: Any]
    var envelope: Data

    init(
        key: P256.Signing.PrivateKey,
        runtime: PassiveBluetoothCaptureRuntimeBuildIdentity,
        attempt: AuthenticatedStationaryCaptureAttempt,
        payload: [String: Any]
    ) throws {
        self.key = key
        self.runtime = runtime
        self.attempt = attempt
        self.payload = payload
        let bytes = try json(payload)
        envelope = try Self.makeEnvelope(payload: bytes, key: key)
    }

    func replacingPayload(_ data: Data) throws -> Fixture {
        var copy = self
        copy.envelope = try Self.makeEnvelope(payload: data, key: key)
        return copy
    }

    func envelopeFor(payload: Data, signature: Data) throws -> Data {
        try json([
            "schema": AuthenticatedStationaryCaptureFieldAuthorizationVerifier.envelopeSchema,
            "version": 1,
            "payloadBase64": payload.base64EncodedString(),
            "signatureDERBase64": signature.base64EncodedString(),
        ])
    }

    private static func makeEnvelope(payload: Data, key: P256.Signing.PrivateKey) throws -> Data {
        let signature = try key.signature(for: payload).derRepresentation
        return try json([
            "schema": AuthenticatedStationaryCaptureFieldAuthorizationVerifier.envelopeSchema,
            "version": 1,
            "payloadBase64": payload.base64EncodedString(),
            "signatureDERBase64": signature.base64EncodedString(),
        ])
    }
}

private final class MemoryConsumptionStore:
    AuthenticatedStationaryCaptureAuthorizationConsumptionStore
{
    private let throwsOnConsume: Bool
    private var seen = Set<String>()
    private(set) var requests: [AuthenticatedStationaryCaptureAuthorizationConsumptionRequest] = []

    init(throwsOnConsume: Bool = false) {
        self.throwsOnConsume = throwsOnConsume
    }

    func consumeIfUnseen(
        _ request: AuthenticatedStationaryCaptureAuthorizationConsumptionRequest
    ) throws -> Bool {
        requests.append(request)
        if throwsOnConsume { throw TestStoreError.failed }
        return seen.insert(request.requestIdentitySHA256).inserted
    }
}

private enum TestStoreError: Error { case failed }

private func json(_ object: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
}

private func object(_ data: Data) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}
