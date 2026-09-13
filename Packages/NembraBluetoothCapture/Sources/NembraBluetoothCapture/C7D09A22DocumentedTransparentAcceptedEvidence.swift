import Foundation

public extension C7D09A22DocumentedTransparentLivePreflight {
    /// Returns portable documented Smart Life receive evidence only when the exact armed
    /// authenticated generation has crossed the physical transport liveness boundary.
    ///
    /// Unlike `evidenceArtifact()`, which is intentionally useful for diagnostics before the
    /// historical rejection horizon, this accessor is acceptance-scoped: it samples one coherent
    /// package-owned field-attempt cut and exposes bytes only when that same cut proves repeated
    /// documented device-to-app receive plus independent authenticated-session survival beyond the
    /// post-authentication rejection window.
    ///
    /// This remains documented SDK transport evidence. It does not identify the underlying FD50
    /// GATT characteristic and cannot authorize DP semantics, control writes, pairing, reset,
    /// removal, or unbind.
    func acceptedDocumentedTransportEvidenceArtifact() async -> C7D09A22DocumentedTransparentEvidenceArtifact? {
        let evidence = await fieldAttemptEvidence()
        guard evidence.satisfiesDocumentedAuthenticatedTransportAcceptance else {
            return nil
        }
        return evidence.artifact
    }
}
