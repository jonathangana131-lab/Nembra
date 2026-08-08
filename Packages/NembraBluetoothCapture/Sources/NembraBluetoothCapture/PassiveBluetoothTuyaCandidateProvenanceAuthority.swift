import NembraCore

/// The strongest authority the in-memory Tuya candidate bridge can claim for
/// the `PassiveBluetoothCaptureSession` it was given.
///
/// `PassiveBluetoothCaptureSession` and its validated record/event vocabulary
/// are public and caller-constructible in `NembraCore`. Therefore a successful
/// bridge projection proves structural validation and exact mapping within that
/// software session; it does not prove that the session came from Nembra's live
/// recorder, an immutable exported artifact, a field-authorized build, or a
/// physical AOVOPRO ES80.
public enum PassiveBluetoothTuyaCandidateSessionProvenanceAuthority: String, Equatable, Sendable {
    case validatedSoftwareSession
}

public extension PassiveBluetoothTuyaCandidateCaptureContext {
    /// Explicit fail-closed authority label for the bridge input provenance.
    ///
    /// Callers that need artifact/chain-of-custody authority must establish it
    /// separately (for example by validating and hashing the exact retained
    /// capture artifact) and must never infer it from this context alone.
    var sessionProvenanceAuthority: PassiveBluetoothTuyaCandidateSessionProvenanceAuthority {
        .validatedSoftwareSession
    }
}
