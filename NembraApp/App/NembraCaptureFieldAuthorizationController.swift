import Foundation
import NembraCaptureAppAuthorization

@MainActor
final class NembraCaptureFieldAuthorizationController {
    enum Error: Swift.Error, Equatable {
        case attemptNotPrepared
        case capabilityNotAuthorized
        case capabilityAlreadyAuthorized
    }

    private let authorizer: AuthenticatedStationaryCaptureAppAuthorizer
    private var retainedInstallManifestData: Data?
    private var preparedAttempt: AuthenticatedStationaryCapturePreparedAttempt?
    private var capabilityGate: AuthenticatedStationaryCaptureCapabilityGate?

    init(authorizer: AuthenticatedStationaryCaptureAppAuthorizer = .init()) {
        self.authorizer = authorizer
    }

    var challengeSHA256: String? { preparedAttempt?.challengeSHA256 }
    var capabilityStage: AuthenticatedStationaryCaptureCapabilityGate.Stage? { capabilityGate?.stage }

    /// Cross-binds the exact retained-install manifest to the running app before exposing the
    /// fresh signer challenge. The returned digest is rendezvous data only, never physical authority.
    @discardableResult
    func prepareAttempt(retainedInstallManifestData: Data) throws -> String {
        abandonUnfinishedAttempt()
        let prepared = try authorizer.beginAttempt(installManifestData: retainedInstallManifestData)
        self.retainedInstallManifestData = retainedInstallManifestData
        preparedAttempt = prepared
        return prepared.challengeSHA256
    }

    /// Verifies the independent post-install envelope through the package-pinned trust root and
    /// keeps the resulting opaque capability private behind the one-attempt lifecycle gate.
    func authorize(envelopeData: Data) throws {
        guard capabilityGate == nil else { throw Error.capabilityAlreadyAuthorized }
        guard let retainedInstallManifestData, let preparedAttempt else {
            throw Error.attemptNotPrepared
        }
        capabilityGate = try authorizer.authorize(
            envelopeData: envelopeData,
            installManifestData: retainedInstallManifestData,
            preparedAttempt: preparedAttempt
        )
    }

    func admitOFF1Start() throws {
        try requireCapabilityGate().admitOFF1Start()
    }

    func admitAuthenticationStart() throws {
        try requireCapabilityGate().admitAuthenticationStart()
    }

    func admitOfficialConnectionStart() throws {
        try requireCapabilityGate().admitOfficialConnectionStart()
    }

    func admitObservationStart() throws {
        try requireCapabilityGate().admitObservationStart()
    }

    func sealAcceptedAttempt() throws {
        try requireCapabilityGate().seal()
    }

    /// Foreground loss, view exit, source-authority loss, cancellation, and any abandoned attempt
    /// retire both the opaque gate and the signer-rendezvous material. A later attempt must start
    /// from a new manifest validation and fresh package-generated challenge.
    func abandonUnfinishedAttempt() {
        capabilityGate?.revoke()
        capabilityGate = nil
        preparedAttempt = nil
        retainedInstallManifestData = nil
    }

    private func requireCapabilityGate() throws -> AuthenticatedStationaryCaptureCapabilityGate {
        guard let capabilityGate else { throw Error.capabilityNotAuthorized }
        return capabilityGate
    }
}
