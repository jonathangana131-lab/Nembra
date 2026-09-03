import Foundation

/// Byte-preserving evidence emitted by Tuya's documented
/// `ThingSmartBLEManagerDelegate.bleReceiveTransparentData(_:devId:)` callback.
///
/// This receipt intentionally does **not** claim that the callback is a raw FD50
/// characteristic notification. Tuya documents it as transmission data received from
/// the device on the SDK-owned BLE path. It is therefore useful same-SDK-transport
/// evidence, but cannot by itself satisfy C7D09A22 physical first acceptance.
public struct TuyaSmartLifeTransparentReceiveReceipt: Equatable, Sendable {
    public static let documentedCallback = "ThingSmartBLEManagerDelegate.bleReceiveTransparentData(_:devId:)"

    public let tuyaDeviceID: String
    public let payload: Data
    public let receivedAtUptimeNanoseconds: UInt64

    public var byteCount: Int { payload.count }

    /// The public SDK callback does not identify the underlying GATT service or
    /// characteristic, so it must never be relabeled as raw FD50 notify custody.
    public var authorizesRawFD50CharacteristicCustody: Bool { false }
    public var authorizesPhysicalFirstAcceptance: Bool { false }
    public var authorizesStationaryMapping: Bool { false }
    public var authorizesTelemetrySemantics: Bool { false }
    public var authorizesControlWrites: Bool { false }
    public var authorizesPairingResetOrUnbind: Bool { false }

    /// Creates evidence only for a non-empty callback belonging to the exact Tuya
    /// device expected by the already-linked account flow. No secret or DP meaning is
    /// accepted or inferred here.
    public init?(
        payload: Data,
        callbackDeviceID: String,
        expectedDeviceID: String,
        receivedAtUptimeNanoseconds: UInt64
    ) {
        let callback = callbackDeviceID.trimmingCharacters(in: .whitespacesAndNewlines)
        let expected = expectedDeviceID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !payload.isEmpty,
              !callback.isEmpty,
              !expected.isEmpty,
              callback == expected else {
            return nil
        }

        self.tuyaDeviceID = callback
        self.payload = payload
        self.receivedAtUptimeNanoseconds = receivedAtUptimeNanoseconds
    }
}
