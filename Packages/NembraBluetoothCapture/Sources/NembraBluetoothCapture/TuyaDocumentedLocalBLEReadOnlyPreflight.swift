import Foundation

/// Semantics-free admission for the documented Smart Life App SDK local-BLE connection path.
///
/// This type deliberately models only facts the app can obtain from the user's own authenticated
/// Smart Life SDK session before Nembra arms its receive-only capture. It does not carry account
/// credentials, local/session keys, DP identifiers, decoded scooter values, or write intent.
///
/// Documented SDK mapping for the app adapter:
/// - `TuyaSmartBLEManager.deviceStatue(withUUID:)` -> `sdkReportsLocalBLEOnline`
/// - `TuyaSmartBLEManager.connectBLE(withUUID:productKey:success:failure:)` may be used only to
///   establish the already-activated device's BLE connection when the status above is false.
///
/// Pairing/activation, DP publishing, transparent writes, OTA, reset, removal and unbind are not
/// part of this contract and cannot be authorized by a successful verdict.
public struct TuyaDocumentedLocalBLEReadOnlySnapshot: Equatable, Sendable {
    public let selectedPeripheralUUID: String
    public let accountMatchedDeviceUUID: String
    public let productKey: String
    public let connectionGeneration: UInt64
    public let authenticationMethod: TuyaAuthenticationProvenance
    public let accountSessionAuthenticated: Bool
    public let boundAccountMatchesSelectedPeripheral: Bool
    public let sdkReportsLocalBLEOnline: Bool

    public init(
        selectedPeripheralUUID: String,
        accountMatchedDeviceUUID: String,
        productKey: String,
        connectionGeneration: UInt64,
        authenticationMethod: TuyaAuthenticationProvenance,
        accountSessionAuthenticated: Bool,
        boundAccountMatchesSelectedPeripheral: Bool,
        sdkReportsLocalBLEOnline: Bool
    ) {
        self.selectedPeripheralUUID = selectedPeripheralUUID
        self.accountMatchedDeviceUUID = accountMatchedDeviceUUID
        self.productKey = productKey
        self.connectionGeneration = connectionGeneration
        self.authenticationMethod = authenticationMethod
        self.accountSessionAuthenticated = accountSessionAuthenticated
        self.boundAccountMatchesSelectedPeripheral = boundAccountMatchesSelectedPeripheral
        self.sdkReportsLocalBLEOnline = sdkReportsLocalBLEOnline
    }
}

public enum TuyaDocumentedLocalBLEReadOnlyPreflight {
    public enum Verdict: Equatable, Sendable {
        /// The official SDK reports that the already-bound, account-matched device is locally
        /// connected over BLE on the package-owned generation. Receive-only capture may proceed to
        /// the stronger authenticated application-evidence gate.
        case readyForAuthenticatedReceiveObservation
        case blocked(reason: String)
    }

    public static func verdict(for snapshot: TuyaDocumentedLocalBLEReadOnlySnapshot) -> Verdict {
        let selected = canonicalUUID(snapshot.selectedPeripheralUUID)
        let accountMatched = canonicalUUID(snapshot.accountMatchedDeviceUUID)

        guard !selected.isEmpty, !accountMatched.isEmpty else {
            return .blocked(reason: "Selected and account-matched Tuya device UUIDs are required.")
        }
        guard selected == accountMatched else {
            return .blocked(reason: "The user's linked Tuya device does not match the selected BLE peripheral.")
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
        guard snapshot.boundAccountMatchesSelectedPeripheral else {
            return .blocked(reason: "The linked Smart Life account has not proven custody of the selected peripheral.")
        }
        guard snapshot.authenticationMethod == .smartLifeAppSDK else {
            return .blocked(reason: "Only documented Smart Life App SDK provenance can admit the BLE transport.")
        }
        guard snapshot.sdkReportsLocalBLEOnline else {
            return .blocked(reason: "Smart Life SDK does not report the selected device locally connected over BLE.")
        }
        return .readyForAuthenticatedReceiveObservation
    }

    private static func canonicalUUID(_ value: String) -> String {
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
