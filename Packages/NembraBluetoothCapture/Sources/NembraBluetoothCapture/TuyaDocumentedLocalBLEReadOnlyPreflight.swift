import Foundation

/// Semantics-free admission for the documented Smart Life App SDK local-BLE connection path.
///
/// This type deliberately models only facts the app can obtain from the user's own authenticated
/// Smart Life SDK session before Nembra arms its receive-only capture. It does not carry account
/// credentials, local/session keys, DP identifiers, decoded scooter values, or write intent.
///
/// Important identity boundary:
/// - `selectedPeripheralIdentifier` is CoreBluetooth's local `CBPeripheral.identifier`.
/// - `accountDeviceUUID` is the Tuya/Smart Life account device UUID used by the SDK.
/// These identifiers are intentionally NOT compared for textual equality. They are different
/// identity domains. The app adapter must instead attest that its documented SDK-backed device
/// resolution bound the selected CoreBluetooth peripheral to the linked account device.
///
/// Documented SDK mapping for the app adapter:
/// - `TuyaSmartBLEManager.deviceStatue(withUUID:)` -> `sdkReportsLocalBLEOnline`
/// - `TuyaSmartBLEManager.connectBLE(withUUID:productKey:success:failure:)` may be used only to
///   establish the already-activated device's BLE connection when the status above is false.
/// - `productKey` must come from that same linked account device record. Merely knowing or guessing
///   a product key from advertising, public metadata, or another device never satisfies admission.
///
/// Pairing/activation, DP publishing, transparent writes, OTA, reset, removal and unbind are not
/// part of this contract and cannot be authorized by a successful verdict.
public struct TuyaDocumentedLocalBLEReadOnlySnapshot: Equatable, Sendable {
    public let selectedPeripheralIdentifier: String
    public let accountDeviceUUID: String
    public let productKey: String
    public let connectionGeneration: UInt64
    public let authenticationMethod: TuyaReadOnlyAuthenticationMethod
    public let accountSessionAuthenticated: Bool
    public let sdkAdapterProvesSelectedPeripheralBinding: Bool
    public let sdkAdapterProvesProductKeyBelongsToAccountDevice: Bool
    public let sdkReportsLocalBLEOnline: Bool

    public init(
        selectedPeripheralIdentifier: String,
        accountDeviceUUID: String,
        productKey: String,
        connectionGeneration: UInt64,
        authenticationMethod: TuyaReadOnlyAuthenticationMethod,
        accountSessionAuthenticated: Bool,
        sdkAdapterProvesSelectedPeripheralBinding: Bool,
        sdkAdapterProvesProductKeyBelongsToAccountDevice: Bool,
        sdkReportsLocalBLEOnline: Bool
    ) {
        self.selectedPeripheralIdentifier = selectedPeripheralIdentifier
        self.accountDeviceUUID = accountDeviceUUID
        self.productKey = productKey
        self.connectionGeneration = connectionGeneration
        self.authenticationMethod = authenticationMethod
        self.accountSessionAuthenticated = accountSessionAuthenticated
        self.sdkAdapterProvesSelectedPeripheralBinding = sdkAdapterProvesSelectedPeripheralBinding
        self.sdkAdapterProvesProductKeyBelongsToAccountDevice = sdkAdapterProvesProductKeyBelongsToAccountDevice
        self.sdkReportsLocalBLEOnline = sdkReportsLocalBLEOnline
    }
}

public enum TuyaDocumentedLocalBLEReadOnlyPreflight {
    public enum Verdict: Equatable, Sendable {
        /// The official SDK reports that the already-bound account device is locally connected over
        /// BLE and the app adapter has bound that SDK device to the package-owned CoreBluetooth
        /// selection/generation. Receive-only capture may proceed to the stronger authenticated
        /// application-evidence gate.
        case readyForAuthenticatedReceiveObservation
        case blocked(reason: String)
    }

    public static func verdict(for snapshot: TuyaDocumentedLocalBLEReadOnlySnapshot) -> Verdict {
        let selectedPeripheralIdentifier = canonicalIdentity(snapshot.selectedPeripheralIdentifier)
        let accountDeviceUUID = canonicalIdentity(snapshot.accountDeviceUUID)

        guard !selectedPeripheralIdentifier.isEmpty else {
            return .blocked(reason: "A selected CoreBluetooth peripheral identifier is required.")
        }
        guard !accountDeviceUUID.isEmpty else {
            return .blocked(reason: "A linked Tuya account device UUID is required.")
        }
        guard !snapshot.productKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .blocked(reason: "The documented Smart Life BLE connect path requires the account-backed product key.")
        }
        guard snapshot.connectionGeneration > 0 else {
            return .blocked(reason: "A package-owned BLE connection generation is required.")
        }
        guard snapshot.accountSessionAuthenticated else {
            return .blocked(reason: "The user's Smart Life SDK account session is not authenticated.")
        }
        guard snapshot.authenticationMethod == .smartLifeAppSDK else {
            return .blocked(reason: "Only documented Smart Life App SDK provenance can admit the BLE transport.")
        }
        guard snapshot.sdkAdapterProvesSelectedPeripheralBinding else {
            return .blocked(reason: "The Smart Life adapter has not proven that the selected CoreBluetooth peripheral is the linked account device.")
        }
        guard snapshot.sdkAdapterProvesProductKeyBelongsToAccountDevice else {
            return .blocked(reason: "The Smart Life adapter has not proven that the product key came from the same linked account device.")
        }
        guard snapshot.sdkReportsLocalBLEOnline else {
            return .blocked(reason: "Smart Life SDK does not report the linked device locally connected over BLE.")
        }
        return .readyForAuthenticatedReceiveObservation
    }

    private static func canonicalIdentity(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    // This preflight is observation-only and never grants mutation or semantic authority.
    public static var authorizesPairingOrActivation: Bool { false }
    public static var authorizesDPWrites: Bool { false }
    public static var authorizesTransparentWrites: Bool { false }
    public static var authorizesFirmwareUpdate: Bool { false }
    public static var authorizesResetRemovalOrUnbind: Bool { false }
    public static var authorizesTelemetrySemantics: Bool { false }
    public static var authorizesPhysicalFirstAcceptance: Bool { false }
}
