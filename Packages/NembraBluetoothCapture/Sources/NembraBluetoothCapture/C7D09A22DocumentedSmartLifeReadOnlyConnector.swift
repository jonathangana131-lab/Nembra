import Foundation

/// Package-owned coordinator for the documented Smart Life BLE connection path used by C7D09A22.
///
/// The injected `sdkAuthenticatedConnect` operation is intentionally narrower than a general Tuya
/// device driver. It must return only after the official Smart Life SDK has successfully connected
/// the already-linked device *and* the caller has independently observed that exact UUID online in
/// the SDK-local BLE state. The coordinator then records `.smartLifeAppSDK` authentication in the
/// package ledger and arms documented device-to-app receive custody for the exact Tuya device ID.
///
/// The live app may instead adopt an exact token that it already authenticated in this same ledger.
/// Adoption never creates a second generation and never takes lifecycle ownership of the app's
/// connection token; retiring evidence custody therefore cannot disconnect or retire that session.
///
/// This type exposes no DP publish, transparent-write, pairing, activation, reset, removal, unbind,
/// or disconnect command. The linked-account identity is only used to address Tuya's documented
/// read-only connection/receive path. Received bytes remain transport evidence and cannot authorize
/// scooter telemetry semantics or controls.
@MainActor
public final class C7D09A22DocumentedSmartLifeReadOnlyConnector {
    public struct LinkedDeviceIdentity: Encodable, Equatable, Sendable {
        public let deviceID: String
        public let uuid: String
        public let productID: String

        public init?(deviceID: String, uuid: String, productID: String) {
            let deviceID = deviceID.trimmingCharacters(in: .whitespacesAndNewlines)
            let uuid = uuid.trimmingCharacters(in: .whitespacesAndNewlines)
            let productID = productID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !deviceID.isEmpty, !uuid.isEmpty, !productID.isEmpty else { return nil }
            self.deviceID = deviceID
            self.uuid = uuid
            self.productID = productID
        }
    }

    /// Must complete only after the official SDK connection succeeds and the exact UUID is observed
    /// online in SDK-local BLE state. It must not pair, activate, publish a DP, or write transparent
    /// data as part of establishing that condition.
    public typealias SDKAuthenticatedConnect = @MainActor (
        _ uuid: String,
        _ productID: String
    ) async throws -> Void

    /// Read-only SDK-local liveness seam. The app must answer from the official Smart Life SDK's
    /// current local BLE state for the exact UUID supplied here. This closure must not reconnect,
    /// pair, activate, publish a DP, or write transparent data in order to produce its answer.
    public typealias SDKExactUUIDOnlineCheck = @MainActor (_ uuid: String) async throws -> Bool

    public enum ConnectError: Error, Equatable, Sendable {
        case sdkAuthenticatedConnectionFailed
        case packageAuthenticationPromotionFailed
        case existingAuthenticatedSessionInvalid
        case documentedReceiveCustodyFailed
        case sdkLivenessObservationFailed
        case exactUUIDNotObservedOnline
    }

    private let ledger: TuyaAuthenticatedReadOnlySessionLedger
    private let handoff: C7D09A22DocumentedTransparentDelegateHandoff
    private var activeToken: TuyaReadOnlyConnectionToken?
    private var activeIdentity: LinkedDeviceIdentity?
    private var ownsActiveTokenLifecycle = false
    private var lifecycleEpoch: UInt64 = 0

    public init(ledger: TuyaAuthenticatedReadOnlySessionLedger = .init()) {
        self.ledger = ledger
        self.handoff = C7D09A22DocumentedTransparentDelegateHandoff(
            preflightSnapshotProvider: { await ledger.currentPreflightSnapshot() }
        )
    }

    private func beginLifecycleIntent() -> UInt64 {
        lifecycleEpoch &+= 1
        return lifecycleEpoch
    }

    private func isCurrentLifecycle(
        _ epoch: UInt64,
        token: TuyaReadOnlyConnectionToken,
        identity: LinkedDeviceIdentity,
        ownsToken: Bool
    ) -> Bool {
        lifecycleEpoch == epoch &&
            activeToken == token &&
            activeIdentity == identity &&
            ownsActiveTokenLifecycle == ownsToken
    }

