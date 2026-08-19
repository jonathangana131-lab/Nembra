import Testing
@testable import NembraBluetoothCapture

@Suite("Official Tuya SDK device catalog selection")
struct TuyaSDKDeviceCatalogSelectionTests {
    @Test("one complete record is retained for explicit operator selection")
    func oneCompleteDeviceIsRetained() throws {
        var subject = TuyaSDKDeviceCatalogAccumulator()
        subject.admit(id: " device-1 ", name: " Scooter ", productID: " product ", uuid: " uuid ")

        let result = try subject.finish(expectedHomeCount: 1, loadedHomeCount: 1, homeLoadFailureCount: 0)

        #expect(result.devices == [.init(id: "device-1", name: "Scooter", productID: "product", uuid: "uuid")])
    }

    @Test("owned and shared copies deduplicate without double selection")
    func duplicateOwnedAndSharedRecordDeduplicates() throws {
        var subject = TuyaSDKDeviceCatalogAccumulator()
        subject.admit(id: "device-1", name: "Z scooter", productID: "product", uuid: "uuid")
        subject.admit(id: "device-1", name: "A scooter", productID: "product", uuid: "uuid")

        let result = try subject.finish(expectedHomeCount: 2, loadedHomeCount: 2, homeLoadFailureCount: 0)

        #expect(result.encounteredDeviceCount == 1)
        #expect(result.devices.count == 1)
        #expect(result.devices[0].name == "A scooter")
    }

    @Test("an incomplete record remains visible in catalog completeness truth")
    func incompleteRecordIsCounted() throws {
        var subject = TuyaSDKDeviceCatalogAccumulator()
        subject.admit(id: nil, name: "Unknown", productID: nil, uuid: nil)
        subject.admit(id: "device-1", name: "Scooter", productID: "product", uuid: "uuid")

        let result = try subject.finish(expectedHomeCount: 1, loadedHomeCount: 1, homeLoadFailureCount: 0)

        #expect(result.devices.count == 1)
        #expect(result.incompleteDeviceCount == 1)
    }

    @Test("a partial duplicate is not hidden by a later complete copy")
    func partialDuplicateIsCounted() throws {
        var subject = TuyaSDKDeviceCatalogAccumulator()
        subject.admit(id: "device-1", name: "Scooter", productID: nil, uuid: nil)
        subject.admit(id: "device-1", name: "Scooter", productID: "product", uuid: "uuid")

        let result = try subject.finish(expectedHomeCount: 1, loadedHomeCount: 1, homeLoadFailureCount: 0)

        #expect(result.encounteredDeviceCount == 1)
        #expect(result.incompleteDeviceCount == 1)
    }

    @Test("a partial duplicate is counted regardless of callback order")
    func laterPartialDuplicateIsCounted() throws {
        var subject = TuyaSDKDeviceCatalogAccumulator()
        subject.admit(id: "device-1", name: "Scooter", productID: "product", uuid: "uuid")
        subject.admit(id: "device-1", name: "Scooter", productID: nil, uuid: nil)

        let result = try subject.finish(expectedHomeCount: 1, loadedHomeCount: 1, homeLoadFailureCount: 0)

        #expect(result.devices.count == 1)
        #expect(result.incompleteDeviceCount == 1)
    }

    @Test("conflicting required locator fields fail the entire catalog")
    func conflictingLocatorFailsClosed() {
        var subject = TuyaSDKDeviceCatalogAccumulator()
        subject.admit(id: "device-1", name: "Scooter", productID: "product-a", uuid: "uuid")
        subject.admit(id: "device-1", name: "Scooter", productID: "product-b", uuid: "uuid")

        #expect(throws: TuyaSDKDeviceCatalogSelectionError.conflictingRequiredLocator) {
            try subject.finish(expectedHomeCount: 1, loadedHomeCount: 1, homeLoadFailureCount: 0)
        }
    }

    @Test("any home failure rejects the otherwise complete device list")
    func partialHomeEnumerationFailsClosed() {
        var subject = TuyaSDKDeviceCatalogAccumulator()
        subject.admit(id: "device-1", name: "Scooter", productID: "product", uuid: "uuid")

        #expect(throws: TuyaSDKDeviceCatalogSelectionError.incompleteHomeEnumeration) {
            try subject.finish(expectedHomeCount: 2, loadedHomeCount: 1, homeLoadFailureCount: 1)
        }
    }

    @Test("multiple complete devices retain a stable choice order")
    func multipleDevicesHaveStableOrder() throws {
        var subject = TuyaSDKDeviceCatalogAccumulator()
        subject.admit(id: "device-2", name: "B", productID: "p2", uuid: "u2")
        subject.admit(id: "device-1", name: "A", productID: "p1", uuid: "u1")

        let result = try subject.finish(expectedHomeCount: 1, loadedHomeCount: 1, homeLoadFailureCount: 0)

        #expect(result.devices.map(\.id) == ["device-1", "device-2"])
    }
}
