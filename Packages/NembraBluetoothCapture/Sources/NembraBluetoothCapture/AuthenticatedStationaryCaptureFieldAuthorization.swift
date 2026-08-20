import CryptoKit
import Foundation

/// Exact external facts that the independent GO signer must bind to one current attempt.
public struct AuthenticatedStationaryCaptureExternalBindings: Equatable, Sendable {
    public let tuyaDependencyLockSHA256: String
    public let externalBuildRecordSHA256: String
    public let signedBuildEvidenceSHA256: String
    public let finalGORecordSHA256: String
    public let intendedDevicePseudonymSHA256: String

    public init(
        tuyaDependencyLockSHA256: String,
        externalBuildRecordSHA256: String,
        signedBuildEvidenceSHA256: String,
        finalGORecordSHA256: String,
        intendedDevicePseudonymSHA256: String
    ) throws {
        for digest in [
            tuyaDependencyLockSHA256,
            externalBuildRecordSHA256,
            signedBuildEvidenceSHA256,
            finalGORecordSHA256,
            intendedDevicePseudonymSHA256,
        ] where !AuthenticatedStationaryCaptureAuthorizationCoding.isCanonicalSHA256(digest) {
            throw AuthenticatedStationaryCaptureFieldAuthorizationError.invalidBinding
        }
        self.tuyaDependencyLockSHA256 = tuyaDependencyLockSHA256
        self.externalBuildRecordSHA256 = externalBuildRecordSHA256
        self.signedBuildEvidenceSHA256 = signedBuildEvidenceSHA256
        self.finalGORecordSHA256 = finalGORecordSHA256
        self.intendedDevicePseudonymSHA256 = intendedDevicePseudonymSHA256
    }
}

/// One in-memory request attempt. It is deliberately non-Codable and cannot be restored across a
/// process boundary. The challenge is package-generated in production and the monotonic start is
/// checked again when the signed envelope is presented.
public struct AuthenticatedStationaryCaptureAttempt: Sendable {
    public let challengeSHA256: String
    public let startedAtWallClockUnixMilliseconds: Int64
    public let startedAtUptimeNanoseconds: UInt64
    public let externalBindings: AuthenticatedStationaryCaptureExternalBindings

    fileprivate let bundleIdentifier: String
    fileprivate let runtimeBuildIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity

    fileprivate init(
        challengeSHA256: String,
        startedAtWallClockUnixMilliseconds: Int64,
        startedAtUptimeNanoseconds: UInt64,
        externalBindings: AuthenticatedStationaryCaptureExternalBindings,
        bundleIdentifier: String,
        runtimeBuildIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity
    ) {
        self.challengeSHA256 = challengeSHA256
        self.startedAtWallClockUnixMilliseconds = startedAtWallClockUnixMilliseconds
        self.startedAtUptimeNanoseconds = startedAtUptimeNanoseconds
        self.externalBindings = externalBindings
        self.bundleIdentifier = bundleIdentifier
        self.runtimeBuildIdentity = runtimeBuildIdentity
    }
}

/// Stable identity the app's durable, atomic replay store must claim exactly once.
public struct AuthenticatedStationaryCaptureAuthorizationConsumptionRequest: Equatable, Sendable {
    public let requestIdentitySHA256: String
    public let authorizationID: String
    public let attemptChallengeSHA256: String
    public let expiresAtUnixMilliseconds: Int64

    fileprivate init(
        requestIdentitySHA256: String,
        authorizationID: String,
        attemptChallengeSHA256: String,
        expiresAtUnixMilliseconds: Int64
    ) {
        self.requestIdentitySHA256 = requestIdentitySHA256
        self.authorizationID = authorizationID
        self.attemptChallengeSHA256 = attemptChallengeSHA256
        self.expiresAtUnixMilliseconds = expiresAtUnixMilliseconds
    }
}

/// App-owned persistence boundary. Implementations must atomically persist a previously unseen
/// request and return true, or return false when it was consumed before. The package intentionally
/// owns no Keychain storage.
public protocol AuthenticatedStationaryCaptureAuthorizationConsumptionStore: AnyObject {
    func consumeIfUnseen(
        _ request: AuthenticatedStationaryCaptureAuthorizationConsumptionRequest
    ) throws -> Bool
}

