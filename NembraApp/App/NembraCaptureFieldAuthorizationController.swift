import Foundation
import NembraCaptureAppAuthorization

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
    private let transferDirectoryPreparationError: (any Error)?

    static func prepareAuthorizationTransferDirectoryForFieldTransport() throws {
        try AuthenticatedStationaryCaptureSignerRendezvousOutbox()
            .prepareAuthorizationTransferDirectory()
    }

    init() {
        self.session = AuthenticatedStationaryCaptureAppSession()
        do {
            try Self.prepareAuthorizationTransferDirectoryForFieldTransport()
            self.transferDirectoryPreparationError = nil
        } catch {
            self.transferDirectoryPreparationError = error
        }
    }

    init(session: AuthenticatedStationaryCaptureAppSession) {
        self.session = session
        self.transferDirectoryPreparationError = nil
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
            session.revoke()
            throw error
        }

        do {
            return try session.prepare(installManifestData: manifestData)
        } catch {
            session.revoke()
            throw error
        }
    }

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

    @discardableResult
    func advanceInboxHandoffIfAvailable() throws -> HandoffProgress {
        if let transferDirectoryPreparationError {
            session.revoke()
            throw transferDirectoryPreparationError
        }

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

    func revoke() {
        session.revoke()
        try? AuthenticatedStationaryCaptureSignerRendezvousOutbox()
            .retirePublishedRendezvous()
    }
}
