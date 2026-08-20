import Foundation
import NembraBluetoothCapture
#if canImport(Security)
import Security
#endif

public enum NembraCaptureAppAuthorizationStoreError: Error, Equatable, Sendable {
    case invalidRequestIdentitySHA256
    case keychainStatus(Int32)
}

/// App-owned durable replay boundary for one signed Capture authorization.
///
/// The Keychain server provides the atomicity: a generic-password item is added exactly once for
/// the request identity. A duplicate item means the authorization was already consumed. There is
/// deliberately no delete, update, synchronization, access-group, or fallback path here.
public final class ThisDeviceAuthorizationConsumptionStore:
    AuthenticatedStationaryCaptureAuthorizationConsumptionStore
{
    public static let service = "com.nembra.capture.authorization-consumption.v1"

    package typealias AddOperation = ([String: Any]) -> Int32

    private let addOperation: AddOperation

    public convenience init() {
        self.init(addOperation: Self.systemAdd)
    }

    package init(addOperation: @escaping AddOperation) {
        self.addOperation = addOperation
    }

    public func consumeIfUnseen(
        _ request: AuthenticatedStationaryCaptureAuthorizationConsumptionRequest
    ) throws -> Bool {
        try consumeIfUnseen(requestIdentitySHA256: request.requestIdentitySHA256)
    }

    package func consumeIfUnseen(requestIdentitySHA256: String) throws -> Bool {
        guard Self.isCanonicalSHA256(requestIdentitySHA256) else {
            throw NembraCaptureAppAuthorizationStoreError.invalidRequestIdentitySHA256
        }

        let status = addOperation(Self.makeAddQuery(account: requestIdentitySHA256))
        switch status {
        case Self.successStatus:
            return true
        case Self.duplicateItemStatus:
            return false
        default:
            throw NembraCaptureAppAuthorizationStoreError.keychainStatus(status)
        }
    }

    package static var successStatus: Int32 {
        #if canImport(Security)
        errSecSuccess
        #else
        0
        #endif
    }

    package static var duplicateItemStatus: Int32 {
        #if canImport(Security)
        errSecDuplicateItem
        #else
        -25_299
        #endif
    }

    package static func makeAddQuery(account: String) -> [String: Any] {
        #if canImport(Security)
        return [
            kSecClass as String: kSecClassGenericPassword as String,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String,
            kSecValueData as String: Data([0x01]),
        ]
        #else
        // Stable stand-ins exist only so deterministic package tests can run on non-Apple hosts.
        // Production Capture is iOS-only and the default add path below fails closed here.
        return [
            "class": "genp",
            "svce": service,
            "acct": account,
            "pdmn": "akpu",
            "v_Data": Data([0x01]),
        ]
        #endif
    }

    private static func systemAdd(_ query: [String: Any]) -> Int32 {
        #if canImport(Security)
        SecItemAdd(query as CFDictionary, nil)
        #else
        // errSecUnimplemented. This path is never field authority; it only preserves fail-closed
        // source portability for non-Apple package tooling.
        -4
        #endif
    }

    private static func isCanonicalSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (0x30 ... 0x39).contains($0) || (0x61 ... 0x66).contains($0)
        }
    }
}
