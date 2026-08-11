/// Explicit authority classification for provenance emitted by the passive
/// Capture -> Tuya candidate bridge.
///
/// `PassiveBluetoothCaptureSession` is a validated value, but it is publicly
/// constructible and can be populated by callers with synthetic observations.
/// The bridge therefore preserves software provenance without upgrading that
/// provenance into recorder custody, cryptographic attestation, physical ES80
/// identity, protocol semantics, telemetry truth, command authority, or field GO.
public enum PassiveBluetoothTuyaCandidateProvenanceClass: String, CaseIterable, Codable, Sendable {
    case validatedSoftwareSessionOnly = "validated-software-session-only"
}

public extension PassiveBluetoothTuyaCandidateCaptureContext {
    /// Machine-readable reminder that bridge provenance describes the validated
    /// session supplied to the bridge. It is not proof of how that session was
    /// produced and must never be promoted into physical ES80 authority.
    var provenanceClass: PassiveBluetoothTuyaCandidateProvenanceClass {
        .validatedSoftwareSessionOnly
    }
}
