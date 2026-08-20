import Foundation
import NembraBluetoothCapture

public enum AuthenticatedStationaryCaptureSignerRendezvousDocumentError: Error, Equatable, Sendable {
    case invalidChallenge
    case invalidAttemptClock
    case deadlineOverflow
    case encodingFailed
}

/// Canonical, non-authorizing document exported from the still-running Capture app to the field
/// signer after the exact retained install has been admitted.
///
/// This document is a rendezvous only. It contains no decision, signature, trust root, capability,
/// device identifier, or Bluetooth authority. The independent signer must still bind the challenge
/// to the separately accepted build/evidence/device subjects and the running app must verify the
/// returned envelope against the original process-local attempt.
public enum AuthenticatedStationaryCaptureSignerRendezvousDocument {
    public static let schema = "nembra.es80-authenticated-stationary-signer-rendezvous"
    public static let schemaVersion = 1
    public static let maximumDocumentByteCount = 4_096

    private struct Wire: Codable {
        let schema: String
        let version: Int
        let procedureID: String
        let attemptChallengeSHA256: String
        let attemptStartedAtUnixMilliseconds: Int64
        let authorizationMustExpireByUnixMilliseconds: Int64
    }

    /// Produces the exact bytes copied FROM the running app container to the independent signer.
    /// The deadline mirrors the package verifier's attempt-relative lifetime rule so an offline
    /// signer cannot accidentally create an otherwise valid envelope that this live attempt must
    /// reject as too long-lived.
    public static func encode(
        _ rendezvous: AuthenticatedStationaryCaptureAppSession.SignerRendezvous
    ) throws -> Data {
        guard isCanonicalSHA256(rendezvous.challengeSHA256) else {
            throw AuthenticatedStationaryCaptureSignerRendezvousDocumentError.invalidChallenge
        }
        guard rendezvous.startedAtWallClockUnixMilliseconds > 0 else {
            throw AuthenticatedStationaryCaptureSignerRendezvousDocumentError.invalidAttemptClock
        }
        let lifetime = AuthenticatedStationaryCaptureFieldAuthorizationVerifier
            .maximumAuthorizationLifetimeMilliseconds
        guard rendezvous.startedAtWallClockUnixMilliseconds <= Int64.max - lifetime else {
            throw AuthenticatedStationaryCaptureSignerRendezvousDocumentError.deadlineOverflow
        }
        let deadline = rendezvous.startedAtWallClockUnixMilliseconds + lifetime
        let wire = Wire(
            schema: schema,
            version: schemaVersion,
            procedureID: rendezvous.procedureID,
            attemptChallengeSHA256: rendezvous.challengeSHA256,
            attemptStartedAtUnixMilliseconds: rendezvous.startedAtWallClockUnixMilliseconds,
            authorizationMustExpireByUnixMilliseconds: deadline
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        do {
            let data = try encoder.encode(wire)
            guard !data.isEmpty, data.count <= maximumDocumentByteCount else {
                throw AuthenticatedStationaryCaptureSignerRendezvousDocumentError.encodingFailed
            }
            return data
        } catch let error as AuthenticatedStationaryCaptureSignerRendezvousDocumentError {
            throw error
        } catch {
            throw AuthenticatedStationaryCaptureSignerRendezvousDocumentError.encodingFailed
        }
    }

    private static func isCanonicalSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (0x30 ... 0x39).contains($0) || (0x61 ... 0x66).contains($0)
        }
    }
}
