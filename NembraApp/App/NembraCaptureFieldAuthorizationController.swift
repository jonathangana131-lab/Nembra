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

    @discardableResult
    func prepareAttemptFromInbox()
        throws -> AuthenticatedStationaryCaptureAppSession.SignerRendezvous
    {
        let manifestData = try AuthenticatedStationaryCaptureAuthorizationInbox()
            .takeInstallManifest()
        return try session.prepare(installManifestData: manifestData)
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