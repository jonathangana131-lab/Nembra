import CryptoKit
import Foundation

public enum AuthenticatedStationaryCaptureAppSessionError: Error, Equatable, Sendable {
    case invalidTransition
}

/// App-owned, single-use composition for one authenticated-stationary Capture attempt.
///
/// This type owns the prepared attempt, retained manifest bytes, and verifier-minted lifecycle
/// gate. Callers receive only the signer rendezvous facts and ordered transition methods; neither
/// the package capability nor the gate can escape this session.
@MainActor
public final class AuthenticatedStationaryCaptureAppSession {
    public enum Stage: Equatable, Sendable {
        case idle
        case awaitingEnvelope
        case armed
        case off1Started
        case authenticationAdmitted
        case officialConnectionAdmitted
        case observationAdmitted
        case sealed
        case revoked
    }

    public struct SignerRendezvous: Equatable, Sendable {
        public let challengeSHA256: String
        public let startedAtWallClockUnixMilliseconds: Int64
        public let startedAtUptimeNanoseconds: UInt64
        public let procedureID: String
    }

    public private(set) var stage: Stage = .idle

    private let authorizer: AuthenticatedStationaryCaptureAppAuthorizer
    private var preparedAttempt: AuthenticatedStationaryCapturePreparedAttempt?
    private var retainedInstallManifestData: Data?
    private var capabilityGate: AuthenticatedStationaryCaptureCapabilityGate?

    public convenience init() {
        self.init(authorizer: AuthenticatedStationaryCaptureAppAuthorizer())
    }

    package init(authorizer: AuthenticatedStationaryCaptureAppAuthorizer) {
        self.authorizer = authorizer
    }

    /// Validates the exact retained manifest against the application that is actually running and
    /// creates the fresh challenge needed by the independent signer. This does not grant OFF1.
    public func prepare(installManifestData: Data) throws -> SignerRendezvous {
        guard stage == .idle else {
            throw AuthenticatedStationaryCaptureAppSessionError.invalidTransition
        }
        let attempt = try authorizer.beginAttempt(installManifestData: installManifestData)
        preparedAttempt = attempt
        retainedInstallManifestData = Data(installManifestData)
        stage = .awaitingEnvelope
        return SignerRendezvous(
            challengeSHA256: attempt.challengeSHA256,
            startedAtWallClockUnixMilliseconds: attempt.startedAtWallClockUnixMilliseconds,
            startedAtUptimeNanoseconds: attempt.startedAtUptimeNanoseconds,
            procedureID: attempt.procedureID
        )
    }

    /// Consumes the post-install, challenge-bound envelope. Any failure terminally revokes this
    /// attempt so corrected/replayed bytes cannot be retried against the same process-local challenge.
    ///
    /// On success the package returns only a non-authorizing digest receipt derived from the exact
    /// envelope bytes that passed the pinned signature/runtime/replay verifier. The raw capability
    /// remains private to this session. App-container transport may publish this receipt so the field
    /// Mac can prove which exact envelope bytes were consumed despite the inbox's one-shot unlink.
    @discardableResult
    public func acceptEnvelope(
        _ envelopeData: Data
    ) throws -> AuthenticatedStationaryCaptureVerifiedEnvelopeTransportReceipt {
        guard stage == .awaitingEnvelope,
              let preparedAttempt,
              let retainedInstallManifestData else {
            revoke()
            throw AuthenticatedStationaryCaptureAppSessionError.invalidTransition
        }
        do {
            capabilityGate = try authorizer.authorize(
                envelopeData: envelopeData,
                installManifestData: retainedInstallManifestData,
                preparedAttempt: preparedAttempt
            )
            let receipt = AuthenticatedStationaryCaptureVerifiedEnvelopeTransportReceipt(
                envelopeData: envelopeData,
                attemptChallengeSHA256: preparedAttempt.challengeSHA256,
                procedureID: preparedAttempt.procedureID
            )
            self.preparedAttempt = nil
            self.retainedInstallManifestData = nil
            stage = .armed
            return receipt
        } catch {
            revoke()
            throw error
        }
    }

    public func admitOFF1Start() throws {
        guard stage == .armed, let capabilityGate else {
            revoke()
            throw AuthenticatedStationaryCaptureAppSessionError.invalidTransition
        }
        do {
            try capabilityGate.admitOFF1Start()
            stage = .off1Started
        } catch {
            revoke()
            throw error
        }
    }

    public func admitAuthenticationStart() throws {
        guard stage == .off1Started, let capabilityGate else {
            revoke()
            throw AuthenticatedStationaryCaptureAppSessionError.invalidTransition
        }
        do {
            try capabilityGate.admitAuthenticationStart()
            stage = .authenticationAdmitted
        } catch {
            revoke()
            throw error
        }
    }

    public func admitOfficialConnectionStart() throws {
        guard stage == .authenticationAdmitted, let capabilityGate else {
            revoke()
            throw AuthenticatedStationaryCaptureAppSessionError.invalidTransition
        }
        do {
            try capabilityGate.admitOfficialConnectionStart()
            stage = .officialConnectionAdmitted
        } catch {
            revoke()
            throw error
        }
    }

    public func admitObservationStart() throws {
        guard stage == .officialConnectionAdmitted, let capabilityGate else {
            revoke()
            throw AuthenticatedStationaryCaptureAppSessionError.invalidTransition
        }
        do {
            try capabilityGate.admitObservationStart()
            stage = .observationAdmitted
        } catch {
            revoke()
            throw error
        }
    }

    /// Seals authority only after the accepted artifact has already been frozen by the Capture
    /// lifecycle. A sealed session can never be reset into another OFF1 sequence.
    public func sealAfterAcceptedArtifactFreeze() throws {
        guard stage == .observationAdmitted, let capabilityGate else {
            revoke()
            throw AuthenticatedStationaryCaptureAppSessionError.invalidTransition
        }
        do {
            try capabilityGate.seal()
            stage = .sealed
        } catch {
            revoke()
            throw error
        }
    }

    /// Terminally retires any unfinished authority after foreground/view/account/source loss,
    /// cancellation, or other abandonment. A successfully sealed session remains sealed.
    public func revoke() {
        guard stage != .sealed else { return }
        capabilityGate?.revoke()
        capabilityGate = nil
        preparedAttempt = nil
        retainedInstallManifestData = nil
        stage = .revoked
    }
}
