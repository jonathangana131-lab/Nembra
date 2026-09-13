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

    public init(ledger: TuyaAuthenticatedReadOnlySessionLedger = .init()) {
        self.ledger = ledger
        self.handoff = C7D09A22DocumentedTransparentDelegateHandoff(
            preflightSnapshotProvider: { await ledger.currentPreflightSnapshot() }
        )
    }

    /// Starts one exact linked-device generation using only the documented authenticated connect
    /// seam supplied by the app's official Smart Life adapter.
    @discardableResult
    public func connect(
        identity: LinkedDeviceIdentity,
        sdkAuthenticatedConnect: @escaping SDKAuthenticatedConnect
    ) async throws -> TuyaReadOnlyConnectionToken {
        await retire()

        let token = try await ledger.beginConnection()
        activeToken = token
        activeIdentity = identity
        ownsActiveTokenLifecycle = true
        do {
            try await ledger.markAuthenticationStarted(for: token)
            try await sdkAuthenticatedConnect(identity.uuid, identity.productID)
        } catch {
            try? await ledger.markAuthenticationFailed(for: token)
            activeToken = nil
            activeIdentity = nil
            ownsActiveTokenLifecycle = false
            await handoff.retire()
            throw ConnectError.sdkAuthenticatedConnectionFailed
        }

        do {
            try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        } catch {
            try? await ledger.markInternalLifecycleFailure(for: token)
            activeToken = nil
            activeIdentity = nil
            ownsActiveTokenLifecycle = false
            await handoff.retire()
            throw ConnectError.packageAuthenticationPromotionFailed
        }

        let authenticated = await ledger.currentPreflightSnapshot()
        guard await handoff.begin(
            connectionToken: token,
            expectedDeviceID: identity.deviceID,
            authenticatedPreflightSnapshot: authenticated
        ) else {
            try? await ledger.markInternalLifecycleFailure(for: token)
            activeToken = nil
            activeIdentity = nil
            ownsActiveTokenLifecycle = false
            await handoff.retire()
            throw ConnectError.documentedReceiveCustodyFailed
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
        await retire()

        let authenticated: TuyaAuthenticatedReadOnlyPreflightSnapshot
        do {
            authenticated = try await ledger.currentPreflightSnapshot(for: connectionToken)
        } catch {
            throw ConnectError.existingAuthenticatedSessionInvalid
        }

        guard authenticated.authenticationState == .authenticated,
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
            await handoff.retire()
            throw ConnectError.documentedReceiveCustodyFailed
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
    /// exact package token and identity are revalidated to prevent a reconnect/re-arm race from
    /// crediting liveness to a different physical connection.
    public func observeAuthenticatedConnection(
        sdkIsExactUUIDOnline: @escaping SDKExactUUIDOnlineCheck
    ) async throws {
        guard let observedToken = activeToken,
              let observedIdentity = activeIdentity else {
            throw TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection
        }

        let isOnline: Bool
        do {
            isOnline = try await sdkIsExactUUIDOnline(observedIdentity.uuid)
        } catch {
            throw ConnectError.sdkLivenessObservationFailed
        }

        guard isOnline else {
            throw ConnectError.exactUUIDNotObservedOnline
        }

        // The SDK check crosses an actor reentrancy point. Do not let a reconnect or re-arm that
        // happened while it was in flight donate its observation to either connection generation.
        guard activeToken == observedToken,
              activeIdentity == observedIdentity else {
            throw ConnectError.existingAuthenticatedSessionInvalid
        }

        let authenticated: TuyaAuthenticatedReadOnlyPreflightSnapshot
        do {
            authenticated = try await ledger.currentPreflightSnapshot(for: observedToken)
        } catch {
            throw ConnectError.existingAuthenticatedSessionInvalid
        }

        guard authenticated.authenticationState == .authenticated,
              authenticated.authenticationMethod == .smartLifeAppSDK,
              authenticated.connectionGeneration == observedToken.diagnosticGeneration,
              authenticated.hasActiveCallbackAuthority else {
            throw ConnectError.existingAuthenticatedSessionInvalid
        }

        try await ledger.observeCurrentConnection(for: observedToken)
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

    public var authorizesRawFD50CharacteristicCustody: Bool { false }
    public var authorizesTelemetrySemantics: Bool { false }
    public var authorizesControlWrites: Bool { false }
    public var authorizesPairingResetOrUnbind: Bool { false }
}