/// Opaque one-attempt authority. It is neither Codable nor publicly constructible.
public final class AuthenticatedStationaryCaptureAttemptCapability: @unchecked Sendable {
    public let authorizationID: String
    public let procedureID: String
    public let maximumOFF1Starts: Int
    public let expiresAtUnixMilliseconds: Int64
    public let expiresAtUptimeNanoseconds: UInt64
    public let consumptionRequest: AuthenticatedStationaryCaptureAuthorizationConsumptionRequest

    fileprivate init(
        authorizationID: String,
        expiresAtUnixMilliseconds: Int64,
        expiresAtUptimeNanoseconds: UInt64,
        consumptionRequest: AuthenticatedStationaryCaptureAuthorizationConsumptionRequest
    ) {
        self.authorizationID = authorizationID
        procedureID = AuthenticatedStationaryCaptureFieldAuthorizationVerifier.procedureID
        maximumOFF1Starts = 1
        self.expiresAtUnixMilliseconds = expiresAtUnixMilliseconds
        self.expiresAtUptimeNanoseconds = expiresAtUptimeNanoseconds
        self.consumptionRequest = consumptionRequest
    }
}

public enum AuthenticatedStationaryCaptureFieldAuthorizationError: Error, Equatable, Sendable {
    case authorizationTrustAnchorNotConfigured
    case runtimeBundleIdentifierUnavailable
    case invalidAttemptClock
    case malformedEnvelope
    case malformedPayload
    case inputByteLimitExceeded
    case payloadByteLimitExceeded
    case unexpectedEnvelopeField(String)
    case unexpectedPayloadField(String)
    case duplicateEnvelopeField(String)
    case duplicatePayloadField(String)
    case nonCanonicalEnvelope
    case nonCanonicalPayload
    case invalidBase64
    case invalidPublicKey
    case invalidSignature
    case unsupportedEnvelopeSchema
    case unsupportedPayloadSchema
    case unsupportedProcedure
    case unsupportedDecision
    case invalidAuthorizationID
    case invalidChallenge
    case invalidValidityWindow
    case authorizationNotYetValid
    case authorizationExpired
    case authorizationLifetimeExceeded
    case invalidMaximumOFF1Starts
    case invalidBinding
    case runtimeBindingMismatch
    case currentAttemptMismatch
    case monotonicClockRegressed
    case wallAndMonotonicClockDiverged
    case consumptionStoreFailed
    case authorizationAlreadyConsumed
}

/// Production trust root. It remains nil until an independently controlled P-256 public key is
/// reviewed and pinned in source; neither the envelope, plist, build setting, nor caller selects it.
enum AuthenticatedStationaryCaptureFieldAuthorizationTrustAnchor {
    static let publicKeyX963Representation: Data? = nil
}

public enum AuthenticatedStationaryCaptureFieldAuthorizationVerifier {
    public static let envelopeSchema =
        "nembra.es80-authenticated-stationary-field-authorization-envelope"
    public static let envelopeSchemaVersion = 1
    public static let payloadSchema =
        "nembra.es80-authenticated-stationary-field-authorization"
    public static let payloadSchemaVersion = 1
    public static let procedureID = "ES80-AUTHENTICATED-STATIONARY-v1"
    public static let maximumEnvelopeByteCount = 32_768
    public static let maximumPayloadByteCount = 16_384
    public static let maximumAuthorizationLifetimeMilliseconds: Int64 = 15 * 60 * 1_000
    public static let maximumClockDivergenceMilliseconds: Int64 = 5_000

    private struct EnvelopeWire: Codable {
        let schema: String
        let version: Int
        let payloadBase64: String
        let signatureDERBase64: String
    }

    private struct PayloadWire: Codable {
        let schema: String
        let version: Int
        let procedureID: String
        let decision: String
        let authorizationID: String
        let attemptChallengeSHA256: String
        let issuedAtUnixMilliseconds: Int64
        let notBeforeUnixMilliseconds: Int64
        let expiresAtUnixMilliseconds: Int64
        let maximumOFF1Starts: Int
        let bundleIdentifier: String
        let sourceCommitSHA: String
        let buildIdentifier: String
        let buildInstanceID: String
        let executableSHA256: String
        let infoPlistSHA256: String
        let tuyaDependencyLockSHA256: String
        let externalBuildRecordSHA256: String
        let signedBuildEvidenceSHA256: String
        let finalGORecordSHA256: String
        let intendedDevicePseudonymSHA256: String
    }

