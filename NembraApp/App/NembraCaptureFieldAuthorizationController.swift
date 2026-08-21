import Foundation
import NembraCaptureAppAuthorization

/// Standalone-app adapter around the package-owned authenticated Capture session.
///
/// This type intentionally owns no parallel authority state. The package session remains the
/// single source of truth for manifest validation, signer rendezvous, opaque capability custody,
/// ordered lifecycle admission, sealing, and terminal revocation. Stable manifest and later
/// envelope bytes enter only through the descriptor-bound one-shot app-container inbox.
/// Complete build metadata may prepare transport; only the package session stages admit OFF1.
/// Exact-head materialization must therefore validate these contracts together before publishing.
/// Touching this adapter intentionally retriggers the sole race-safe materializer after legacy-writer retirement.
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

    /// Root-safe bootstrap for the external app-container transport destination.
    ///
    /// This seam deliberately exists independently of field-build authority so the installed app
    /// can prepare the empty owner-controlled destination before the retained manifest is copied in.
    /// It cannot read a manifest, publish a challenge, accept an envelope, mint/expose a capability,
    /// arm a session, admit OFF1, or touch Bluetooth/Tuya.
    static func prepareAuthorizationTransferDirectoryForFieldTransport() throws {
        try AuthenticatedStationaryCaptureSignerRendezvousOutbox()
            .prepareAuthorizationTransferDirectory()
    }

    init() {
        self.session = AuthenticatedStationaryCaptureAppSession()
        do {
            // Keep the controller-side check as an idempotent custody assertion for the eventual
            // authorized SecureLink flow. CaptureP0Root may call the static bootstrap earlier so
            // first-install transport does not depend on reaching this authority-gated controller.
            try Self.prepareAuthorizationTransferDirectoryForFieldTransport()
            self.transferDirectoryPreparationError = nil
        } catch {
            // Keep bootstrap failure non-authorizing, but remember it so any later authorized
            // handoff fails closed instead of silently consuming subjects through another path.
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

    /// Advances only the app-container handoff that is valid for the current single-use session
    /// stage. Production callers keep this non-authorizing handoff behind complete field-build
    /// metadata; only the package session's independently signed stage can admit OFF1. The earlier
    /// root/controller bootstrap is deliberately narrower: it can create only the empty protected
    /// destination and cannot read a manifest, publish a challenge, arm the session, or admit OFF1.
    ///
    /// A legitimately absent next file is a wait state, not a failure and not authority. Any
    /// present-but-invalid/custody-violating manifest or envelope is propagated to the caller;
    /// verification code remains responsible for terminal revocation where required.
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

    /// Revocation is authoritative even if non-authorizing transport cleanup fails. Best-effort
    /// retirement prevents an abandoned rendezvous from blocking the next legitimate field attempt;
    /// a custody failure leaves the stale file in place and therefore still fails closed on publish.
    func revoke() {
        session.revoke()
        try? AuthenticatedStationaryCaptureSignerRendezvousOutbox()
            .retirePublishedRendezvous()
    }
}
