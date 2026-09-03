import Foundation

/// Actor-owned live-session wrapper for the documented Tuya Smart Life
/// transparent-receive callback used by the C7D09A22 read-only preflight.
///
/// `ThingSmartBLEManager` is process-global and its delegate callbacks can outlive
/// the UI/controller generation that initiated a connection. This actor gives the
/// Capture adapter one serialization point for callback admission and terminal
/// retirement without exposing any write-capable Tuya operation.
///
/// The adapter must still capture callback chronology synchronously at the SDK
/// delegate boundary before hopping to this actor. Recorded bytes remain
/// diagnostic-only because the documented callback does not expose a raw GATT
/// service/characteristic tuple.
public actor C7D09A22AuthenticatedTransparentReceiveSession {
    public typealias CallbackReceipt = C7D09A22AuthenticatedTransparentReceiveCustody.CallbackReceipt
    public typealias RecordResult = C7D09A22AuthenticatedTransparentReceiveCustody.RecordResult

    private var custody: C7D09A22AuthenticatedTransparentReceiveCustody
    private var terminallyRetired = false

    public init?(
        connectionToken: TuyaReadOnlyConnectionToken,
        expectedDeviceID: String,
        sdkConnectionStartedAtUptimeNanoseconds: UInt64
    ) {
        guard let custody = C7D09A22AuthenticatedTransparentReceiveCustody(
            connectionToken: connectionToken,
            expectedDeviceID: expectedDeviceID,
            sdkConnectionStartedAtUptimeNanoseconds: sdkConnectionStartedAtUptimeNanoseconds
        ) else {
            return nil
        }
        self.custody = custody
    }

    /// Preferred live delegate ingress. The callback receipt seals the active
    /// package generation synchronously at `bleReceiveTransparentData(_:devId:)`.
    /// That generation must still be this exact session when actor admission runs,
    /// preventing queued generation-N bytes from being borrowed by generation N+1.
    @discardableResult
    public func recordDocumentedTransparentReceive(
        _ callback: C7D09A22GenerationBoundTransparentReceiveReceipt,
        preflightSnapshot: TuyaAuthenticatedReadOnlyPreflightSnapshot,
        activeConnectionToken: TuyaReadOnlyConnectionToken?
    ) -> RecordResult {
        guard !terminallyRetired,
              callback.capturedConnectionGeneration == custody.diagnosticGeneration else {
            return .rejectedWrongOrRetiredGeneration
        }

        let sealedReceipt = CallbackReceipt(
            payload: callback.payload,
            callbackDeviceID: callback.callbackDeviceID,
            receivedAtUptimeNanoseconds: callback.receivedAtUptimeNanoseconds
        )
        return custody.recordDocumentedTransparentReceive(
            sealedReceipt,
            preflightSnapshot: preflightSnapshot,
            activeConnectionToken: activeConnectionToken
        )
    }

    /// Serially admits one already-timestamped documented SDK callback against
    /// the exact package-owned authenticated generation. A callback queued before
    /// retirement but admitted after retirement still fails closed.
    @discardableResult
    public func recordDocumentedTransparentReceive(
        _ callback: CallbackReceipt,
        preflightSnapshot: TuyaAuthenticatedReadOnlyPreflightSnapshot,
        activeConnectionToken: TuyaReadOnlyConnectionToken?
    ) -> RecordResult {
        guard !terminallyRetired else {
            return .rejectedWrongOrRetiredGeneration
        }

        return custody.recordDocumentedTransparentReceive(
            callback,
            preflightSnapshot: preflightSnapshot,
            activeConnectionToken: activeConnectionToken
        )
    }

    /// Irreversibly closes callback admission for this exact SDK connection.
    /// Calling this more than once is intentionally harmless.
    public func retire() {
        guard !terminallyRetired else { return }
        terminallyRetired = true
        custody.retire()
    }

    public var isRetired: Bool { terminallyRetired || custody.isRetired }

    public var snapshot: TuyaSmartLifeTransparentReceiveObservationLedger.Snapshot {
        custody.snapshot
    }

    public var diagnosticGeneration: UInt64 { custody.diagnosticGeneration }

    // SDK transparent-receive bytes are useful transport diagnostics only.
    public var authorizesRawFD50CharacteristicCustody: Bool { false }
    public var authorizesPhysicalFirstAcceptance: Bool { false }
    public var authorizesStationaryMapping: Bool { false }
    public var authorizesTelemetrySemantics: Bool { false }
    public var authorizesControlWrites: Bool { false }
    public var authorizesPairingResetOrUnbind: Bool { false }
}
