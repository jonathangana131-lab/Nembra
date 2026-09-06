import Foundation

/// Canonical, semantics-free presentation helpers for authenticated physical evidence.
///
/// UI code must not reimplement the physical timing boundary. In particular, evidence exactly
/// at the historical 30-second rejection boundary is still insufficient; acceptance begins at
/// the package-owned first-valid instant encoded by the preflight threshold.
public enum TuyaAuthenticatedReadOnlyPresentation {
    public static func applicationEvidenceSurvivedHistoricalWindow(
        _ snapshot: TuyaAuthenticatedReadOnlyPreflightSnapshot
    ) -> Bool {
        guard let authenticatedAt = snapshot.authenticatedAtUptimeNanoseconds,
              let latestPayload = snapshot.latestApplicationPayloadUptimeNanoseconds,
              latestPayload >= authenticatedAt else {
            return false
        }
        return latestPayload - authenticatedAt
            >= TuyaAuthenticatedReadOnlyPreflight.minimumPostAuthenticationPayloadSurvivalNanoseconds
    }
}
