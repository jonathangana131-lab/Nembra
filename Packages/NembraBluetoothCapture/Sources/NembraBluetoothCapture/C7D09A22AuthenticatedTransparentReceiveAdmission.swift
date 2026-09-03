import Foundation

/// Fail-closed admission gate for Tuya's documented Smart Life transparent-receive callback.
///
/// This gate is intentionally narrower than `C7D09A22TransparentReceiveGenerationBinding`:
/// the generation binding proves exact token ownership and callback chronology, while this type
/// additionally proves that the same generation has already reached package-owned authenticated
/// state through the supported Smart Life SDK path before callback bytes are forwarded.
///
/// Admitted bytes remain diagnostic-only. The Smart Life transparent callback does not expose the
/// underlying GATT service/characteristic tuple, so admission here cannot establish raw FD50
/// characteristic custody, physical first acceptance, telemetry semantics, control authority,
/// pairing, reset, removal, or unbind.
public enum C7D09A22AuthenticatedTransparentReceiveAdmission {
    public enum Verdict: Equatable, Sendable {
        case admitDiagnosticCallback
        case rejectNotAuthenticated
        case rejectWrongAuthenticationMethod
        case rejectGenerationMismatch
        case rejectInvalidChronology
    }

    public static func verdict(
        snapshot: TuyaAuthenticatedReadOnlyPreflightSnapshot,
        bindingGeneration: UInt64,
        receivedAtUptimeNanoseconds: UInt64
    ) -> Verdict {
        guard snapshot.authenticationState == .authenticated else {
            return .rejectNotAuthenticated
        }
        guard snapshot.authenticationMethod == .smartLifeAppSDK else {
            return .rejectWrongAuthenticationMethod
        }
        guard bindingGeneration > 0,
              snapshot.connectionGeneration == bindingGeneration else {
            return .rejectGenerationMismatch
        }
        guard let connectionStarted = snapshot.connectionStartedAtUptimeNanoseconds,
              let authenticatedAt = snapshot.authenticatedAtUptimeNanoseconds,
              authenticatedAt >= connectionStarted,
              receivedAtUptimeNanoseconds >= authenticatedAt else {
            return .rejectInvalidChronology
        }
        return .admitDiagnosticCallback
    }

    public static var authorizesRawFD50CharacteristicCustody: Bool { false }
    public static var authorizesPhysicalFirstAcceptance: Bool { false }
    public static var authorizesTelemetrySemantics: Bool { false }
    public static var authorizesControlWrites: Bool { false }
    public static var authorizesPairingResetOrUnbind: Bool { false }
}
