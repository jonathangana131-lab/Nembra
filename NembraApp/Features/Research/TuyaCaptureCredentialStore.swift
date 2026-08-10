import Foundation
import Security

/// Private, device-bound credential retained only on this iPhone for the next authenticated
/// Capture phase. This value must never be logged, exported, or promoted to telemetry evidence.
struct TuyaCaptureCredential: Codable, Equatable, Sendable {
    let deviceID: String
    let productID: String
    let uuid: String
    let localKey: String
    let secKey: String?

    var isUsable: Bool {
        !deviceID.isEmpty && !uuid.isEmpty && !localKey.isEmpty
    }

    /// TuyaOpen's current bound BLE path uses a 16-byte login/local key plus a separate
    /// 16-byte activation secret. This is only a material-completeness check; it does not
    /// establish that this scooter uses that exact protocol generation.
    var hasCandidateBoundSessionMaterial: Bool {
        localKey.utf8.count == 16 && secKey?.utf8.count == 16
    }
}

/// Narrow Keychain custody for the already-bound scooter credential returned by Tuya's
/// authorized account bridge. Replacement is update-first so a failed write never deletes a
/// previously valid credential.
enum TuyaCaptureCredentialStore {
    private static let service = "com.jonathangana131.nembra.capturelearn.tuya"
    private static let account = "selected-scooter"
    private static let secKeyNames = ["secKey", "seckey", "sec_key"]

    @discardableResult
    static func save(
        device: TuyaAccountBridge.LinkedDevice,
        detailMetadata: [String: Any]? = nil
    ) -> Bool {
        let existing = load()
        let returnedSecKey = secretValue(in: detailMetadata) ?? secretValue(in: device.raw)
        let preservedSecKey = existing?.deviceID == device.id ? existing?.secKey : nil
        let credential = TuyaCaptureCredential(
            deviceID: device.id,
            productID: device.productID,
            uuid: device.uuid,
            localKey: device.localKey,
            secKey: returnedSecKey ?? preservedSecKey
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

    private static func secretValue(in metadata: [String: Any]?) -> String? {
        guard let metadata else { return nil }
        for name in secKeyNames {
            if let value = metadata[name] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func secretValue(in raw: [String: AnyHashable]) -> String? {
        for name in secKeyNames {
            if let value = raw[name] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