    /// Re-reads package authentication authority after the handoff has crossed its own async arm
    /// boundary. This prevents a snapshot captured before `handoff.begin(...)` from authorizing an
    /// apparently successful connector return after callback authority was revoked in the gap.
    private func hasCurrentAuthenticatedAuthority(for token: TuyaReadOnlyConnectionToken) async -> Bool {
        guard let snapshot = try? await ledger.currentPreflightSnapshot(for: token) else {
            return false
        }
        return snapshot.authenticationState == .authenticated &&
            snapshot.authenticationMethod == .smartLifeAppSDK &&
            snapshot.connectionGeneration == token.diagnosticGeneration &&
            snapshot.hasActiveCallbackAuthority
    }

    /// Clears only the state that was current when this helper began. This helper deliberately does
    /// not advance `lifecycleEpoch`; its caller owns the lifecycle intent. Clearing state before the
    /// first await prevents an older continuation from later mistaking newer custody for its own.
    private func retireCurrentState() async {
        let token = activeToken
        let shouldEndOwnedToken = ownsActiveTokenLifecycle
        activeToken = nil
        activeIdentity = nil
        ownsActiveTokenLifecycle = false
        await handoff.retire()
        if shouldEndOwnedToken, let token {
            try? await ledger.endConnection(for: token)
        }
    }

    /// Starts one exact linked-device generation using only the documented authenticated connect
    /// seam supplied by the app's official Smart Life adapter.
    @discardableResult
    public func connect(
        identity: LinkedDeviceIdentity,
        sdkAuthenticatedConnect: @escaping SDKAuthenticatedConnect
    ) async throws -> TuyaReadOnlyConnectionToken {
        let lifecycle = beginLifecycleIntent()
        await retireCurrentState()
        guard lifecycleEpoch == lifecycle else {
            throw ConnectError.existingAuthenticatedSessionInvalid
        }

        let token = try await ledger.beginConnection()
        guard lifecycleEpoch == lifecycle else {
            try? await ledger.endConnection(for: token)
            throw ConnectError.existingAuthenticatedSessionInvalid
        }

        activeToken = token
        activeIdentity = identity
        ownsActiveTokenLifecycle = true

        do {
            try await ledger.markAuthenticationStarted(for: token)
            guard isCurrentLifecycle(lifecycle, token: token, identity: identity, ownsToken: true) else {
                throw ConnectError.existingAuthenticatedSessionInvalid
            }
            try await sdkAuthenticatedConnect(identity.uuid, identity.productID)
        } catch {
            try? await ledger.markAuthenticationFailed(for: token)
            if isCurrentLifecycle(lifecycle, token: token, identity: identity, ownsToken: true) {
                activeToken = nil
                activeIdentity = nil
                ownsActiveTokenLifecycle = false
                await handoff.retire()
            }
            if error as? ConnectError == .existingAuthenticatedSessionInvalid {
                throw ConnectError.existingAuthenticatedSessionInvalid
            }
            throw ConnectError.sdkAuthenticatedConnectionFailed
        }

        guard isCurrentLifecycle(lifecycle, token: token, identity: identity, ownsToken: true) else {
            try? await ledger.markInternalLifecycleFailure(for: token)
            throw ConnectError.existingAuthenticatedSessionInvalid
        }

        do {
            try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        } catch {
            try? await ledger.markInternalLifecycleFailure(for: token)
            if isCurrentLifecycle(lifecycle, token: token, identity: identity, ownsToken: true) {
                activeToken = nil
                activeIdentity = nil
                ownsActiveTokenLifecycle = false
                await handoff.retire()
            }
            throw ConnectError.packageAuthenticationPromotionFailed
        }

        guard isCurrentLifecycle(lifecycle, token: token, identity: identity, ownsToken: true) else {
            try? await ledger.markInternalLifecycleFailure(for: token)
            throw ConnectError.existingAuthenticatedSessionInvalid
        }

        let authenticated = await ledger.currentPreflightSnapshot()
        guard isCurrentLifecycle(lifecycle, token: token, identity: identity, ownsToken: true) else {
            try? await ledger.markInternalLifecycleFailure(for: token)
            throw ConnectError.existingAuthenticatedSessionInvalid
        }

        guard await handoff.begin(
            connectionToken: token,
            expectedDeviceID: identity.deviceID,
            authenticatedPreflightSnapshot: authenticated
        ) else {
            try? await ledger.markInternalLifecycleFailure(for: token)
            if isCurrentLifecycle(lifecycle, token: token, identity: identity, ownsToken: true) {
                activeToken = nil
                activeIdentity = nil
                ownsActiveTokenLifecycle = false
                await handoff.retire()
            }
            throw ConnectError.documentedReceiveCustodyFailed
        }

        guard isCurrentLifecycle(lifecycle, token: token, identity: identity, ownsToken: true),
              await hasCurrentAuthenticatedAuthority(for: token),
              isCurrentLifecycle(lifecycle, token: token, identity: identity, ownsToken: true) else {
            try? await ledger.markInternalLifecycleFailure(for: token)
            if isCurrentLifecycle(lifecycle, token: token, identity: identity, ownsToken: true) {
                activeToken = nil
                activeIdentity = nil
                ownsActiveTokenLifecycle = false
                await handoff.retire()
            }
            throw ConnectError.existingAuthenticatedSessionInvalid
        }

        return token
    }

