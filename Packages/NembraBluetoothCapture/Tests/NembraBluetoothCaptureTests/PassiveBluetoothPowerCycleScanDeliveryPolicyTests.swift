import Testing
@testable import NembraBluetoothCapture

@Suite("Passive Bluetooth power-cycle scan delivery")
struct PassiveBluetoothPowerCycleScanDeliveryPolicyTests {
    @Test("bounded windows keep post-readiness rediscovery possible")
    func boundedWindowsAllowDuplicateDiscoveryCallbacks() {
        #expect(PassiveBluetoothPowerCycleScanDeliveryPolicy.allowsDuplicateDiscoveryCallbacks)
    }
}
