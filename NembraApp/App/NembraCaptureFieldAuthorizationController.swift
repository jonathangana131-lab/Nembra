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

    func revoke() {
        session.revoke()
    }
}