    /// Adopts the live app's exact already-authenticated Smart Life token without creating another
    /// connection generation. The token must still be current in this connector's injected ledger,
    /// authenticated by `.smartLifeAppSDK`, and retain active callback authority.
    ///
    /// This path intentionally does not take lifecycle ownership of `connectionToken`. Calling
    /// `retire()` later only drops this coordinator's documented evidence custody; it does not end
    /// the app-owned authenticated session.
    public func adoptAuthenticatedSession(
        identity: LinkedDeviceIdentity,
        connectionToken: TuyaReadOnlyConnectionToken
    ) async throws {
        let lifecycle = beginLifecycleIntent()
        await retireCurrentState()
        guard lifecycleEpoch == lifecycle else {
            throw ConnectError.existingAuthenticatedSessionInvalid
        }

        let authenticated: TuyaAuthenticatedReadOnlyPreflightSnapshot
        do {
            authenticated = try await ledger.currentPreflightSnapshot(for: connectionToken)
        } catch {
            throw ConnectError.existingAuthenticatedSessionInvalid
        }

        guard lifecycleEpoch == lifecycle,
              authenticated.authenticationState == .authenticated,
              authenticated.authenticationMethod == .smartLifeAppSDK,
              authenticated.connectionGeneration == connectionToken.diagnosticGeneration,
              authenticated.hasActiveCallbackAuthority,
              authenticated.connectionStartedAtUptimeNanoseconds != nil,
              authenticated.authenticatedAtUptimeNanoseconds != nil else {
            throw ConnectError.existingAuthenticatedSessionInvalid
        }

        guard await handoff.begin(
            connectionToken: connectionToken,
            expectedDeviceID: identity.deviceID,
            authenticatedPreflightSnapshot: authenticated
        ) else {
            if lifecycleEpoch == lifecycle {
                await handoff.retire()
            }
            throw ConnectError.documentedReceiveCustodyFailed
        }

        guard lifecycleEpoch == lifecycle,
              await hasCurrentAuthenticatedAuthority(for: connectionToken),
              lifecycleEpoch == lifecycle else {
            if lifecycleEpoch == lifecycle {
                await handoff.retire()
            }
            throw ConnectError.existingAuthenticatedSessionInvalid
        }

        activeToken = connectionToken
        activeIdentity = identity
        ownsActiveTokenLifecycle = false
    }

    /// Feed this synchronously from Tuya's documented device-to-app transparent receive callback.
    /// The handoff seals exact generation + device identity before its asynchronous record step.
    public func receiveDocumentedTransparentPayload(_ payload: Data, deviceID: String) {
        handoff.receive(payload: payload, callbackDeviceID: deviceID)
    }

