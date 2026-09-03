import Foundation

/// Fail-closed provenance binder for Tuya's documented Smart Life transparent-receive callback.
///
/// The live Capture adapter can retain one instance per `TuyaReadOnlyConnectionToken` and feed
/// callback bytes only while that exact authenticated generation owns the official SDK transport.
/// The binder rejects callbacks attributed to another/retired generation before they can enter
/// the byte-preserving transparent-receive ledger.
///
/// This remains diagnostic-only. Tuya's transparent callback does not identify the underlying
/// GATT service/characteristic tuple, so this type cannot establish raw FD50 custody, physical
/// first acceptance, telemetry semantics, control authority, pairing, reset, removal, or unbind.
public struct C7D09A22TransparentReceiveGenerationBinding: Sendable {
    public enum RecordResult: Equatable, Sendable {
        case recorded
        case rejectedWrongOrRetiredGeneration
        case rejectedWrongDeviceOrEmptyPayload
        case rejectedStaleOrReplayedCallback
    }

    private let connectionToken: TuyaReadOnlyConnectionToken
    private var bridge: C7D09A22SmartLifeTransparentReceiveBridge
    private var retired = false

    public init?(
        connectionToken: TuyaReadOnlyConnectionToken,
        expectedDeviceID: String,
        sdkConnectionStartedAtUptimeNanoseconds: UInt64
    ) {
        guard let bridge = C7D09A22SmartLifeTransparentReceiveBridge(
            expectedDeviceID: expectedDeviceID,
            sdkConnectionStartedAtUptimeNanoseconds: sdkConnectionStartedAtUptimeNanoseconds
        ) else {
            return nil
        }
        self.connectionToken = connectionToken
        self.bridge = bridge
    }

    /// Permanently closes this callback-custody object. The live SDK delegate can call this before
    /// clearing its package-owned active token during any disconnect, foreground-loss, cancellation,
    /// or other terminal path. Even if a caller accidentally retains the old token value, a delayed
    /// singleton-manager callback cannot be re-admitted after retirement.
    public mutating func retire() {
        retired = true
    }

    /// Records a callback only when the caller proves it still belongs to the exact package-owned
    /// connection generation that created this binding. A stale SDK delegate callback therefore
    /// cannot be relabeled as evidence for a later authenticated attempt.
    @discardableResult
    public mutating func recordDocumentedTransparentReceive(
        payload: Data,
        callbackDeviceID: String,
        receivedAtUptimeNanoseconds: UInt64,
        activeConnectionToken: TuyaReadOnlyConnectionToken?
    ) -> RecordResult {
        guard !retired, activeConnectionToken == connectionToken else {
            return .rejectedWrongOrRetiredGeneration
        }

        switch bridge.recordDocumentedTransparentReceive(
            payload: payload,
            callbackDeviceID: callbackDeviceID,
            receivedAtUptimeNanoseconds: receivedAtUptimeNanoseconds
        ) {
        case .recorded:
            return .recorded
        case .rejectedWrongDeviceOrEmptyPayload:
            return .rejectedWrongDeviceOrEmptyPayload
        case .rejectedStaleOrReplayedCallback:
            return .rejectedStaleOrReplayedCallback
        }
    }

    public var snapshot: TuyaSmartLifeTransparentReceiveObservationLedger.Snapshot {
        bridge.snapshot
    }

    public var diagnosticGeneration: UInt64 { connectionToken.diagnosticGeneration }
    public var isRetired: Bool { retired }

    public var authorizesRawFD50CharacteristicCustody: Bool { false }
    public var authorizesPhysicalFirstAcceptance: Bool { false }
    public var authorizesStationaryMapping: Bool { false }
    public var authorizesTelemetrySemantics: Bool { false }
    public var authorizesControlWrites: Bool { false }
    public var authorizesPairingResetOrUnbind: Bool { false }
}
