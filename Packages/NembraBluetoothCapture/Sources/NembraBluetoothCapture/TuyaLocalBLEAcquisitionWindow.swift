import Foundation

/// Fail-closed authority for the short interval after Tuya reports transport connect success
/// but before its local-BLE status API necessarily reflects that connection.
///
/// The window never advances authenticated-session chronology. It only decides whether the
/// caller may keep polling for local-BLE currentness or must stop the attempt.
public enum TuyaLocalBLEAcquisitionWindow: Sendable {
    public static let maximumWaitNanoseconds: UInt64 = 15_000_000_000

    public enum Verdict: Equatable, Sendable {
        case observedOnline
        case keepWaiting
        case timedOut
        case invalidClock
    }

    public static func verdict(
        startedAtUptimeNanoseconds startedAt: UInt64,
        observedAtUptimeNanoseconds observedAt: UInt64,
        isLocallyOnline: Bool,
        maximumWaitNanoseconds: UInt64 = maximumWaitNanoseconds
    ) -> Verdict {
        guard observedAt >= startedAt else { return .invalidClock }
        if isLocallyOnline { return .observedOnline }
        guard observedAt - startedAt < maximumWaitNanoseconds else { return .timedOut }
        return .keepWaiting
    }
}
