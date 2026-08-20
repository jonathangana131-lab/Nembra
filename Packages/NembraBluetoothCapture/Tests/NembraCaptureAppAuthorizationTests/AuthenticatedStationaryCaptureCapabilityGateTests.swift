import CryptoKit
import Foundation
import Testing
@testable import NembraBluetoothCapture
@testable import NembraCaptureAppAuthorization

@Suite("Authenticated stationary capability lifecycle gate")
@MainActor
struct AuthenticatedStationaryCaptureCapabilityGateTests {
    @Test("one verified capability advances only through the accepted physical sequence")
    func acceptedSequence() throws {
        let capability = try makeCapability()
        let clock = GateTestClock(wall: 2_001_000, uptime: 11_000_000_000)
        let gate = makeGate(capability: capability, clock: clock)

        #expect(gate.stage == .armed)
        try gate.admitOFF1Start()
        #expect(gate.stage == .off1Started)
        try gate.admitAuthenticationStart()
        #expect(gate.stage == .authenticationAdmitted)
        try gate.admitOfficialConnectionStart()
        #expect(gate.stage == .officialConnectionAdmitted)
        try gate.admitObservationStart()
        #expect(gate.stage == .observationAdmitted)
        try gate.seal()
        #expect(gate.stage == .sealed)
    }

    @Test("OFF1 cannot be started twice and later stages cannot be skipped")
    func orderAndSingleUse() throws {
        let capability = try makeCapability()
        let clock = GateTestClock(wall: 2_001_000, uptime: 11_000_000_000)
        let gate = makeGate(capability: capability, clock: clock)

        #expect(throws: AuthenticatedStationaryCaptureCapabilityGateError.invalidTransition) {
            try gate.admitAuthenticationStart()
        }
        #expect(gate.stage == .armed)

