import Foundation

/// Tuya's documented BLE GATT transport profile for the FD50 service family.
///
/// This is a provenance matcher only. Matching these UUIDs does not prove that a callback was
/// observed on the current authenticated generation, does not prove byte-for-byte raw-notify
/// custody, and never authorizes scooter telemetry semantics or control writes.
public enum TuyaFD50DocumentedGATTProfile {
    public static let serviceUUID = "FD50"
    public static let writeCharacteristicUUID = "00000001-0000-1001-8001-00805F9B07D0"
    public static let notifyCharacteristicUUID = "00000002-0000-1001-8001-00805F9B07D0"
    public static let readCharacteristicUUID = "00000003-0000-1001-8001-00805F9B07D0"

    /// Returns true only for Tuya's documented FD50 device-to-app notify characteristic.
    ///
    /// A caller may use this to validate characteristic provenance *if* an official SDK/adapter
    /// hook exposes the service and characteristic associated with bytes from the already-
    /// authenticated connection. It must not be used to open a competing CoreBluetooth session.
    public static func matchesNotify(
        serviceUUID candidateServiceUUID: String,
        characteristicUUID candidateCharacteristicUUID: String
    ) -> Bool {
        normalize(candidateServiceUUID) == normalize(serviceUUID)
            && normalize(candidateCharacteristicUUID) == normalize(notifyCharacteristicUUID)
    }

    /// UUID provenance alone cannot mint the stronger physical evidence classes.
    public static var authorizesAuthentication: Bool { false }
    public static var authorizesRawNotifyCustody: Bool { false }
    public static var authorizesTelemetrySemantics: Bool { false }
    public static var authorizesControlWrites: Bool { false }

    private static func normalize(_ uuid: String) -> String {
        uuid.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}
