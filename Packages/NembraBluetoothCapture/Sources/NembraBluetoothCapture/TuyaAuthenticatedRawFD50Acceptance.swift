import Foundation

/// Package-level physical-truth contract for C7D09A22 follow-up evidence.
///
/// This evaluator is intentionally separate from `TuyaAuthenticatedReadOnlyPreflight`: SDK
/// application/transparent callbacks can establish authenticated Tuya transport survival, but
/// they cannot mint raw FD50 characteristic custody. Callers must provide observations produced
/// by a documented same-session characteristic path owned by the authenticated generation.
public enum TuyaAuthenticatedRawFD50Acceptance {
    public static let deviceToAppNotifyCharacteristicUUID = "00000002-0000-1001-8001-00805F9B07D0"
    public static let historicalRejectionBoundaryNanoseconds: UInt64 = 30_000_000_000
    public static let minimumRetainedNotifyCount = 2

    public struct Observation: Equatable, Sendable {
        public let connectionGeneration: UInt64
        public let characteristicUUID: String
        public let observedAtUptimeNanoseconds: UInt64

        /// Exact bytes delivered by the documented same-session raw characteristic callback.
        /// Keeping the bytes (rather than only their length) makes an accepted prefix auditable
        /// and usable for later physical mapping without assigning any DP semantics here.
        public let payload: Data

        public var payloadByteCount: Int { payload.count }

        /// Observation construction is package-owned so app/UI code cannot manufacture physical
        /// custody. A future documented same-session raw callback must be integrated inside this
        /// package and pass the exact callback bytes at this ingress boundary.
        init(
            connectionGeneration: UInt64,
            characteristicUUID: String,
            observedAtUptimeNanoseconds: UInt64,
            payload: Data
        ) {
            self.connectionGeneration = connectionGeneration
            self.characteristicUUID = characteristicUUID.uppercased()
            self.observedAtUptimeNanoseconds = observedAtUptimeNanoseconds
            self.payload = payload
        }
    }

    public enum Verdict: Equatable, Sendable {
        case blocked(reason: String)
        case accepted
    }

    /// Evaluates only physical raw-notify acceptance. It does not parse payload contents or assign
    /// any DP/telemetry/control meaning.
    public static func verdict(
        authenticatedSnapshot: TuyaAuthenticatedReadOnlyPreflightSnapshot,
        observations: [Observation]
    ) -> Verdict {
        guard authenticatedSnapshot.connectionGeneration > 0 else {
            return .blocked(reason: "No current authenticated Bluetooth generation.")
        }
        guard authenticatedSnapshot.hasActiveCallbackAuthority else {
            return .blocked(reason: "Authenticated generation no longer has live callback authority.")
        }
        guard authenticatedSnapshot.authenticationState == .authenticated,
              authenticatedSnapshot.authenticationMethod == .smartLifeAppSDK else {
            return .blocked(reason: "Current generation is not authenticated by the documented Smart Life SDK path.")
        }
        guard let connectionStarted = authenticatedSnapshot.connectionStartedAtUptimeNanoseconds,
              let authenticatedAt = authenticatedSnapshot.authenticatedAtUptimeNanoseconds,
              let latestObserved = authenticatedSnapshot.latestObservedUptimeNanoseconds,
              authenticatedAt >= connectionStarted,
              latestObserved >= authenticatedAt else {
            return .blocked(reason: "Authenticated connection chronology is unavailable or invalid.")
        }

        // Physical GO has two independent requirements: real raw notify custody and an authenticated
        // connection that itself remains observed beyond the historical ~30-second rejection window.
        // A delayed/queued raw callback received after 30 seconds cannot, by itself, prove that the
        // BLE transport was still alive at that time. Require the SDK-local connection ledger to
        // independently observe the same authenticated generation strictly beyond the boundary.
        guard latestObserved - authenticatedAt > historicalRejectionBoundaryNanoseconds else {
            return .blocked(reason: "Authenticated connection has not been independently observed beyond the historical rejection boundary.")
        }

        let qualifying = observations.filter {
            $0.connectionGeneration == authenticatedSnapshot.connectionGeneration
                && $0.characteristicUUID == deviceToAppNotifyCharacteristicUUID
                && !$0.payload.isEmpty
                // Raw physical evidence must be received after authentication completed. A packet
                // stamped at or before the authentication transition cannot prove the authenticated
                // generation's notify path even when its generation identifier otherwise matches.
                && $0.observedAtUptimeNanoseconds > authenticatedAt
        }

        // Do not require a raw callback timestamp to be <= the snapshot's latest SDK-local
        // observation. The raw callback and SDK-local connection poll execute independently, so a
        // legitimate notify can land between two polls. The independent survival guard above only
        // requires that the authenticated transport itself has also been observed beyond 30 seconds.

        // Physical acceptance requires distinct callback receipts, not two copies of one retained
        // observation. The package ingress stamps each callback with monotonic receipt time, so a
        // replayed/copy-pasted observation cannot manufacture the required two-event prefix.
        let distinctReceiptTimes = Set(qualifying.map(\.observedAtUptimeNanoseconds))
        guard distinctReceiptTimes.count >= minimumRetainedNotifyCount else {
            return .blocked(reason: "Fewer than two distinct retained non-empty post-auth raw FD50 notify receipts belong to this authenticated generation.")
        }
        guard qualifying.contains(where: {
            $0.observedAtUptimeNanoseconds - authenticatedAt > historicalRejectionBoundaryNanoseconds
        }) else {
            return .blocked(reason: "No retained raw FD50 notify payload survives beyond the historical rejection boundary.")
        }

        return .accepted
    }
}
