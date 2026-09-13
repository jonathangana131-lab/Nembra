import Foundation

/// Package-owned coordinator for the documented Smart Life BLE connection path used by C7D09A22.
///
/// The injected `sdkAuthenticatedConnect` operation is intentionally narrower than a general Tuya
/// device driver. It must return only after the official Smart Life SDK has successfully connected
/// the already-linked device *and* the caller has independently observed that exact UUID online in
/// the SDK-local BLE state. The coordinator then records `.smartLifeAppSDK` authentication in the
/// package ledger and arms documented device-to-app receive custody for the exact Tuya device ID.
///
/// This type exposes no DP publish, transparent-write, pairing, activation, reset, removal, unbind,
/// or disconnect command. The linked-account identity is only used to address Tuya's documented
/// read-only connection/receive path. Received bytes remain transport evidence and cannot authorize
/// scooter telemetry semantics or controls.
@MainActor
public final class C7D09A22DocumentedSmartLifeReadOnlyConnector {
    public struct LinkedDeviceIdentity: Equatable, Sendable {
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

    public enum ConnectError: Error, Equatable, Sendable {
        case sdkAuthenticatedConnectionFailed
        case packageAuthenticationPromotionFailed
        case documentedReceiveCustodyFailed
    }

    private let ledger: TuyaAuthenticatedReadOnlySessionLedger
    private let handoff: C7D09A22DocumentedTransparentDelegateHandoff
    private var activeToken: TuyaReadOnlyConnectionToken?

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
        do {
            try await ledger.markAuthenticationStarted(for: token)
            try await sdkAuthenticatedConnect(identity.uuid, identity.productID)
        } catch {
            try? await ledger.markAuthenticationFailed(for: token)
            activeToken = nil
            await handoff.retire()
            throw ConnectError.sdkAuthenticatedConnectionFailed
        }

        do {
            try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        } catch {
            try? await ledger.markInternalLifecycleFailure(for: token)
            activeToken = nil
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
            await handoff.retire()
            throw ConnectError.documentedReceiveCustodyFailed
        }

        return token
    }

    /// Feed this synchronously from Tuya's documented device-to-app transparent receive callback.
    /// The handoff seals exact generation + device identity before its asynchronous record step.
    public func receiveDocumentedTransparentPayload(_ payload: Data, deviceID: String) {
        handoff.receive(payload: payload, callbackDeviceID: deviceID)
    }

    /// Records an independent SDK-local liveness observation for the exact active generation.
    /// This is required in addition to receive timestamps before the >30 s transport milestone can
    /// be accepted; queued callbacks cannot manufacture connection survival.
    public func observeAuthenticatedConnection() async throws {
        guard let activeToken else {
            throw TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection
        }
        try await ledger.observeCurrentConnection(for: activeToken)
    }

    public func currentPreflightSnapshot() async -> TuyaAuthenticatedReadOnlyPreflightSnapshot {
        await ledger.currentPreflightSnapshot()
    }

    public func documentedReceiveDiagnosticSnapshot() async -> C7D09A22DocumentedTransparentReceiveIngress.DiagnosticSnapshot? {
        await handoff.diagnosticSnapshot()
    }

    /// Local evidence retirement only. It deliberately does not issue a scooter/SDK disconnect.
    public func retire() async {
        let token = activeToken
        activeToken = nil
        await handoff.retire()
        if let token {
            try? await ledger.endConnection(for: token)
        }
    }

    public var authorizesRawFD50CharacteristicCustody: Bool { false }
    public var authorizesTelemetrySemantics: Bool { false }
    public var authorizesControlWrites: Bool { false }
    public var authorizesPairingResetOrUnbind: Bool { false }
}
