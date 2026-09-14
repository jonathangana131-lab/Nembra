import Foundation

/// Field-facing, fail-closed entry point for C7D09A22's documented Smart Life BLE preflight.
///
/// The low-level connector deliberately accepts an injected documented SDK connect seam so it can
/// be tested independently. Physical field code should use this wrapper instead: it requires both
/// (1) complete exact-device membership in the user's currently linked Tuya/Smart Life account and
/// (2) an in-memory same-account identity lease before the SDK BLE connect is allowed to run.
///
/// No account credential, UID, local key, token, password, AppSecret, or session material is stored
/// or exported by this wrapper. It does not add DP publish, transparent write, pairing, activation,
/// reset, removal, unbind, or disconnect authority.
public enum C7D09A22DocumentedSmartLifeVerifiedAccountPreflight {
    public enum Error: Swift.Error, Equatable, Sendable {
        case accountMembershipNotAuthorized(reason: String)
        case accountIdentityLeaseNotAuthorized(reason: String)
    }

    @MainActor
    @discardableResult
    public static func connect(
        connector: C7D09A22DocumentedSmartLifeReadOnlyConnector,
        identity: C7D09A22DocumentedSmartLifeReadOnlyConnector.LinkedDeviceIdentity,
        membershipSnapshot: TuyaSDKAccountDeviceMembershipGate.Snapshot,
        identityLeaseSnapshot: TuyaSDKAccountIdentityLeaseGate.Snapshot,
        sdkAuthenticatedConnect: @escaping C7D09A22DocumentedSmartLifeReadOnlyConnector.SDKAuthenticatedConnect
    ) async throws -> TuyaReadOnlyConnectionToken {
        switch TuyaSDKAccountDeviceMembershipGate.verdict(
            expectedDeviceID: identity.deviceID,
            snapshot: membershipSnapshot
        ) {
        case .authorized:
            break
        case .blocked(let reason):
            throw Error.accountMembershipNotAuthorized(reason: reason)
        }

        // The lease must describe this exact identity. Do not allow callers to pass a lease whose
        // internally expected device differs from the connector target even if the lease is otherwise
        // self-consistent.
        let normalizedTargetDeviceID = identity.deviceID.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedLeaseExpectedDeviceID = identityLeaseSnapshot.expectedDeviceID
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedTargetDeviceID == normalizedLeaseExpectedDeviceID else {
            throw Error.accountIdentityLeaseNotAuthorized(
                reason: "Account-bound identity lease targets a different Tuya device."
            )
        }

        switch TuyaSDKAccountIdentityLeaseGate.verdict(for: identityLeaseSnapshot) {
        case .authorized:
            break
        case .blocked(let reason):
            throw Error.accountIdentityLeaseNotAuthorized(reason: reason)
        }

        return try await connector.connect(
            identity: identity,
            sdkAuthenticatedConnect: sdkAuthenticatedConnect
        )
    }

    public static var authorizesTelemetrySemantics: Bool { false }
    public static var authorizesControlWrites: Bool { false }
    public static var authorizesPairingResetOrUnbind: Bool { false }
}
