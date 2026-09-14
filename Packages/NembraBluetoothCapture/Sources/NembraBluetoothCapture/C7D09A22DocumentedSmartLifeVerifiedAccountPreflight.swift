import Foundation

/// Field-facing, fail-closed entry point for C7D09A22's documented Smart Life BLE preflight.
///
/// The low-level connector deliberately accepts an injected documented SDK connect seam so it can
/// be tested independently. Physical field code should use this wrapper instead: it requires both
/// (1) complete exact-device membership in the user's currently linked Tuya/Smart Life account and
/// (2) an in-memory same-account identity lease before the SDK BLE connect is allowed to run.
///
/// Account authority is read immediately before and again immediately after each asynchronous SDK
/// connection or liveness observation. If membership/account identity changes while either SDK read
/// is in flight, package evidence custody is retired and the preflight fails closed. Retiring package
/// custody never issues a scooter disconnect, pairing, activation, reset, removal, or unbind command.
///
/// No account credential, UID, local key, token, password, AppSecret, or session material is stored
/// or exported by this wrapper. It does not add DP publish, transparent write, pairing, activation,
/// reset, removal, unbind, or disconnect authority.
public enum C7D09A22DocumentedSmartLifeVerifiedAccountPreflight {
    public enum Error: Swift.Error, Equatable, Sendable {
        case accountMembershipNotAuthorized(reason: String)
        case accountIdentityLeaseNotAuthorized(reason: String)
    }

    public typealias MembershipSnapshotProvider = @MainActor () async -> TuyaSDKAccountDeviceMembershipGate.Snapshot
    public typealias IdentityLeaseSnapshotProvider = @MainActor () async -> TuyaSDKAccountIdentityLeaseGate.Snapshot

    private static func verify(
        identity: C7D09A22DocumentedSmartLifeReadOnlyConnector.LinkedDeviceIdentity,
        membershipSnapshot: TuyaSDKAccountDeviceMembershipGate.Snapshot,
        identityLeaseSnapshot: TuyaSDKAccountIdentityLeaseGate.Snapshot
    ) throws {
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
    }

    @MainActor
    private static func verifyFreshAccountAuthority(
        identity: C7D09A22DocumentedSmartLifeReadOnlyConnector.LinkedDeviceIdentity,
        membershipSnapshotProvider: @escaping MembershipSnapshotProvider,
        identityLeaseSnapshotProvider: @escaping IdentityLeaseSnapshotProvider
    ) async throws {
        try verify(
            identity: identity,
            membershipSnapshot: await membershipSnapshotProvider(),
            identityLeaseSnapshot: await identityLeaseSnapshotProvider()
        )
    }

    @MainActor
    @discardableResult
    public static func connect(
        connector: C7D09A22DocumentedSmartLifeReadOnlyConnector,
        identity: C7D09A22DocumentedSmartLifeReadOnlyConnector.LinkedDeviceIdentity,
        membershipSnapshotProvider: @escaping MembershipSnapshotProvider,
        identityLeaseSnapshotProvider: @escaping IdentityLeaseSnapshotProvider,
        sdkAuthenticatedConnect: @escaping C7D09A22DocumentedSmartLifeReadOnlyConnector.SDKAuthenticatedConnect
    ) async throws -> TuyaReadOnlyConnectionToken {
        try await verifyFreshAccountAuthority(
            identity: identity,
            membershipSnapshotProvider: membershipSnapshotProvider,
            identityLeaseSnapshotProvider: identityLeaseSnapshotProvider
        )

        let token = try await connector.connect(
            identity: identity,
            sdkAuthenticatedConnect: sdkAuthenticatedConnect
        )

        do {
            try await verifyFreshAccountAuthority(
                identity: identity,
                membershipSnapshotProvider: membershipSnapshotProvider,
                identityLeaseSnapshotProvider: identityLeaseSnapshotProvider
            )
        } catch {
            // This only drops package-owned evidence custody. The connector intentionally exposes no
            // scooter/SDK disconnect, reset, removal, pairing, activation, or unbind command.
            await connector.retire()
            throw error
        }

        return token
    }

    /// Advances authenticated continuity only while the exact linked-account/device authority is
    /// still current. The SDK liveness seam is read-only and must report whether the exact UUID is
    /// online in the official Smart Life SDK; it may not reconnect or send scooter commands.
    ///
    /// Account authority is checked on both sides of the asynchronous SDK observation so an account
    /// switch, lost device membership, or changed identity lease cannot donate >30/45-second survival
    /// credit to a generation after the user's linked-account authority has ceased to match it.
    @MainActor
    public static func observeAuthenticatedConnection(
        connector: C7D09A22DocumentedSmartLifeReadOnlyConnector,
        identity: C7D09A22DocumentedSmartLifeReadOnlyConnector.LinkedDeviceIdentity,
        membershipSnapshotProvider: @escaping MembershipSnapshotProvider,
        identityLeaseSnapshotProvider: @escaping IdentityLeaseSnapshotProvider,
        sdkIsExactUUIDOnline: @escaping C7D09A22DocumentedSmartLifeReadOnlyConnector.SDKExactUUIDOnlineCheck
    ) async throws {
        try await verifyFreshAccountAuthority(
            identity: identity,
            membershipSnapshotProvider: membershipSnapshotProvider,
            identityLeaseSnapshotProvider: identityLeaseSnapshotProvider
        )

        try await connector.observeAuthenticatedConnection(
            sdkIsExactUUIDOnline: sdkIsExactUUIDOnline
        )

        do {
            try await verifyFreshAccountAuthority(
                identity: identity,
                membershipSnapshotProvider: membershipSnapshotProvider,
                identityLeaseSnapshotProvider: identityLeaseSnapshotProvider
            )
        } catch {
            // Fail closed on evidence custody only. Do not disconnect/unbind/reset the physical device.
            await connector.retire()
            throw error
        }
    }

    public static var authorizesTelemetrySemantics: Bool { false }
    public static var authorizesControlWrites: Bool { false }
    public static var authorizesPairingResetOrUnbind: Bool { false }
}
