import Foundation
import NembraCaptureAppAuthorization

/// Standalone-app adapter around the package-owned authenticated Capture session.
///
/// This type intentionally owns no parallel authority state. The package session remains the
/// single source of truth for manifest validation, signer rendezvous, opaque capability custody,
/// ordered lifecycle admission, sealing, and terminal revocation. Stable manifest and later
/// envelope bytes enter only through the descriptor-bound one-shot app-container inbox.
@MainActor
final class NembraCaptureFieldAuthorizationController {
    enum HandoffProgress: Equatable {
        case waitingForManifest
        case waitingForEnvelope
        case armed
        case lifecycleInProgress
        case sealed
        case revoked
    }

    private let session: AuthenticatedStationaryCaptureAppSession

    init(session: AuthenticatedStationaryCaptureAppSession = .init()) {
        self.session = session
    }

    var stage: AuthenticatedStationaryCaptureAppSession.Stage { session.stage }

    private func prepareAttemptFromInbox()
        throws -> AuthenticatedStationaryCaptureAppSession.SignerRendezvous
    {
        let manifestData = try AuthenticatedStationaryCaptureAuthorizationInbox()
            .takeInstallManifest()
        return try session.prepare(installManifestData: manifestData)
    }

    /// Publishes the exact non-authorizing bytes that should be copied FROM the still-running app
    /// container to the independent field signer. The process-local attempt remains alive inside
    /// `session`; publication does not grant OFF1 or expose the opaque capability. Publication
    /// failure terminally retires the attempt so a consumed manifest/challenge cannot become an
    /// invisible retry path.
    @discardableResult
    func prepareSignerRendezvousDocumentFromInbox() throws -> Data {
        let rendezvous = try prepareAttemptFromInbox()
        do {
            return try AuthenticatedStationaryCaptureSignerRendezvousOutbox()
                .publish(rendezvous)
        } catch {
            session.revoke()
            throw error
        }
    }

    /// Takes the returned signed envelope, retires the exact outbound rendezvous inode, then asks
    /// the package session to verify/consume the envelope. If rendezvous retirement fails, the
    /// attempt is revoked before the envelope can become authority.
    func authorizeFromInbox() throws {
        let outbox = try AuthenticatedStationaryCaptureSignerRendezvousOutbox()
        let envelopeData = try AuthenticatedStationaryCaptureAuthorizationInbox()
            .takeAuthorizationEnvelope()
        do {
            try outbox.retirePublishedRendezvous()
        } catch {
            session.revoke()
            throw error
        }
        try session.acceptEnvelope(envelopeData)
    }

    /// Advances only the non-authorizing app-container handoff that is valid for the current
    /// single-use session stage. A legitimately absent next file is a wait state, not a failure and
    /// not authority. Any present-but-invalid/custody-violating manifest or envelope is propagated
    /// to the caller; verification code remains responsible for terminal revocation where required.
    ///
    /// This seam is intentionally idempotent while waiting: the manifest is consumed exactly once,
    /// then only an envelope can advance the session. It never retries a rejected envelope against
    /// the same challenge and never resets a revoked session.
    @discardableResult
    func advanceInboxHandoffIfAvailable() throws -> HandoffProgress {
        switch session.stage {
        case .idle:
            do {
                _ = try prepareSignerRendezvousDocumentFromInbox()
                return .waitingForEnvelope
            } catch AuthenticatedStationaryCaptureAuthorizationInboxError.missingSubject(let subject)
                where subject == AuthenticatedStationaryCaptureAuthorizationInbox.installManifestFilename {
                return .waitingForManifest
            }

        case .awaitingEnvelope:
            do {
                try authorizeFromInbox()
                return .armed
            } catch AuthenticatedStationaryCaptureAuthorizationInboxError.missingSubject(let subject)
                where subject == AuthenticatedStationaryCaptureAuthorizationInbox.authorizationEnvelopeFilename {
                return .waitingForEnvelope
            }

        case .armed:
            return .armed

        case .off1Started, .authenticationAdmitted, .officialConnectionAdmitted, .observationAdmitted:
            return .lifecycleInProgress

        case .sealed:
            return .sealed

        case .revoked:
            return .revoked
        }
    }

    func admitOFF1Start() throws {
        try session.admitOFF1Start()
    }

    func admitAuthenticationStart() throws {
        try session.admitAuthenticationStart()
    }

    func admitOfficialConnectionStart() throws {
        try session.admitOfficialConnectionStart()
    }

    func admitObservationStart() throws {
        try session.admitObservationStart()
    }

    func sealAfterAcceptedArtifactFreeze() throws {
        try session.sealAfterAcceptedArtifactFreeze()
    }

    /// Revocation is authoritative even if non-authorizing transport cleanup fails. Best-effort
    /// retirement prevents an abandoned rendezvous from blocking the next legitimate field attempt;
    /// a custody failure leaves the stale file in place and therefore still fails closed on publish.
    func revoke() {
        session.revoke()
        try? AuthenticatedStationaryCaptureSignerRendezvousOutbox()
            .retirePublishedRendezvous()
    }
}