    /// Records an independent SDK-local liveness observation for the exact active generation.
    ///
    /// The package deliberately cannot advance its >30 s survival clock merely because this method
    /// was called. The app must first perform a fresh, read-only observation of the exact linked UUID
    /// in the official Smart Life SDK's local BLE state. After that async observation returns, the
    /// exact package token, identity, and lifecycle intent are revalidated to prevent a reconnect,
    /// retire, or same-token re-adoption race from crediting liveness to another custody interval.
    public func observeAuthenticatedConnection(
        sdkIsExactUUIDOnline: @escaping SDKExactUUIDOnlineCheck
    ) async throws {
        guard let observedToken = activeToken,
              let observedIdentity = activeIdentity else {
            throw TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection
        }
        let observedLifecycle = lifecycleEpoch

        let isOnline: Bool
        do {
            isOnline = try await sdkIsExactUUIDOnline(observedIdentity.uuid)
        } catch {
            throw ConnectError.sdkLivenessObservationFailed
        }

        guard isOnline else {
            // A negative observation for the exact linked UUID breaks the physical continuity
            // required by the >30 s / 45 s acceptance horizon. Do not leave this generation's
            // callback authority armed and allow a later online sample to bridge across an
            // observed offline interval. This retires package evidence only; it does not issue an
            // SDK disconnect, reconnect, write, reset, removal, or unbind command.
            if lifecycleEpoch == observedLifecycle,
               activeToken == observedToken,
               activeIdentity == observedIdentity {
                try? await ledger.markObservationContinuityInvalidated(for: observedToken)
                activeToken = nil
                activeIdentity = nil
                ownsActiveTokenLifecycle = false
                await handoff.retire()
            }
            throw ConnectError.exactUUIDNotObservedOnline
        }

        // The SDK check crosses an actor reentrancy point. Do not let a reconnect, retire, or
        // same-token re-adoption that happened while it was in flight donate its observation.
        guard lifecycleEpoch == observedLifecycle,
              activeToken == observedToken,
              activeIdentity == observedIdentity else {
            throw ConnectError.existingAuthenticatedSessionInvalid
        }

        let authenticated: TuyaAuthenticatedReadOnlyPreflightSnapshot
        do {
            authenticated = try await ledger.currentPreflightSnapshot(for: observedToken)
        } catch {
            throw ConnectError.existingAuthenticatedSessionInvalid
        }

        guard lifecycleEpoch == observedLifecycle,
              activeToken == observedToken,
              activeIdentity == observedIdentity,
              authenticated.authenticationState == .authenticated,
              authenticated.authenticationMethod == .smartLifeAppSDK,
              authenticated.connectionGeneration == observedToken.diagnosticGeneration,
              authenticated.hasActiveCallbackAuthority else {
            throw ConnectError.existingAuthenticatedSessionInvalid
        }

        try await ledger.observeCurrentConnection(for: observedToken)

        // The actor mutation above is another suspension point. If this custody interval lost
        // ownership while the mutation was in flight, the observation has already touched the
        // package chronology. Fail closed by retiring the still-current exact token rather than
        // allowing a retired/re-adopted interval to inherit stale >30 s liveness credit. If a newer
        // token owns the ledger, this exact-token invalidation is rejected as stale and cannot harm it.
        guard lifecycleEpoch == observedLifecycle,
              activeToken == observedToken,
              activeIdentity == observedIdentity else {
            try? await ledger.markInternalLifecycleFailure(for: observedToken)
            throw ConnectError.existingAuthenticatedSessionInvalid
        }
    }

    public func currentPreflightSnapshot() async -> TuyaAuthenticatedReadOnlyPreflightSnapshot {
        await ledger.currentPreflightSnapshot()
    }

    public func documentedReceiveDiagnosticSnapshot() async -> C7D09A22DocumentedTransparentReceiveIngress.DiagnosticSnapshot? {
        await handoff.diagnosticSnapshot()
    }

    /// Local evidence retirement only. An adopted app-owned token is never ended here. For a token
    /// minted by `connect`, retirement closes only the package ledger generation and still does not
    /// issue a scooter/SDK disconnect command.
    public func retire() async {
        _ = beginLifecycleIntent()
        await retireCurrentState()
    }

    public var authorizesRawFD50CharacteristicCustody: Bool { false }
    public var authorizesTelemetrySemantics: Bool { false }
    public var authorizesControlWrites: Bool { false }
    public var authorizesPairingResetOrUnbind: Bool { false }
}
