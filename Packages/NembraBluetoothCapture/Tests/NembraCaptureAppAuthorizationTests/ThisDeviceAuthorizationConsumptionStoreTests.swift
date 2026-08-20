import Foundation
import Testing
@testable import NembraCaptureAppAuthorization
#if canImport(Security)
import Security
#endif

@Suite("Capture app authorization replay store")
struct ThisDeviceAuthorizationConsumptionStoreTests {
    private let identity = String(repeating: "a", count: 64)

    @Test("first consume performs exactly one ThisDeviceOnly generic-password add")
    func firstConsume() throws {
        var capturedQuery: [String: Any]?
        var calls = 0
        let store = ThisDeviceAuthorizationConsumptionStore { query in
            calls += 1
            capturedQuery = query
            return ThisDeviceAuthorizationConsumptionStore.successStatus
        }

        #expect(try store.consumeIfUnseen(requestIdentitySHA256: identity))
        #expect(calls == 1)

        let query = try #require(capturedQuery)
        #expect(query.count == 5)
        #expect(query[accountKey] as? String == identity)
        #expect(query[serviceKey] as? String == ThisDeviceAuthorizationConsumptionStore.service)
        #expect(query[valueDataKey] as? Data == Data([0x01]))
        #expect(query[classKey] as? String == genericPasswordValue)
        #expect(query[accessibleKey] as? String == whenUnlockedThisDeviceOnlyValue)
        #expect(query[synchronizableKey] == nil)
        #expect(query[accessGroupKey] == nil)
        #expect(ThisDeviceAuthorizationConsumptionStore.service.hasSuffix(".v1"))
    }

    @Test("duplicate item is replay rejection without retry or mutation fallback")
    func duplicateIsAlreadyConsumed() throws {
        var calls = 0
        let store = ThisDeviceAuthorizationConsumptionStore { _ in
            calls += 1
            return ThisDeviceAuthorizationConsumptionStore.duplicateItemStatus
        }

        #expect(try store.consumeIfUnseen(requestIdentitySHA256: identity) == false)
        #expect(calls == 1)
    }

    @Test("unexpected Keychain status fails closed after one add attempt")
    func unexpectedStatusFailsClosed() {
        var calls = 0
        let store = ThisDeviceAuthorizationConsumptionStore { _ in
            calls += 1
            return -50
        }

        #expect(
            throws: NembraCaptureAppAuthorizationStoreError.keychainStatus(-50)
        ) {
            _ = try store.consumeIfUnseen(requestIdentitySHA256: identity)
        }
        #expect(calls == 1)
    }

    @Test("malformed request identity never reaches Keychain")
    func malformedIdentityFailsBeforeAdd() {
        var calls = 0
        let store = ThisDeviceAuthorizationConsumptionStore { _ in
            calls += 1
            return ThisDeviceAuthorizationConsumptionStore.successStatus
        }

        for invalid in [
            String(repeating: "a", count: 63),
            String(repeating: "A", count: 64),
            String(repeating: "g", count: 64),
            String(repeating: "0", count: 65),
        ] {
            #expect(
                throws: NembraCaptureAppAuthorizationStoreError.invalidRequestIdentitySHA256
            ) {
                _ = try store.consumeIfUnseen(requestIdentitySHA256: invalid)
            }
        }
        #expect(calls == 0)
    }

    private var classKey: String {
        #if canImport(Security)
        kSecClass as String
        #else
        "class"
        #endif
    }

    private var serviceKey: String {
        #if canImport(Security)
        kSecAttrService as String
        #else
        "svce"
        #endif
    }

    private var accountKey: String {
        #if canImport(Security)
        kSecAttrAccount as String
        #else
        "acct"
        #endif
    }

    private var accessibleKey: String {
        #if canImport(Security)
        kSecAttrAccessible as String
        #else
        "pdmn"
        #endif
    }

    private var valueDataKey: String {
        #if canImport(Security)
        kSecValueData as String
        #else
        "v_Data"
        #endif
    }

    private var synchronizableKey: String {
        #if canImport(Security)
        kSecAttrSynchronizable as String
        #else
        "sync"
        #endif
    }

    private var accessGroupKey: String {
        #if canImport(Security)
        kSecAttrAccessGroup as String
        #else
        "agrp"
        #endif
    }

    private var genericPasswordValue: String {
        #if canImport(Security)
        kSecClassGenericPassword as String
        #else
        "genp"
        #endif
    }

    private var whenUnlockedThisDeviceOnlyValue: String {
        #if canImport(Security)
        kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String
        #else
        "akpu"
        #endif
    }
}
