import Foundation
import Security
import Testing
@testable import NembraCaptureAppAuthorization

@Suite("This-device Capture authorization consumption")
struct ThisDeviceAuthorizationConsumptionStoreTests {
    private let requestIdentity = String(repeating: "a", count: 64)

    @Test("first unseen request is atomically admitted with the exact device-bound keychain shape")
    func firstConsumption() throws {
        var calls = 0
        var capturedQuery: [String: Any] = [:]
        let store = ThisDeviceAuthorizationConsumptionStore(addItem: { query, _ in
            calls += 1
            capturedQuery = query as NSDictionary as! [String: Any]
            return errSecSuccess
        })

        #expect(try store.consumeRequestIdentityIfUnseen(requestIdentity))
        #expect(calls == 1)
        #expect(capturedQuery[kSecClass as String] as? String == kSecClassGenericPassword as String)
        #expect(capturedQuery[kSecAttrService as String] as? String == ThisDeviceAuthorizationConsumptionStore.keychainService)
        #expect(capturedQuery[kSecAttrAccount as String] as? String == requestIdentity)
        #expect(capturedQuery[kSecAttrAccessible as String] as? String == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        #expect(capturedQuery[kSecValueData as String] as? Data == Data([0x01]))
        #expect(capturedQuery[kSecAttrSynchronizable as String] == nil)
        #expect(capturedQuery[kSecAttrAccessGroup as String] == nil)
    }

    @Test("duplicate item is a replay and returns false without a fallback mutation")
    func duplicateConsumption() throws {
        var calls = 0
        let store = ThisDeviceAuthorizationConsumptionStore(addItem: { _, _ in
            calls += 1
            return errSecDuplicateItem
        })

        #expect(try !store.consumeRequestIdentityIfUnseen(requestIdentity))
        #expect(calls == 1)
    }

    @Test("unexpected keychain status fails closed")
    func keychainFailure() {
        var calls = 0
        let store = ThisDeviceAuthorizationConsumptionStore(addItem: { _, _ in
            calls += 1
            return errSecNotAvailable
        })

        #expect(
            throws: ThisDeviceAuthorizationConsumptionStoreError.keychainStatus(errSecNotAvailable)
        ) {
            _ = try store.consumeRequestIdentityIfUnseen(requestIdentity)
        }
        #expect(calls == 1)
    }

    @Test("noncanonical request identity is rejected before keychain contact")
    func invalidIdentity() {
        var calls = 0
        let store = ThisDeviceAuthorizationConsumptionStore(addItem: { _, _ in
            calls += 1
            return errSecSuccess
        })

        #expect(throws: ThisDeviceAuthorizationConsumptionStoreError.invalidRequestIdentity) {
            _ = try store.consumeRequestIdentityIfUnseen(String(repeating: "A", count: 64))
        }
        #expect(calls == 0)
    }

    @Test("source keeps replay consumption to one add-only primitive")
    func sourceContract() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(
                "Sources/NembraCaptureAppAuthorization/ThisDeviceAuthorizationConsumptionStore.swift"
            )
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("SecItemAdd"))
        #expect(!source.contains("SecItemDelete"))
        #expect(!source.contains("SecItemUpdate"))
        #expect(!source.contains("kSecAttrSynchronizable"))
        #expect(!source.contains("kSecAttrAccessGroup"))
        #expect(source.contains("kSecAttrAccessibleWhenUnlockedThisDeviceOnly"))
        #expect(source.contains("request.requestIdentitySHA256"))
    }
}
