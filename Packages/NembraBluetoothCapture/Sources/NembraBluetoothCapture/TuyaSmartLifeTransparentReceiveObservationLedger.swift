import Foundation

/// Read-only observation ledger for Tuya's documented Smart Life BLE transparent receive callback.
///
/// This ledger answers one narrow field question: while the official SDK-owned BLE session is
/// alive, do byte-preserving device-to-app payload callbacks continue strictly beyond the
/// historical C7D09A22 unauthenticated rejection horizon?
///
/// It deliberately does not equate the SDK callback with a raw FD50 characteristic notification.
/// Therefore even a positive post-horizon observation is diagnostic transport evidence only and
/// cannot mint raw-GATT custody, physical first acceptance, DP semantics, mapping, or controls.
public struct TuyaSmartLifeTransparentReceiveObservationLedger: Sendable {
    public static let c7d09a22HistoricalRejectionNanoseconds: UInt64 = 30_000_000_000

    public struct Snapshot: Equatable, Sendable {
        public let tuyaDeviceID: String
        public let sdkConnectionStartedAtUptimeNanoseconds: UInt64
        public let payloadCount: Int
        public let totalByteCount: Int
        public let latestPayloadAtUptimeNanoseconds: UInt64?
        public let hasPayloadStrictlyBeyondHistoricalRejectionHorizon: Bool

        public var authorizesRawFD50CharacteristicCustody: Bool { false }
        public var authorizesPhysicalFirstAcceptance: Bool { false }
        public var authorizesStationaryMapping: Bool { false }
        public var authorizesTelemetrySemantics: Bool { false }
        public var authorizesControlWrites: Bool { false }
        public var authorizesPairingResetOrUnbind: Bool { false }
    }

    private let expectedDeviceID: String
    private let sdkConnectionStartedAtUptimeNanoseconds: UInt64
    private var payloadCount = 0
    private var totalByteCount = 0
    private var latestPayloadAtUptimeNanoseconds: UInt64?
    private var hasPostHorizonPayload = false

    public init?(expectedDeviceID: String, sdkConnectionStartedAtUptimeNanoseconds: UInt64) {
        let normalized = expectedDeviceID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        self.expectedDeviceID = normalized
        self.sdkConnectionStartedAtUptimeNanoseconds = sdkConnectionStartedAtUptimeNanoseconds
    }

    /// Records only an already-validated Smart Life transparent-receive receipt for the same
    /// linked Tuya device and the current SDK connection chronology.
    ///
    /// Callback times must advance strictly. A receipt replayed at the same observation instant
    /// cannot be counted again as independent authenticated application evidence.
    @discardableResult
    public mutating func record(_ receipt: TuyaSmartLifeTransparentReceiveReceipt) -> Bool {
        guard receipt.tuyaDeviceID == expectedDeviceID,
              receipt.receivedAtUptimeNanoseconds >= sdkConnectionStartedAtUptimeNanoseconds else {
            return false
        }

        if let latestPayloadAtUptimeNanoseconds,
           receipt.receivedAtUptimeNanoseconds <= latestPayloadAtUptimeNanoseconds {
            return false
        }

        payloadCount += 1
        totalByteCount += receipt.byteCount
        latestPayloadAtUptimeNanoseconds = receipt.receivedAtUptimeNanoseconds

        let elapsed = receipt.receivedAtUptimeNanoseconds - sdkConnectionStartedAtUptimeNanoseconds
        if elapsed > Self.c7d09a22HistoricalRejectionNanoseconds {
            hasPostHorizonPayload = true
        }
        return true
    }

    public var snapshot: Snapshot {
        Snapshot(
            tuyaDeviceID: expectedDeviceID,
            sdkConnectionStartedAtUptimeNanoseconds: sdkConnectionStartedAtUptimeNanoseconds,
            payloadCount: payloadCount,
            totalByteCount: totalByteCount,
            latestPayloadAtUptimeNanoseconds: latestPayloadAtUptimeNanoseconds,
            hasPayloadStrictlyBeyondHistoricalRejectionHorizon: hasPostHorizonPayload
        )
    }
}
