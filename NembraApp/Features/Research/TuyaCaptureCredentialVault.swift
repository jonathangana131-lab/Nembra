import Foundation
import Security

struct TuyaCaptureCredential: Codable, Equatable {
    let deviceID: String
    let productID: String
    let uuid: String
    let localKey: String
}

/// Read-only companion to the existing one-time credential writer.
/// The secret local key never leaves Keychain and is not included in diagnostics.
enum TuyaCaptureCredentialVault {
    private static let service = "com.jonathangana131.nembra.capturelearn.tuya"
    private static let account = "selected-scooter"

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
              let data = item as? Data,
              let dictionary = try? JSONDecoder().decode([String: String].self, from: data),
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
