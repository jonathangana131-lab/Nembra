import Foundation
import Security

struct TuyaCaptureCredential: Codable, Equatable {
    let deviceID: String
    let productID: String
    let uuid: String
    let localKey: String
}

/// Private persistence for the already-bound scooter identity used by the next
/// authenticated stationary Capture gate.
///
/// The local key remains Keychain-only and is never placed in exported diagnostics.
enum TuyaCaptureCredentialVault {
    private static let service = "com.jonathangana131.nembra.capturelearn.tuya"
    private static let account = "selected-scooter"

    static func save(device: TuyaAccountBridge.LinkedDevice) -> Bool {
        guard !device.id.isEmpty,
              !device.productID.isEmpty,
              !device.uuid.isEmpty,
              !device.localKey.isEmpty else {
            return false
        }

        let credential = TuyaCaptureCredential(
            deviceID: device.id,
            productID: device.productID,
            uuid: device.uuid,
            localKey: device.localKey
        )
        guard let data = try? JSONEncoder().encode(credential) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)

        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
    }

    static func load() -> TuyaCaptureCredential? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else {
            return nil
        }

        if let credential = try? JSONDecoder().decode(TuyaCaptureCredential.self, from: data) {
            return credential
        }

        // Compatibility with the immediately preceding field build, which stored
        // the same four values as a String dictionary.
        guard let dictionary = try? JSONDecoder().decode([String: String].self, from: data),
              let deviceID = dictionary["deviceID"],
              let productID = dictionary["productID"],
              let uuid = dictionary["uuid"],
              let localKey = dictionary["localKey"] else {
            return nil
        }

        return TuyaCaptureCredential(
            deviceID: deviceID,
            productID: productID,
            uuid: uuid,
            localKey: localKey
        )
    }
}
