import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive Bluetooth power-cycle scan delivery")
struct PassiveBluetoothPowerCycleScanDeliveryPolicyTests {
    private static func producerSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile
            .deletingLastPathComponent() // NembraBluetoothCaptureTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // NembraBluetoothCapture package root
        let producer = packageRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("NembraBluetoothCapture")
            .appendingPathComponent("PassiveBluetoothPowerCycleObservationSession.swift")
        return try String(contentsOf: producer, encoding: .utf8)
    }

    @Test("bounded windows keep post-readiness rediscovery possible")
    func boundedWindowsAllowDuplicateDiscoveryCallbacks() {
        #expect(PassiveBluetoothPowerCycleScanDeliveryPolicy.allowsDuplicateDiscoveryCallbacks)
    }

    @Test("live scan request consumes the duplicate-delivery policy")
    func liveScanRequestConsumesDuplicateDeliveryPolicy() throws {
        let source = try Self.producerSource()

        #expect(
            source.contains(
                "CBCentralManagerScanOptionAllowDuplicatesKey:\n" +
                    "                    PassiveBluetoothPowerCycleScanDeliveryPolicy" +
                    ".allowsDuplicateDiscoveryCallbacks"
            )
        )
        #expect(!source.contains("CBCentralManagerScanOptionAllowDuplicatesKey: false"))
    }
}
