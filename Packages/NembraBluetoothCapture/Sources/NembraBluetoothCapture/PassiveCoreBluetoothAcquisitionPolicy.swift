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

    public static func plan(for characteristic: CBCharacteristic) -> PassiveCoreBluetoothCharacteristicPlan {
        let properties = characteristic.properties
        return PassiveCoreBluetoothCharacteristicPlan(
            shouldReadValue: properties.contains(.read),
            shouldSubscribeForValueUpdates: properties.contains(.notify) || properties.contains(.indicate),
            shouldDiscoverDescriptors: true
        )
    }
}
