import Dispatch
import Foundation

/// A transparent-receive callback receipt that seals the package-owned connection
/// generation at the synchronous SDK delegate boundary.
///
/// This prevents a callback that was delivered for generation N from being queued
/// across an actor hop and later admitted against generation N+1 merely because the
/// Tuya device ID is the same. The receipt is diagnostic-only and carries no raw
/// GATT service/characteristic authority.
public struct C7D09A22GenerationBoundTransparentReceiveReceipt: Equatable, Sendable {
    public let payload: Data
    public let callbackDeviceID: String
    public let capturedConnectionGeneration: UInt64
    public let receivedAtUptimeNanoseconds: UInt64

    /// Capture this synchronously inside `bleReceiveTransparentData(_:devId:)`.
    /// A callback with no package-owned active token is intentionally discarded.
    public static func capture(
        payload: Data,
        callbackDeviceID: String,
        activeConnectionToken: TuyaReadOnlyConnectionToken?
    ) -> Self? {
        guard let activeConnectionToken else { return nil }
        return Self(
            payload: payload,
            callbackDeviceID: callbackDeviceID,
            capturedConnectionGeneration: activeConnectionToken.diagnosticGeneration,
            receivedAtUptimeNanoseconds: DispatchTime.now().uptimeNanoseconds
        )
    }

    init(
        payload: Data,
        callbackDeviceID: String,
        capturedConnectionGeneration: UInt64,
        receivedAtUptimeNanoseconds: UInt64
    ) {
        self.payload = payload
        self.callbackDeviceID = callbackDeviceID
        self.capturedConnectionGeneration = capturedConnectionGeneration
        self.receivedAtUptimeNanoseconds = receivedAtUptimeNanoseconds
    }

    public var authorizesRawFD50CharacteristicCustody: Bool { false }
    public var authorizesPhysicalFirstAcceptance: Bool { false }
    public var authorizesTelemetrySemantics: Bool { false }
    public var authorizesControlWrites: Bool { false }
    public var authorizesPairingResetOrUnbind: Bool { false }
}
