import Foundation
import NembraBluetoothCapture
import Security

public enum ThisDeviceAuthorizationConsumptionStoreError: Error, Equatable, Sendable {
    case invalidRequestIdentity
    case keychainStatus(OSStatus)
}

/// App-owned, device-bound replay consumption for one externally authorized Capture attempt.
///
/// The atomicity boundary is one generic-password `SecItemAdd`: the first add wins and a duplicate
/// item means the same request identity was already consumed. This target does not authorize OFF1
/// or widen any Bluetooth/Tuya authority; it only implements the persistence seam required by the
/// field-authorization verifier.
public final class ThisDeviceAuthorizationConsumptionStore:
    AuthenticatedStationaryCaptureAuthorizationConsumptionStore
{
    public static let keychainService = "com.nembra.capture.authorization-consumption.v1"

    typealias AddItem = (CFDictionary, UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus

    private let addItem: AddItem

    public convenience init() {
        self.init(addItem: { query, result in
            SecItemAdd(query, result)
        })
    }

    init(addItem: @escaping AddItem) {
        self.addItem = addItem
    }

    public func consumeIfUnseen(
        _ request: AuthenticatedStationaryCaptureAuthorizationConsumptionRequest
    ) throws -> Bool {
        try consumeRequestIdentityIfUnseen(request.requestIdentitySHA256)
    }

    func consumeRequestIdentityIfUnseen(_ requestIdentitySHA256: String) throws -> Bool {
        guard Self.isCanonicalSHA256(requestIdentitySHA256) else {
            throw ThisDeviceAuthorizationConsumptionStoreError.invalidRequestIdentity
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: requestIdentitySHA256,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: Data([0x01]),
        ]

        switch addItem(query as CFDictionary, nil) {
        case errSecSuccess:
            return true
        case errSecDuplicateItem:
            return false
        case let status:
            throw ThisDeviceAuthorizationConsumptionStoreError.keychainStatus(status)
        }
    }

    private static func isCanonicalSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { byte in
            (48 ... 57).contains(byte) || (97 ... 102).contains(byte)
        }
    }
}
