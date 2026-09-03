import Dispatch
import Foundation

/// One fail-closed custody object for Tuya's documented Smart Life transparent-receive callback.
///
/// The live Capture adapter should create one instance for the exact package-issued connection
/// token and retain it only for that official SDK attempt. Callback bytes must pass both gates:
/// 1. the package-owned preflight snapshot proves this exact generation is already authenticated
///    through the supported Smart Life SDK path; and
/// 2. the generation binding proves the callback still belongs to the exact non-retired token and
///    preserves device, payload, and chronology checks before bytes enter the diagnostic ledger.
///
/// This object intentionally cannot promote SDK callback bytes into raw FD50 characteristic
/// custody because the documented callback does not carry the underlying GATT tuple. It also
/// cannot authorize telemetry semantics, control writes, pairing, reset, removal, or unbind.
public struct C7D09A22AuthenticatedTransparentReceiveCustody: Sendable {
    /// Immutable process-boundary receipt captured at the instant the documented SDK callback
    /// reaches Nembra. The public constructor deliberately samples monotonic uptime itself so the
    /// live adapter cannot accidentally replace callback chronology with a later actor-hop time.
    /// Tests may use the internal initializer through `@testable` for deterministic chronology.
    public struct CallbackReceipt: Equatable, Sendable {
        public let payload: Data
        public let callbackDeviceID: String
        public let receivedAtUptimeNanoseconds: UInt64

        public static func capture(payload: Data, callbackDeviceID: String) -> Self {
            Self(
                payload: payload,
                callbackDeviceID: callbackDeviceID,
                receivedAtUptimeNanoseconds: DispatchTime.now().uptimeNanoseconds
            )
        }

        init(
            payload: Data,
            callbackDeviceID: String,
            receivedAtUptimeNanoseconds: UInt64
        ) {
            self.payload = payload
            self.callbackDeviceID = callbackDeviceID
            self.receivedAtUptimeNanoseconds = receivedAtUptimeNanoseconds
        }
    }

    public enum RecordResult: Equatable, Sendable {
        case recordedDiagnosticOnly
        case rejectedNotAuthenticated
        case rejectedWrongAuthenticationMethod
        case rejectedGenerationMismatch
        case rejectedInvalidChronology
        case rejectedWrongOrRetiredGeneration
        case rejectedWrongDeviceOrEmptyPayload
        case rejectedStaleOrReplayedCallback
    }

    private var binding: C7D09A22TransparentReceiveGenerationBinding

    public init?(
        connectionToken: TuyaReadOnlyConnectionToken,
        expectedDeviceID: String,
        sdkConnectionStartedAtUptimeNanoseconds: UInt64
    ) {
        guard let binding = C7D09A22TransparentReceiveGenerationBinding(
            connectionToken: connectionToken,
            expectedDeviceID: expectedDeviceID,
            sdkConnectionStartedAtUptimeNanoseconds: sdkConnectionStartedAtUptimeNanoseconds
        ) else {
            return nil
        }
        self.binding = binding
    }

    /// Permanently seals this custody object against delayed singleton-manager callbacks.
    public mutating func retire() {
        binding.retire()
    }

    /// Preferred live-adapter entrypoint. Capture the callback receipt synchronously when Tuya's
    /// BLE-manager delegate fires, then obtain the actor-owned preflight snapshot if needed. The
    /// exact callback timestamp survives those asynchronous hops without trusting app code to
    /// reconstruct chronology afterward.
    @discardableResult
    public mutating func recordDocumentedTransparentReceive(
        _ callback: CallbackReceipt,
        preflightSnapshot: TuyaAuthenticatedReadOnlyPreflightSnapshot,
        activeConnectionToken: TuyaReadOnlyConnectionToken?
    ) -> RecordResult {
        recordDocumentedTransparentReceive(
            payload: callback.payload,
            callbackDeviceID: callback.callbackDeviceID,
            receivedAtUptimeNanoseconds: callback.receivedAtUptimeNanoseconds,
            preflightSnapshot: preflightSnapshot,
            activeConnectionToken: activeConnectionToken
        )
    }

    /// Deterministic lower-level admission used by package tests and evidence replay.
    /// Live SDK callback wiring should prefer the `CallbackReceipt` overload above.
    /// The returned `.recordedDiagnosticOnly` result is never raw FD50 physical acceptance.
    @discardableResult
    public mutating func recordDocumentedTransparentReceive(
        payload: Data,
        callbackDeviceID: String,
        receivedAtUptimeNanoseconds: UInt64,
        preflightSnapshot: TuyaAuthenticatedReadOnlyPreflightSnapshot,
        activeConnectionToken: TuyaReadOnlyConnectionToken?
    ) -> RecordResult {
        switch C7D09A22AuthenticatedTransparentReceiveAdmission.verdict(
            snapshot: preflightSnapshot,
            bindingGeneration: binding.diagnosticGeneration,
            receivedAtUptimeNanoseconds: receivedAtUptimeNanoseconds
        ) {
        case .rejectNotAuthenticated:
            return .rejectedNotAuthenticated
        case .rejectWrongAuthenticationMethod:
            return .rejectedWrongAuthenticationMethod
        case .rejectGenerationMismatch:
            return .rejectedGenerationMismatch
        case .rejectInvalidChronology:
            return .rejectedInvalidChronology
        case .admitDiagnosticCallback:
            break
        }

        switch binding.recordDocumentedTransparentReceive(
            payload: payload,
            callbackDeviceID: callbackDeviceID,
            receivedAtUptimeNanoseconds: receivedAtUptimeNanoseconds,
            activeConnectionToken: activeConnectionToken
        ) {
        case .recorded:
            return .recordedDiagnosticOnly
        case .rejectedWrongOrRetiredGeneration:
            return .rejectedWrongOrRetiredGeneration
        case .rejectedWrongDeviceOrEmptyPayload:
            return .rejectedWrongDeviceOrEmptyPayload
        case .rejectedStaleOrReplayedCallback:
            return .rejectedStaleOrReplayedCallback
        }
    }

    public var snapshot: TuyaSmartLifeTransparentReceiveObservationLedger.Snapshot {
        binding.snapshot
    }

    public var diagnosticGeneration: UInt64 { binding.diagnosticGeneration }
    public var isRetired: Bool { binding.isRetired }

    public var authorizesRawFD50CharacteristicCustody: Bool { false }
    public var authorizesPhysicalFirstAcceptance: Bool { false }
    public var authorizesStationaryMapping: Bool { false }
    public var authorizesTelemetrySemantics: Bool { false }
    public var authorizesControlWrites: Bool { false }
    public var authorizesPairingResetOrUnbind: Bool { false }
}