        try gate.admitOFF1Start()
        #expect(throws: AuthenticatedStationaryCaptureCapabilityGateError.invalidTransition) {
            try gate.admitOFF1Start()
        }
        #expect(throws: AuthenticatedStationaryCaptureCapabilityGateError.invalidTransition) {
            try gate.admitOfficialConnectionStart()
        }
        #expect(gate.stage == .off1Started)
    }

    @Test("revocation is terminal across every later boundary")
    func revocationIsTerminal() throws {
        let capability = try makeCapability()
        let clock = GateTestClock(wall: 2_001_000, uptime: 11_000_000_000)
        let gate = makeGate(capability: capability, clock: clock)

        try gate.admitOFF1Start()
        gate.revoke()
        #expect(gate.stage == .revoked)
        #expect(throws: AuthenticatedStationaryCaptureCapabilityGateError.authorizationRevoked) {
            try gate.admitAuthenticationStart()
        }
        #expect(gate.stage == .revoked)
    }

    @Test("expired authority cannot begin OFF1 and retires itself")
    func expiryBeforeOFF1() throws {
        let capability = try makeCapability()
        let clock = GateTestClock(
            wall: capability.expiresAtUnixMilliseconds + 1,
            uptime: capability.expiresAtUptimeNanoseconds + 1
        )
        let gate = makeGate(capability: capability, clock: clock)

        #expect(throws: AuthenticatedStationaryCaptureCapabilityGateError.authorizationExpired) {
            try gate.admitOFF1Start()
        }
        #expect(gate.stage == .revoked)
    }

    @Test("expiry is rechecked after OFF1 instead of becoming immortal")
    func expiryAfterOFF1() throws {
        let capability = try makeCapability()
        let clock = GateTestClock(wall: 2_001_000, uptime: 11_000_000_000)
        let gate = makeGate(capability: capability, clock: clock)

        try gate.admitOFF1Start()
        clock.wall = capability.expiresAtUnixMilliseconds + 1
        clock.uptime = capability.expiresAtUptimeNanoseconds + 1

        #expect(throws: AuthenticatedStationaryCaptureCapabilityGateError.authorizationExpired) {
            try gate.admitAuthenticationStart()
        }
        #expect(gate.stage == .revoked)
    }

    @Test("exact verifier wall and monotonic expiry instants are already expired")
    func exactExpiryBoundariesAreExclusive() throws {
        let capability = try makeCapability()

        let wallClock = GateTestClock(wall: 2_001_000, uptime: 11_000_000_000)
        let wallGate = makeGate(capability: capability, clock: wallClock)
        try wallGate.admitOFF1Start()
        wallClock.wall = capability.expiresAtUnixMilliseconds
        #expect(throws: AuthenticatedStationaryCaptureCapabilityGateError.authorizationExpired) {
            try wallGate.admitAuthenticationStart()
        }
        #expect(wallGate.stage == .revoked)

        let uptimeClock = GateTestClock(wall: 2_001_000, uptime: 11_000_000_000)
        let uptimeGate = makeGate(capability: capability, clock: uptimeClock)
        try uptimeGate.admitOFF1Start()
        uptimeClock.uptime = capability.expiresAtUptimeNanoseconds
        #expect(throws: AuthenticatedStationaryCaptureCapabilityGateError.authorizationExpired) {
            try uptimeGate.admitAuthenticationStart()
        }
        #expect(uptimeGate.stage == .revoked)
    }

    @Test("gate source never exposes or reconstructs the opaque verifier capability")
    func sourceContract() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/NembraCaptureAppAuthorization/AuthenticatedStationaryCaptureCapabilityGate.swift"
            ),
            encoding: .utf8
        )

        #expect(source.contains("private let capability: AuthenticatedStationaryCaptureAttemptCapability"))
        #expect(!source.contains("var capability:"))
        #expect(!source.contains("func capability"))
        #expect(!source.contains("AuthenticatedStationaryCaptureAttemptCapability("))
        #expect(source.contains("func revoke()"))
        #expect(source.contains("try validateCapabilityIsCurrent()"))
        #expect(source.contains("nowWall < capability.expiresAtUnixMilliseconds"))
        #expect(source.contains("nowUptime < capability.expiresAtUptimeNanoseconds"))
        #expect(!source.contains("nowWall <= capability.expiresAtUnixMilliseconds"))
        #expect(!source.contains("nowUptime <= capability.expiresAtUptimeNanoseconds"))
    }

    private func makeGate(
        capability: AuthenticatedStationaryCaptureAttemptCapability,
        clock: GateTestClock
    ) -> AuthenticatedStationaryCaptureCapabilityGate {
        AuthenticatedStationaryCaptureCapabilityGate(
            capability: capability,
            wallClockUnixMilliseconds: { clock.wall },
            uptimeNanoseconds: { clock.uptime }
        )
    }

    private func makeCapability() throws -> AuthenticatedStationaryCaptureAttemptCapability {
        let key = P256.Signing.PrivateKey()
        let runtime = try PassiveBluetoothCaptureRuntimeBuildIdentityReader.resolveEmbeddedMetadata(
            infoDictionary: [
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildIdentifierInfoDictionaryKey:
                    "Capture Build Capability-Gate-Test",
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildInstanceIDInfoDictionaryKey:
                    "b1b2c3d4-e5f6-47a8-90bc-def123456789",
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
            wallClockUnixMilliseconds: 2_000_000,
            uptimeNanoseconds: 10_000_000_000
        )
        let payload: [String: Any] = [
            "schema": AuthenticatedStationaryCaptureFieldAuthorizationVerifier.payloadSchema,
            "version": 1,
            "procedureID": AuthenticatedStationaryCaptureFieldAuthorizationVerifier.procedureID,
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
        let payloadData = try canonicalJSON(payload)
        let signature = try key.signature(for: payloadData).derRepresentation
        let envelope = try canonicalJSON([
            "schema": AuthenticatedStationaryCaptureFieldAuthorizationVerifier.envelopeSchema,
            "version": 1,
            "payloadBase64": payloadData.base64EncodedString(),
            "signatureDERBase64": signature.base64EncodedString(),
        ])

        return try AuthenticatedStationaryCaptureFieldAuthorizationVerifier.verify(
            envelope,
            attempt: attempt,
            publicKeyX963Representation: key.publicKey.x963Representation,
            currentRuntimeBuildIdentity: runtime,
            currentBundleIdentifier: "com.nembra.capture",
            nowWallClockUnixMilliseconds: 2_001_000,
            nowUptimeNanoseconds: 11_000_000_000,
            consumptionStore: GateMemoryConsumptionStore()
        )
    }
}

private final class GateTestClock: @unchecked Sendable {
    var wall: Int64
    var uptime: UInt64

    init(wall: Int64, uptime: UInt64) {
        self.wall = wall
        self.uptime = uptime
    }
}

private final class GateMemoryConsumptionStore:
    AuthenticatedStationaryCaptureAuthorizationConsumptionStore
{
    private var seen = Set<String>()

    func consumeIfUnseen(
        _ request: AuthenticatedStationaryCaptureAuthorizationConsumptionRequest
    ) throws -> Bool {
        seen.insert(request.requestIdentitySHA256).inserted
    }
}

private func canonicalJSON(_ object: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
}
