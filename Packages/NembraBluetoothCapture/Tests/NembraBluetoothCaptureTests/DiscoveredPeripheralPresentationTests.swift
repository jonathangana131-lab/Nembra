import Foundation
import Testing
@testable import NembraBluetoothCapture

struct DiscoveredPeripheralPresentationTests {
    @Test
    func unavailableCoreBluetoothRSSISentinelStaysUnknown() {
        #expect(
            ForegroundCoreBluetoothCaptureController.DiscoveredPeripheral.normalizedRSSI(127) == nil
        )
        #expect(
            ForegroundCoreBluetoothCaptureController.DiscoveredPeripheral.normalizedRSSI(-52) == -52
        )
    }

    @Test
    func unknownRSSIIsNeverRenderedAsMeasuredDBM() {
        let candidate = ForegroundCoreBluetoothCaptureController.DiscoveredPeripheral(
            id: UUID(),
            localName: "candidate",
            rssi: nil,
            isConnectable: true
        )

        #expect(candidate.rssiDescription == "Unavailable")
    }

    @Test
    func knownSignalsSortByStrengthBeforeUnknownCandidates() {
        let strongest = ForegroundCoreBluetoothCaptureController.DiscoveredPeripheral(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            localName: "strong",
            rssi: -41,
            isConnectable: true
        )
        let weaker = ForegroundCoreBluetoothCaptureController.DiscoveredPeripheral(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            localName: "weak",
            rssi: -79,
            isConnectable: true
        )
        let unknown = ForegroundCoreBluetoothCaptureController.DiscoveredPeripheral(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            localName: "unknown",
            rssi: nil,
            isConnectable: true
        )

        let sorted = [unknown, weaker, strongest].sorted {
            ForegroundCoreBluetoothCaptureController.DiscoveredPeripheral.sortsBefore($0, $1)
        }

        #expect(sorted.map(\.id) == [strongest.id, weaker.id, unknown.id])
    }
}