    /// Begins a process-local attempt using the running app identity and a random 256-bit challenge.
    public static func makeCurrentApplicationAttempt(
        externalBindings: AuthenticatedStationaryCaptureExternalBindings
    ) throws -> AuthenticatedStationaryCaptureAttempt {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier,
              AuthenticatedStationaryCaptureAuthorizationCoding.isValidBundleIdentifier(
                bundleIdentifier
              ) else {
            throw AuthenticatedStationaryCaptureFieldAuthorizationError
                .runtimeBundleIdentifierUnavailable
        }
        let runtime = try PassiveBluetoothCaptureRuntimeBuildIdentityReader.currentApplication()
        var generator = SystemRandomNumberGenerator()
        let challenge = Data((0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
        return try makeAttempt(
            externalBindings: externalBindings,
            challenge: challenge,
            bundleIdentifier: bundleIdentifier,
            runtimeBuildIdentity: runtime,
            wallClockUnixMilliseconds: currentWallClockUnixMilliseconds(),
            uptimeNanoseconds: currentUptimeNanoseconds()
        )
    }

    /// Verifies against only the package-pinned production key and current clocks/runtime.
    public static func verifyForCurrentApplication(
        _ envelopeData: Data,
        attempt: AuthenticatedStationaryCaptureAttempt,
        consumptionStore: any AuthenticatedStationaryCaptureAuthorizationConsumptionStore
    ) throws -> AuthenticatedStationaryCaptureAttemptCapability {
        guard let publicKey = AuthenticatedStationaryCaptureFieldAuthorizationTrustAnchor
            .publicKeyX963Representation else {
            throw AuthenticatedStationaryCaptureFieldAuthorizationError
                .authorizationTrustAnchorNotConfigured
        }
        guard Bundle.main.bundleIdentifier == attempt.bundleIdentifier else {
            throw AuthenticatedStationaryCaptureFieldAuthorizationError.runtimeBindingMismatch
        }
        let runtime = try PassiveBluetoothCaptureRuntimeBuildIdentityReader.currentApplication()
        guard runtime == attempt.runtimeBuildIdentity else {
            throw AuthenticatedStationaryCaptureFieldAuthorizationError.runtimeBindingMismatch
        }
        return try verify(
            envelopeData,
            attempt: attempt,
            publicKeyX963Representation: publicKey,
            currentRuntimeBuildIdentity: runtime,
            currentBundleIdentifier: attempt.bundleIdentifier,
            nowWallClockUnixMilliseconds: currentWallClockUnixMilliseconds(),
            nowUptimeNanoseconds: currentUptimeNanoseconds(),
            consumptionStore: consumptionStore
        )
    }

    package static func makeAttempt(
        externalBindings: AuthenticatedStationaryCaptureExternalBindings,
        challenge: Data,
        bundleIdentifier: String,
        runtimeBuildIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity,
        wallClockUnixMilliseconds: Int64,
        uptimeNanoseconds: UInt64
    ) throws -> AuthenticatedStationaryCaptureAttempt {
        guard challenge.count == 32,
              wallClockUnixMilliseconds > 0,
              uptimeNanoseconds > 0,
              AuthenticatedStationaryCaptureAuthorizationCoding.isValidBundleIdentifier(
                bundleIdentifier
              ) else {
            throw AuthenticatedStationaryCaptureFieldAuthorizationError.invalidAttemptClock
        }
        return AuthenticatedStationaryCaptureAttempt(
            challengeSHA256: AuthenticatedStationaryCaptureAuthorizationCoding.sha256Hex(challenge),
            startedAtWallClockUnixMilliseconds: wallClockUnixMilliseconds,
            startedAtUptimeNanoseconds: uptimeNanoseconds,
            externalBindings: externalBindings,
            bundleIdentifier: bundleIdentifier,
            runtimeBuildIdentity: runtimeBuildIdentity
        )
    }

    /// Package-only deterministic key/runtime/clock seam for focused tests.
    package static func verify(
        _ envelopeData: Data,
        attempt: AuthenticatedStationaryCaptureAttempt,
        publicKeyX963Representation: Data,
        currentRuntimeBuildIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity,
        currentBundleIdentifier: String,
        nowWallClockUnixMilliseconds: Int64,
        nowUptimeNanoseconds: UInt64,
        consumptionStore: any AuthenticatedStationaryCaptureAuthorizationConsumptionStore
    ) throws -> AuthenticatedStationaryCaptureAttemptCapability {
        guard envelopeData.count <= maximumEnvelopeByteCount else {
            throw AuthenticatedStationaryCaptureFieldAuthorizationError.inputByteLimitExceeded
        }
        let envelope: EnvelopeWire = try decodeCanonical(
            envelopeData,
            maximumByteCount: maximumEnvelopeByteCount,
            allowedKeys: ["schema", "version", "payloadBase64", "signatureDERBase64"],
            duplicateError: { .duplicateEnvelopeField($0) },
            unexpectedError: { .unexpectedEnvelopeField($0) },
            malformedError: .malformedEnvelope,
            nonCanonicalError: .nonCanonicalEnvelope
        )
        guard envelope.schema == envelopeSchema, envelope.version == envelopeSchemaVersion else {
            throw AuthenticatedStationaryCaptureFieldAuthorizationError.unsupportedEnvelopeSchema
        }
        guard let payloadData = AuthenticatedStationaryCaptureAuthorizationCoding
            .decodeCanonicalBase64(envelope.payloadBase64),
              let signatureData = AuthenticatedStationaryCaptureAuthorizationCoding
                .decodeCanonicalBase64(envelope.signatureDERBase64) else {
            throw AuthenticatedStationaryCaptureFieldAuthorizationError.invalidBase64
        }
        guard payloadData.count <= maximumPayloadByteCount else {
            throw AuthenticatedStationaryCaptureFieldAuthorizationError.payloadByteLimitExceeded
        }
        let payload: PayloadWire = try decodeCanonical(
            payloadData,
            maximumByteCount: maximumPayloadByteCount,
            allowedKeys: [
                "schema", "version", "procedureID", "decision", "authorizationID",
                "attemptChallengeSHA256", "issuedAtUnixMilliseconds",
                "notBeforeUnixMilliseconds", "expiresAtUnixMilliseconds", "maximumOFF1Starts",
                "bundleIdentifier", "sourceCommitSHA", "buildIdentifier", "buildInstanceID",
                "executableSHA256",
                "infoPlistSHA256", "tuyaDependencyLockSHA256", "externalBuildRecordSHA256",
                "signedBuildEvidenceSHA256", "finalGORecordSHA256",
                "intendedDevicePseudonymSHA256",
            ],
            duplicateError: { .duplicatePayloadField($0) },
            unexpectedError: { .unexpectedPayloadField($0) },
            malformedError: .malformedPayload,
            nonCanonicalError: .nonCanonicalPayload
        )
        guard payload.schema == payloadSchema, payload.version == payloadSchemaVersion else {
            throw AuthenticatedStationaryCaptureFieldAuthorizationError.unsupportedPayloadSchema
        }
        guard payload.procedureID == procedureID else {
            throw AuthenticatedStationaryCaptureFieldAuthorizationError.unsupportedProcedure
        }
        guard payload.decision == "GO" else {
            throw AuthenticatedStationaryCaptureFieldAuthorizationError.unsupportedDecision
        }
        guard AuthenticatedStationaryCaptureAuthorizationCoding
            .isCanonicalVersion4UUID(payload.authorizationID) else {
            throw AuthenticatedStationaryCaptureFieldAuthorizationError.invalidAuthorizationID
        }
        guard payload.maximumOFF1Starts == 1 else {
            throw AuthenticatedStationaryCaptureFieldAuthorizationError.invalidMaximumOFF1Starts
        }
        let digests = [
            payload.attemptChallengeSHA256, payload.executableSHA256, payload.infoPlistSHA256,
            payload.tuyaDependencyLockSHA256, payload.externalBuildRecordSHA256,
            payload.signedBuildEvidenceSHA256, payload.finalGORecordSHA256,
            payload.intendedDevicePseudonymSHA256,
        ]
        guard digests.allSatisfy(AuthenticatedStationaryCaptureAuthorizationCoding.isCanonicalSHA256) else {
            throw AuthenticatedStationaryCaptureFieldAuthorizationError.invalidBinding
        }

        let publicKey: P256.Signing.PublicKey
        let signature: P256.Signing.ECDSASignature
        do {
            publicKey = try P256.Signing.PublicKey(x963Representation: publicKeyX963Representation)
        } catch {
            throw AuthenticatedStationaryCaptureFieldAuthorizationError.invalidPublicKey
        }
        do {
            signature = try P256.Signing.ECDSASignature(derRepresentation: signatureData)
        } catch {
            throw AuthenticatedStationaryCaptureFieldAuthorizationError.invalidSignature
        }
        guard publicKey.isValidSignature(signature, for: payloadData) else {
            throw AuthenticatedStationaryCaptureFieldAuthorizationError.invalidSignature
        }

        guard currentRuntimeBuildIdentity == attempt.runtimeBuildIdentity,
              currentBundleIdentifier == attempt.bundleIdentifier,
              payload.bundleIdentifier == attempt.bundleIdentifier,
              payload.sourceCommitSHA == attempt.runtimeBuildIdentity.sourceCommitSHA,
              payload.buildIdentifier == attempt.runtimeBuildIdentity.buildIdentifier,
              payload.buildInstanceID == attempt.runtimeBuildIdentity.buildInstanceID,
              payload.executableSHA256 == attempt.runtimeBuildIdentity.executableSHA256,
              payload.infoPlistSHA256 == attempt.runtimeBuildIdentity.infoPlistSHA256 else {
            throw AuthenticatedStationaryCaptureFieldAuthorizationError.runtimeBindingMismatch
        }
        guard payload.attemptChallengeSHA256 == attempt.challengeSHA256,
              payload.tuyaDependencyLockSHA256
                == attempt.externalBindings.tuyaDependencyLockSHA256,
              payload.externalBuildRecordSHA256
                == attempt.externalBindings.externalBuildRecordSHA256,
              payload.signedBuildEvidenceSHA256
                == attempt.externalBindings.signedBuildEvidenceSHA256,
              payload.finalGORecordSHA256 == attempt.externalBindings.finalGORecordSHA256,
              payload.intendedDevicePseudonymSHA256
                == attempt.externalBindings.intendedDevicePseudonymSHA256 else {
            throw AuthenticatedStationaryCaptureFieldAuthorizationError.currentAttemptMismatch
        }

        guard payload.issuedAtUnixMilliseconds > 0,
              payload.notBeforeUnixMilliseconds >= payload.issuedAtUnixMilliseconds,
              payload.expiresAtUnixMilliseconds > payload.notBeforeUnixMilliseconds else {
            throw AuthenticatedStationaryCaptureFieldAuthorizationError.invalidValidityWindow
        }
        guard payload.expiresAtUnixMilliseconds - payload.issuedAtUnixMilliseconds
            <= maximumAuthorizationLifetimeMilliseconds else {
            throw AuthenticatedStationaryCaptureFieldAuthorizationError.authorizationLifetimeExceeded
        }
        guard nowWallClockUnixMilliseconds >= payload.notBeforeUnixMilliseconds else {
            throw AuthenticatedStationaryCaptureFieldAuthorizationError.authorizationNotYetValid
        }
        guard nowWallClockUnixMilliseconds < payload.expiresAtUnixMilliseconds else {
            throw AuthenticatedStationaryCaptureFieldAuthorizationError.authorizationExpired
        }
        guard nowUptimeNanoseconds >= attempt.startedAtUptimeNanoseconds else {
            throw AuthenticatedStationaryCaptureFieldAuthorizationError.monotonicClockRegressed
        }
        let wallElapsed = nowWallClockUnixMilliseconds
            - attempt.startedAtWallClockUnixMilliseconds
        guard wallElapsed >= 0 else {
            throw AuthenticatedStationaryCaptureFieldAuthorizationError.wallAndMonotonicClockDiverged
        }
        let monotonicElapsed = Int64(
            (nowUptimeNanoseconds - attempt.startedAtUptimeNanoseconds) / 1_000_000
        )
        guard abs(wallElapsed - monotonicElapsed) <= maximumClockDivergenceMilliseconds else {
            throw AuthenticatedStationaryCaptureFieldAuthorizationError.wallAndMonotonicClockDiverged
        }
        guard payload.issuedAtUnixMilliseconds + maximumClockDivergenceMilliseconds
            >= attempt.startedAtWallClockUnixMilliseconds else {
            throw AuthenticatedStationaryCaptureFieldAuthorizationError.currentAttemptMismatch
        }

        let remainingMilliseconds = payload.expiresAtUnixMilliseconds
            - nowWallClockUnixMilliseconds
        guard remainingMilliseconds > 0,
              UInt64(remainingMilliseconds) <= (UInt64.max - nowUptimeNanoseconds) / 1_000_000 else {
            throw AuthenticatedStationaryCaptureFieldAuthorizationError.invalidValidityWindow
        }
        let request = AuthenticatedStationaryCaptureAuthorizationConsumptionRequest(
            requestIdentitySHA256: AuthenticatedStationaryCaptureAuthorizationCoding.sha256Hex(
                Data("nembra.es80-authenticated-stationary-consumption/v1\u{0}".utf8) + payloadData
            ),
            authorizationID: payload.authorizationID,
            attemptChallengeSHA256: payload.attemptChallengeSHA256,
            expiresAtUnixMilliseconds: payload.expiresAtUnixMilliseconds
        )
        let consumed: Bool
        do {
            consumed = try consumptionStore.consumeIfUnseen(request)
        } catch {
            throw AuthenticatedStationaryCaptureFieldAuthorizationError.consumptionStoreFailed
        }
        guard consumed else {
            throw AuthenticatedStationaryCaptureFieldAuthorizationError.authorizationAlreadyConsumed
        }
        return AuthenticatedStationaryCaptureAttemptCapability(
            authorizationID: payload.authorizationID,
            expiresAtUnixMilliseconds: payload.expiresAtUnixMilliseconds,
            expiresAtUptimeNanoseconds: nowUptimeNanoseconds
                + UInt64(remainingMilliseconds) * 1_000_000,
            consumptionRequest: request
        )
    }

    private static func decodeCanonical<T: Codable>(
        _ data: Data,
        maximumByteCount: Int,
        allowedKeys: Set<String>,
        duplicateError: (String) -> AuthenticatedStationaryCaptureFieldAuthorizationError,
        unexpectedError: (String) -> AuthenticatedStationaryCaptureFieldAuthorizationError,
        malformedError: AuthenticatedStationaryCaptureFieldAuthorizationError,
        nonCanonicalError: AuthenticatedStationaryCaptureFieldAuthorizationError
    ) throws -> T {
        guard data.count <= maximumByteCount else { throw malformedError }
        if let duplicate = PassiveBluetoothStrictJSON.duplicateTopLevelObjectKey(in: data) {
            throw duplicateError(duplicate)
        }
        let root: [String: Any]
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw malformedError
            }
            root = object
        } catch let error as AuthenticatedStationaryCaptureFieldAuthorizationError {
            throw error
        } catch {
            throw malformedError
        }
        if let unexpected = root.keys.sorted().first(where: { !allowedKeys.contains($0) }) {
            throw unexpectedError(unexpected)
        }
        let value: T
        do {
            value = try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw malformedError
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard try encoder.encode(value) == data else { throw nonCanonicalError }
        return value
    }

    private static func currentWallClockUnixMilliseconds() -> Int64 {
        Int64((Date().timeIntervalSince1970 * 1_000).rounded(.towardZero))
    }

    private static func currentUptimeNanoseconds() -> UInt64 {
        UInt64((ProcessInfo.processInfo.systemUptime * 1_000_000_000).rounded(.towardZero))
    }
}

private enum AuthenticatedStationaryCaptureAuthorizationCoding {
    static func decodeCanonicalBase64(_ value: String) -> Data? {
        guard let data = Data(base64Encoded: value), data.base64EncodedString() == value else {
            return nil
        }
        return data
    }

    static func isCanonicalSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (0x30...0x39).contains($0) || (0x61...0x66).contains($0)
        }
    }

    static func isCanonicalVersion4UUID(_ value: String) -> Bool {
        guard let uuid = UUID(uuidString: value), uuid.uuidString.lowercased() == value else {
            return false
        }
        let bytes = Array(value.utf8)
        return bytes[14] == 0x34 && [0x38, 0x39, 0x61, 0x62].contains(bytes[19])
    }

    static func isValidBundleIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 255,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return value.utf8.allSatisfy {
            (0x30...0x39).contains($0) || (0x41...0x5A).contains($0)
                || (0x61...0x7A).contains($0) || $0 == 0x2D || $0 == 0x2E
        }
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
