import Foundation

/// The only authentication route currently allowed to mint authenticated-session provenance.
///
/// Cloud metadata, device sharing, account membership, and `local_key` possession are deliberately
/// absent. They may establish account/device context, but none is mechanically equivalent to a
/// documented authenticated FD50 BLE session. Physical acceptance therefore requires the official
/// SmartLife App SDK connection path used by the field adapter.
public enum TuyaReadOnlyAuthenticationMethod: String, Codable, Equatable, Sendable {
    case smartLifeAppSDK = "tuya-smartlife-sdk"
}

/// Non-secret milestones for the physical Tuya authentication gate.
/// No token, device key, session key, nonce, password, or plaintext credential belongs here.
public struct TuyaAuthenticatedReadOnlyPreflightSnapshot: Equatable, Sendable {
    public enum AuthenticationState: Equatable, Sendable {
        case unavailable(reason: String)
        case waitingForAuthentication
        case authenticating
        case authenticated
        case failed(reason: String)
    }

    public let authenticationState: AuthenticationState
    public let authenticationMethod: TuyaReadOnlyAuthenticationMethod?
    public let connectionStartedAtUptimeNanoseconds: UInt64?
    public let authenticatedAtUptimeNanoseconds: UInt64?
    public let latestObservedUptimeNanoseconds: UInt64?
    public let applicationPayloadCount: Int
    public let latestApplicationPayloadUptimeNanoseconds: UInt64?
    public let connectionGeneration: UInt64

    public init(
        authenticationState: AuthenticationState,
        authenticationMethod: TuyaReadOnlyAuthenticationMethod? = nil,
        connectionStartedAtUptimeNanoseconds: UInt64?,
        authenticatedAtUptimeNanoseconds: UInt64?,
        latestObservedUptimeNanoseconds: UInt64?,
        applicationPayloadCount: Int,
        latestApplicationPayloadUptimeNanoseconds: UInt64? = nil,
        connectionGeneration: UInt64
    ) {
        self.authenticationState = authenticationState
        self.authenticationMethod = authenticationMethod
        self.connectionStartedAtUptimeNanoseconds = connectionStartedAtUptimeNanoseconds
        self.authenticatedAtUptimeNanoseconds = authenticatedAtUptimeNanoseconds
        self.latestObservedUptimeNanoseconds = latestObservedUptimeNanoseconds
        self.applicationPayloadCount = max(0, applicationPayloadCount)
        self.latestApplicationPayloadUptimeNanoseconds = latestApplicationPayloadUptimeNanoseconds
        self.connectionGeneration = connectionGeneration
    }
}

/// Fail-closed decision boundary between Tuya transport authentication and the guided
/// physical scenario flow. This object never performs BLE writes and never stores secrets.
public enum TuyaAuthenticatedReadOnlyPreflight {
    /// Physical acceptance is intentionally stricter than the observed ~29.93 s rejection.
    public static let minimumAuthenticatedConnectionNanoseconds: UInt64 = 45_000_000_000

    public enum Verdict: Equatable, Sendable {
        case blocked(reason: String)
        case readyForStationaryMapping
    }

    public static func verdict(
        for snapshot: TuyaAuthenticatedReadOnlyPreflightSnapshot
    ) -> Verdict {
        guard snapshot.connectionGeneration > 0 else {
            return .blocked(reason: "No current Bluetooth connection generation.")
        }
        switch snapshot.authenticationState {
        case let .unavailable(reason), let .failed(reason):
            return .blocked(reason: reason)
        case .waitingForAuthentication:
            return .blocked(reason: "Tuya authentication required.")
        case .authenticating:
            return .blocked(reason: "Tuya authentication is still in progress.")
        case .authenticated:
            break
        }
        guard snapshot.authenticationMethod == .smartLifeAppSDK else {
            return .blocked(reason: "Authenticated state has no accepted SmartLife SDK BLE provenance.")
        }
        guard snapshot.applicationPayloadCount > 0 else {
            return .blocked(reason: "Authenticated session has not produced an application payload yet.")
        }
        guard let connectionStarted = snapshot.connectionStartedAtUptimeNanoseconds,
              let authenticatedAt = snapshot.authenticatedAtUptimeNanoseconds,
              let latestPayload = snapshot.latestApplicationPayloadUptimeNanoseconds,
              let latest = snapshot.latestObservedUptimeNanoseconds,
              authenticatedAt >= connectionStarted,
              latestPayload >= authenticatedAt,
              latest >= latestPayload else {
            return .blocked(reason: "Authenticated connection chronology is unavailable or invalid.")
        }
        guard latest - authenticatedAt >= minimumAuthenticatedConnectionNanoseconds else {
            return .blocked(reason: "Authenticated connection has not survived the physical stability window yet.")
        }
        return .readyForStationaryMapping
    }
}

/// Narrow integration seam for the official Tuya-backed session implementation.
///
/// Implementations may perform only documented authentication/session-establishment transport
/// writes and authenticated reads/notification decryption. They must not expose generic GATT
/// writes or DP control through this protocol. An implementation must report SmartLife App SDK
/// provenance for the current generation; cloud metadata, sharing authority, account membership,
/// or possession of a cloud `local_key` alone can never mint authenticated BLE authority.
public protocol TuyaReadOnlyAuthenticationSessionProvider: Sendable {
    func currentPreflightSnapshot() async -> TuyaAuthenticatedReadOnlyPreflightSnapshot
}
