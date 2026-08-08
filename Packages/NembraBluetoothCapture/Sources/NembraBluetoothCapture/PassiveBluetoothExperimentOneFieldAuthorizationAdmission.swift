import Foundation

/// The one production package seam from externally delivered field-authorization bytes to an
/// Experiment One admission capability.
///
/// This keeps trust-root selection, running-app identity measurement, signed-envelope verification,
/// exact field-evidence validation, and Experiment One recipe/procedure admission inside the package.
/// App code supplies only opaque envelope bytes; it cannot supply a trust key, runtime identity,
/// build digest, GO Boolean, peripheral identifier, or controller.
///
/// A returned `VerifiedAdmission` is still necessary-but-insufficient for physical execution. The
/// admission-bearing canonical ES80 factory separately requires the final package field gate to be GO.
public enum PassiveBluetoothExperimentOneFieldAuthorizationAdmission {
    public enum AdmissionError: Error, Equatable, Sendable {
        case verifiedAuthorizationNotAdmissible
    }

    /// Verifies one externally delivered authorization envelope against the package-owned production
    /// trust root and this running app, then narrows that verified authority to the Experiment One
    /// recipe/procedure capability consumed by the future field-authorized construction path.
    ///
    /// Until the reviewed production public key is pinned this fails closed with
    /// `authorizationTrustAnchorNotConfigured` from the verifier. It does not mutate the global field
    /// gate, instantiate CoreBluetooth, persist the envelope, or grant physical GO.
    public static func verifyAndAdmitForCurrentApplication(
        _ envelopeData: Data
    ) throws -> PassiveBluetoothExperimentOneFieldExecutionGate.VerifiedAdmission {
        let verified = try PassiveBluetoothCaptureFieldAuthorizationVerifier
            .verifyForCurrentApplication(envelopeData)
        guard let admission = PassiveBluetoothExperimentOneFieldExecutionGate.admit(
            verifiedAuthorization: verified
        ) else {
            throw AdmissionError.verifiedAuthorizationNotAdmissible
        }
        return admission
    }
}
