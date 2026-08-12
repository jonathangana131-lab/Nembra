import Foundation

/// Authentication/account routes recognized by the physical Tuya preflight.
///
/// `cloud local_key` is deliberately absent. Tuya cloud metadata can retain that secret for
/// future supported use, but it is not mechanically equivalent to documented FD50 BLE
/// authentication material and must never unlock the physical preflight by itself.
///
/// Device Sharing is account/device authority only. It can establish that the linked account is
/// allowed to see a device, but it does not itself prove that the current BLE generation was
/// authenticated. Physical readiness therefore requires `smartLifeAppSDK` provenance.
public enum TuyaReadOnlyAuthenticationMethod: String, Codable, Equatable, Sendable {
    case smartLifeAppSDK = "tuya-smartlife-sdk"
    case documentedDeviceSharing = "tuya-device-sharing"
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

    /// A single post-auth callback can be an initial state replay. Require repeated application
    /// evidence before physical mapping can unlock so transport liveness alone cannot turn one
    /// bootstrap callback into a claim of an ongoing authenticated notify path.
    public static let minimumAuthenticatedApplicationPayloadCount = 2

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
        guard let authenticationMethod = snapshot.authenticationMethod else {
            return .blocked(reason: "Authenticated state has no accepted Tuya authentication provenance.")
        }
        guard authenticationMethod == .smartLifeAppSDK else {
            return .blocked(reason: "Tuya Device Sharing proves account/device authority, not authentication of the current BLE connection generation.")
        }
        guard snapshot.applicationPayloadCount >= minimumAuthenticatedApplicationPayloadCount else {
            return .blocked(reason: "Authenticated session has not produced repeated application payload evidence yet.")
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

/// Narrow integration seam for an official Tuya-backed session implementation.
///
/// Implementations may perform only documented authentication/session-establishment transport
/// writes and authenticated reads/notification decryption. They must not expose generic GATT
/// writes or DP control through this protocol. An implementation must also report the provenance
/// that established the current generation. Device Sharing may establish account/device authority,
/// but only an official SmartLife SDK-authenticated BLE generation can satisfy physical readiness;
/// possession of a cloud `local_key` alone is never accepted authentication provenance.
public protocol TuyaReadOnlyAuthenticationSessionProvider: Sendable {
    func currentPreflightSnapshot() async -> TuyaAuthenticatedReadOnlyPreflightSnapshot
}
