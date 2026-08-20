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

    init() {
        self.session = AuthenticatedStationaryCaptureAppSession()
    }

    init(session: AuthenticatedStationaryCaptureAppSession) {
        self.session = session
    }

    var stage: AuthenticatedStationaryCaptureAppSession.Stage { session.stage }

    private func prepareAttemptFromInbox()
        throws -> AuthenticatedStationaryCaptureAppSession.SignerRendezvous
    {
        let manifestData: Data
        do {
            manifestData = try AuthenticatedStationaryCaptureAuthorizationInbox()
                .takeInstallManifest()
        } catch AuthenticatedStationaryCaptureAuthorizationInboxError.missingSubject(let subject)
            where subject == AuthenticatedStationaryCaptureAuthorizationInbox.installManifestFilename {
            throw AuthenticatedStationaryCaptureAuthorizationInboxError.missingSubject(subject)
        } catch {
            // Once a manifest path is present but custody cannot prove exactly one trusted subject,
            // this controller lifetime is terminal. Do not allow a replacement manifest to turn a
            // failed physical-field handoff into an invisible retry.
            session.revoke()
            throw error
        }

        do {
            return try session.prepare(installManifestData: manifestData)
        } catch {
            // `takeInstallManifest()` has already retired the descriptor-bound manifest inode. If
            // canonical/runtime cross-binding rejects those consumed bytes, the attempt must remain
            // terminal rather than accepting replacement bytes in the same controller lifetime.
            session.revoke()
            throw error
        }
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
    /// the package session to verify/consume the envelope. Exact absence remains retryable because
    /// no signed subject has arrived. Any other handoff/custody/retirement/verification failure is
    /// terminal so replacement bytes cannot inherit the same process-local challenge.
    func authorizeFromInbox() throws {
        do {
            let outbox = try AuthenticatedStationaryCaptureSignerRendezvousOutbox()
            let envelopeData = try AuthenticatedStationaryCaptureAuthorizationInbox()
                .takeAuthorizationEnvelope()
            try outbox.retirePublishedRendezvous()
            try session.acceptEnvelope(envelopeData)
        } catch AuthenticatedStationaryCaptureAuthorizationInboxError.missingSubject(let subject)
            where subject == AuthenticatedStationaryCaptureAuthorizationInbox.authorizationEnvelopeFilename {
            throw AuthenticatedStationaryCaptureAuthorizationInboxError.missingSubject(subject)
        } catch {
            session.revoke()
            throw error
        }
    }

    /// Advances only the non-authorizing app-container handoff that is valid for the current
    /// single-use session stage. A legitimately absent next file is a wait state, not a failure and
    /// not authority. Any present-but-invalid/custody-violating manifest or envelope is propagated
    /// to the caller; verification code remains responsible for terminal revocation where required.
    ///
    /// This seam is intentionally idempotent while waiting: an idle authoritative handoff first
    /// provisions the exact owner-controlled directory external `appDataContainer` transport may
    /// target, the manifest is consumed exactly once, then only an envelope can advance the session.
    /// It never retries a rejected envelope against the same challenge and never resets a revoked
    /// session. Directory preparation failure is terminal for this controller lifetime.
    @discardableResult
    func advanceInboxHandoffIfAvailable() throws -> HandoffProgress {
        switch session.stage {
        case .idle:
            do {
                try AuthenticatedStationaryCaptureSignerRendezvousOutbox()
                    .prepareAuthorizationTransferDirectory()
            } catch {
                session.revoke()
                throw error
            }

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
