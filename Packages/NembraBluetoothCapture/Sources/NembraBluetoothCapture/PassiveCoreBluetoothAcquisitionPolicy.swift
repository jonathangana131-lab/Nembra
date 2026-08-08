@preconcurrency import CoreBluetooth
import Foundation

/// The only characteristic-level operations permitted during Nembra's passive
/// ES80 acquisition phase.
///
/// CoreBluetooth notification subscription can update the GATT Client
/// Characteristic Configuration descriptor internally. That is transport
/// subscription state, not an application characteristic command. This policy
/// still exposes no characteristic-value write operation.
public struct PassiveCoreBluetoothCharacteristicPlan: Equatable, Sendable {
    public let shouldReadValue: Bool
    public let shouldSubscribeForValueUpdates: Bool
    public let shouldDiscoverDescriptors: Bool

    public init(
        shouldReadValue: Bool,
        shouldSubscribeForValueUpdates: Bool,
        shouldDiscoverDescriptors: Bool
    ) {
        self.shouldReadValue = shouldReadValue
        self.shouldSubscribeForValueUpdates = shouldSubscribeForValueUpdates
        self.shouldDiscoverDescriptors = shouldDiscoverDescriptors
    }
}

public enum PassiveCoreBluetoothAcquisitionPolicy {
    /// The first physical fingerprint must not assume FD50, A201, 1910, F1/F2,
    /// or any other family. A nil foreground service filter intentionally asks
    /// CoreBluetooth for all nearby advertisements during an explicit research
    /// session so unknown ES80 service evidence is not filtered out.
    ///
    /// This is a foreground-research policy, not a background reconnect policy.
    public static var foregroundResearchServiceFilter: [CBUUID]? { nil }

    /// Duplicate advertisement callbacks are needed only when measuring real
    /// advertisement cadence/change behavior. Apple documents a battery cost,
    /// so Nembra keeps this opt-in rather than making it a production default.
    public static func foregroundResearchScanOptions(
        captureAdvertisementCadence: Bool
    ) -> [String: Any] {
        captureAdvertisementCadence
            ? [CBCentralManagerScanOptionAllowDuplicatesKey: true]
            : [:]
    }

    /// A finite discovery/read/subscription pass should either make progress or
    /// terminate explicitly. This deadline is restarted only when one tracked
    /// finite operation completes; it never watches ordinary notification quiet
    /// periods after the acquisition ledger reaches ready.
    public static let defaultAcquisitionProgressTimeout: TimeInterval = 15

    /// Converts a user/research deadline to the nanosecond domain accepted by
    /// Task.sleep without overflowing or trapping on Double→UInt64 conversion.
    /// No arbitrary product timeout is imposed here; representability is the
    /// boundary. Sub-nanosecond, non-finite, zero, and negative values fail.
    public static func connectionTimeoutNanoseconds(
        _ timeout: TimeInterval
    ) -> UInt64? {
        timeoutNanoseconds(timeout)
    }

    /// Uses the same strict deadline conversion for the finite GATT acquisition
    /// progress watchdog. Keeping this separate from the connection API makes the
    /// two lifecycle deadlines explicit even though their numeric conversion is
    /// identical.
    public static func acquisitionProgressTimeoutNanoseconds(
        _ timeout: TimeInterval
    ) -> UInt64? {
        timeoutNanoseconds(timeout)
    }

    private static func timeoutNanoseconds(_ timeout: TimeInterval) -> UInt64? {
        guard timeout.isFinite, timeout > 0 else { return nil }
        let nanoseconds = timeout * 1_000_000_000
        guard nanoseconds.isFinite,
              nanoseconds >= 1,
              nanoseconds < Double(UInt64.max) else {
            return nil
        }
        return UInt64(nanoseconds)
    }

    public static func plan(for characteristic: CBCharacteristic) -> PassiveCoreBluetoothCharacteristicPlan {
        let properties = characteristic.properties
        return PassiveCoreBluetoothCharacteristicPlan(
            shouldReadValue: properties.contains(.read),
            shouldSubscribeForValueUpdates: properties.contains(.notify) || properties.contains(.indicate),
            shouldDiscoverDescriptors: true
        )
    }
}
