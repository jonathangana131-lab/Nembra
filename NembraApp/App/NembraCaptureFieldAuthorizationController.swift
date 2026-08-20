import Foundation
import NembraCaptureAppAuthorization

/// Standalone-app adapter around the package-owned authenticated Capture session.
///
/// This type intentionally owns no parallel authority state. The package session remains the
/// single source of truth for manifest validation, signer rendezvous, opaque capability custody,
/// ordered lifecycle admission, sealing, and terminal revocation.
@MainActor
final class NembraCaptureFieldAuthorizationController {
    private let session: AuthenticatedStationaryCaptureAppSession

    init(session: AuthenticatedStationaryCaptureAppSession = .init()) {
        self.session = session
    }

    var stage: AuthenticatedStationaryCaptureAppSession.Stage { session.stage }

    @discardableResult
    func prepareAttempt(
        retainedInstallManifestData: Data
    ) throws -> AuthenticatedStationaryCaptureAppSession.SignerRendezvous {
        try session.prepare(installManifestData: retainedInstallManifestData)
    }

    func authorize(envelopeData: Data) throws {
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
