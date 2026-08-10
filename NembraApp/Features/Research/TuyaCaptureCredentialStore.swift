import Foundation
import Security

/// Private, device-bound credential retained only on this iPhone for the next authenticated
/// Capture phase. This value must never be logged, exported, or promoted to telemetry evidence.
struct TuyaCaptureCredential: Codable, Equatable, Sendable {
    let deviceID: String
    let productID: String
    let uuid: String
    let localKey: String

    var isUsable: Bool {
        !deviceID.isEmpty && !uuid.isEmpty && !localKey.isEmpty
    }
}

/// Narrow Keychain custody for the already-bound scooter credential returned by Tuya's
/// authorized account bridge. Replacement is update-first so a failed write never deletes a
/// previously valid credential.
enum TuyaCaptureCredentialStore {
    private static let service = "com.jonathangana131.nembra.capturelearn.tuya"
    private static let account = "selected-scooter"

    @discardableResult
    static func save(device: TuyaAccountBridge.LinkedDevice) -> Bool {
        let credential = TuyaCaptureCredential(
            deviceID: device.id,
            productID: device.productID,
            uuid: device.uuid,
            localKey: device.localKey
        )
        guard credential.isUsable,
              let data = try? JSONEncoder().encode(credential) else {
            return false
        }

        let query = baseQuery
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }
        guard updateStatus == errSecItemNotFound else {
            return false
        }

        var item = query
        for (key, value) in attributes {
            item[key] = value
        }
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static func load() -> TuyaCaptureCredential? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let credential = try? JSONDecoder().decode(TuyaCaptureCredential.self, from: data),
              credential.isUsable else {
            return nil
        }
        return credential
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
