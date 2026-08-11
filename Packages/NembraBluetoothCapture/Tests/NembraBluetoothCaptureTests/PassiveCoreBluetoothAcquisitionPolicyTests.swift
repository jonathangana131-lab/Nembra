@preconcurrency import CoreBluetooth
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive CoreBluetooth acquisition policy")
struct PassiveCoreBluetoothAcquisitionPolicyTests {
    @Test("unknown first fingerprint does not hard-code a service family")
    func noFingerprintAssumption() {
        #expect(PassiveCoreBluetoothAcquisitionPolicy.foregroundResearchServiceFilter == nil)
    }

    @Test("duplicate advertisement collection is explicit and opt-in")
    func duplicateAdvertisementsAreOptIn() {
        let ordinary = PassiveCoreBluetoothAcquisitionPolicy.foregroundResearchScanOptions(
            captureAdvertisementCadence: false
        )
        let cadence = PassiveCoreBluetoothAcquisitionPolicy.foregroundResearchScanOptions(
            captureAdvertisementCadence: true
        )

        #expect(ordinary.isEmpty)
        #expect((cadence[CBCentralManagerScanOptionAllowDuplicatesKey] as? Bool) == true)
    }

    @Test("connection timeout conversion rejects non-finite zero negative sub-nanosecond and overflow values")
    func connectionTimeoutValidation() {
        #expect(PassiveCoreBluetoothAcquisitionPolicy.connectionTimeoutNanoseconds(12) == 12_000_000_000)
        #expect(PassiveCoreBluetoothAcquisitionPolicy.connectionTimeoutNanoseconds(0.000000001) == 1)
        #expect(PassiveCoreBluetoothAcquisitionPolicy.connectionTimeoutNanoseconds(0) == nil)
        #expect(PassiveCoreBluetoothAcquisitionPolicy.connectionTimeoutNanoseconds(-1) == nil)
        #expect(PassiveCoreBluetoothAcquisitionPolicy.connectionTimeoutNanoseconds(0.0000000001) == nil)
        #expect(PassiveCoreBluetoothAcquisitionPolicy.connectionTimeoutNanoseconds(.infinity) == nil)
        #expect(PassiveCoreBluetoothAcquisitionPolicy.connectionTimeoutNanoseconds(.nan) == nil)
        #expect(PassiveCoreBluetoothAcquisitionPolicy.connectionTimeoutNanoseconds(Double.greatestFiniteMagnitude) == nil)
    }

    @Test("finite acquisition progress timeout is explicit and uses the strict deadline conversion")
    func acquisitionProgressTimeoutValidation() {
        #expect(PassiveCoreBluetoothAcquisitionPolicy.defaultAcquisitionProgressTimeout == 15)
        #expect(PassiveCoreBluetoothAcquisitionPolicy.acquisitionProgressTimeoutNanoseconds(15) == 15_000_000_000)
        #expect(PassiveCoreBluetoothAcquisitionPolicy.acquisitionProgressTimeoutNanoseconds(0.000000001) == 1)
        #expect(PassiveCoreBluetoothAcquisitionPolicy.acquisitionProgressTimeoutNanoseconds(0) == nil)
        #expect(PassiveCoreBluetoothAcquisitionPolicy.acquisitionProgressTimeoutNanoseconds(-1) == nil)
        #expect(PassiveCoreBluetoothAcquisitionPolicy.acquisitionProgressTimeoutNanoseconds(.infinity) == nil)
        #expect(PassiveCoreBluetoothAcquisitionPolicy.acquisitionProgressTimeoutNanoseconds(.nan) == nil)
        #expect(PassiveCoreBluetoothAcquisitionPolicy.acquisitionProgressTimeoutNanoseconds(Double.greatestFiniteMagnitude) == nil)
    }

    @Test("readable notifying characteristic permits read subscription and descriptor discovery only")
    func readableNotifyingPlan() {
        let characteristic = CBMutableCharacteristic(
            type: CBUUID(string: "2B10"),
            properties: [.read, .notify],
            value: nil,
            permissions: [.readable]
        )

        let plan = PassiveCoreBluetoothAcquisitionPolicy.plan(for: characteristic)
        #expect(plan.shouldReadValue)
        #expect(plan.shouldSubscribeForValueUpdates)
        #expect(plan.shouldDiscoverDescriptors)
    }

    @Test("writable-only characteristic never becomes a passive read or subscription operation")
    func writableOnlyPlan() {
        let characteristic = CBMutableCharacteristic(
            type: CBUUID(string: "2B11"),
            properties: [.write, .writeWithoutResponse],
            value: nil,
            permissions: [.writeable]
        )

        let plan = PassiveCoreBluetoothAcquisitionPolicy.plan(for: characteristic)
        #expect(!plan.shouldReadValue)
        #expect(!plan.shouldSubscribeForValueUpdates)
        #expect(plan.shouldDiscoverDescriptors)
    }

    @Test("indication-only characteristic is subscribable without pretending it is a notification")
    func indicationPlan() {
        let characteristic = CBMutableCharacteristic(
            type: CBUUID(string: "FFF1"),
            properties: [.indicate],
            value: nil,
            permissions: []
        )

        let plan = PassiveCoreBluetoothAcquisitionPolicy.plan(for: characteristic)
        #expect(!plan.shouldReadValue)
        #expect(plan.shouldSubscribeForValueUpdates)
        #expect(plan.shouldDiscoverDescriptors)
    }
}
