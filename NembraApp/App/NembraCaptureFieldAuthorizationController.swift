import Foundation
import NembraCaptureAppAuthorization

/// Standalone-app adapter around the package-owned authenticated Capture session.
///
/// This type intentionally owns no parallel authority state. The package session remains the
/// single source of truth for manifest validation, signer rendezvous, opaque capability custody,
/// ordered lifecycle admission, sealing, and terminal revocation. Stable manifest and later
/// envelope bytes enter only through the descriptor-bound one-shot app-container inbox. A prepared
/// signer rendezvous is atomically published to the same app-container handoff directory so the
/// field Mac can copy exact canonical bytes FROM the still-running app.
@MainActor
final class NembraCaptureFieldAuthorizationController {
    private let session: AuthenticatedStationaryCaptureAppSession

    init(session: AuthenticatedStationaryCaptureAppSession = .init()) {
        self.session = session
    }

    var stage: AuthenticatedStationaryCaptureAppSession.Stage { session.stage }

    @discardableResult
    func prepareAttemptFromInbox()
        throws -> AuthenticatedStationaryCaptureAppSession.SignerRendezvous
    {
        let manifestData = try AuthenticatedStationaryCaptureAuthorizationInbox()
            .takeInstallManifest()
        let rendezvous = try session.prepare(installManifestData: manifestData)
        do {
            try AuthenticatedStationaryCaptureSignerRendezvousOutbox().publish(rendezvous)
            return rendezvous
        } catch {
            // An unpublished challenge has no supported signer rendezvous. Revoke this process-local
            // attempt so hidden awaiting-envelope authority cannot survive a failed file handoff.
            session.revoke()
            throw error
        }
    }

    /// Compatibility/testing view of the exact bytes already published by `prepareAttemptFromInbox`.
    /// Production field transport reads the atomic app-container file rather than caller-owned Data.
    func prepareSignerRendezvousDocumentFromInbox() throws -> Data {
        let rendezvous = try prepareAttemptFromInbox()
        return try AuthenticatedStationaryCaptureSignerRendezvousDocument.encode(rendezvous)
    }

    func authorizeFromInbox() throws {
        let envelopeData = try AuthenticatedStationaryCaptureAuthorizationInbox()
            .takeAuthorizationEnvelope()
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