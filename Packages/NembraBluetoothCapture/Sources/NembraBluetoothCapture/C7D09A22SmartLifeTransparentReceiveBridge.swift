import Foundation

/// Safe handoff for Tuya's documented Smart Life BLE transparent-receive callback during
/// the C7D09A22 authenticated read-only field preflight.
///
/// The bridge preserves callback bytes and chronology for the exact activated Tuya device.
/// It never upgrades SDK-owned callback data into raw FD50 characteristic custody: the public
/// Smart Life callback does not expose the underlying GATT service/characteristic tuple.
/// Physical first acceptance therefore still requires independently observed raw subscribed
/// notifications plus same-transport custody through the canonical evidence assembler.
public struct C7D09A22SmartLifeTransparentReceiveBridge: Sendable {
    public enum RecordResult: Equatable, Sendable {
        case recorded
        case rejectedWrongDeviceOrEmptyPayload
        case rejectedStaleOrReplayedCallback
    }

    private let expectedDeviceID: String
    private var ledger: TuyaSmartLifeTransparentReceiveObservationLedger

    public init?(
        expectedDeviceID: String,
        sdkConnectionStartedAtUptimeNanoseconds: UInt64
    ) {
        let normalizedDeviceID = expectedDeviceID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedDeviceID.isEmpty,
              let ledger = TuyaSmartLifeTransparentReceiveObservationLedger(
                  expectedDeviceID: normalizedDeviceID,
                  sdkConnectionStartedAtUptimeNanoseconds: sdkConnectionStartedAtUptimeNanoseconds
              ) else {
            return nil
        }

        self.expectedDeviceID = normalizedDeviceID
        self.ledger = ledger
    }

    /// Feed this method only from Tuya's documented
    /// `ThingSmartBLEManagerDelegate.bleReceiveTransparentData(_:devId:)` callback.
    /// No BLE write, DP publish, pairing, reset, removal, or unbind operation occurs here.
    @discardableResult
    public mutating func recordDocumentedTransparentReceive(
        payload: Data,
        callbackDeviceID: String,
        receivedAtUptimeNanoseconds: UInt64
    ) -> RecordResult {
        guard let receipt = TuyaSmartLifeTransparentReceiveReceipt(
            payload: payload,
            callbackDeviceID: callbackDeviceID,
            expectedDeviceID: expectedDeviceID,
            receivedAtUptimeNanoseconds: receivedAtUptimeNanoseconds
        ) else {
            return .rejectedWrongDeviceOrEmptyPayload
        }

        guard ledger.record(receipt) else {
            return .rejectedStaleOrReplayedCallback
        }
        return .recorded
    }

    public var snapshot: TuyaSmartLifeTransparentReceiveObservationLedger.Snapshot {
        ledger.snapshot
    }

    /// Deliberately false: SDK transparent receive is diagnostic transport evidence only.
    public var authorizesRawFD50CharacteristicCustody: Bool { false }
    public var authorizesPhysicalFirstAcceptance: Bool { false }
    public var authorizesStationaryMapping: Bool { false }
    public var authorizesTelemetrySemantics: Bool { false }
    public var authorizesControlWrites: Bool { false }
    public var authorizesPairingResetOrUnbind: Bool { false }
}
