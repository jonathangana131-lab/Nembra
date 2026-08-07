import Foundation
import Testing
@testable import NembraBluetoothCapture

struct PassiveCoreBluetoothAcquisitionWatchdogContextTests {
    private let peripheral = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    @Test
    func exactAcquisitionIdentityMatches() {
        let context = PassiveCoreBluetoothAcquisitionWatchdogContext(
            peripheralIdentifier: peripheral,
            targetSessionGeneration: 4,
            acquisitionGeneration: 9
        )

        #expect(
            context.matches(
                peripheralIdentifier: peripheral,
                targetSessionGeneration: 4,
                acquisitionGeneration: 9
            )
        )
    }

    @Test
    func laterAcquisitionGenerationRejectsStaleWatchdog() {
        let context = PassiveCoreBluetoothAcquisitionWatchdogContext(
            peripheralIdentifier: peripheral,
            targetSessionGeneration: 4,
            acquisitionGeneration: 9
        )

        #expect(
            !context.matches(
                peripheralIdentifier: peripheral,
                targetSessionGeneration: 4,
                acquisitionGeneration: 10
            )
        )
    }

    @Test
    func laterTargetSessionRejectsStaleWatchdog() {
        let context = PassiveCoreBluetoothAcquisitionWatchdogContext(
            peripheralIdentifier: peripheral,
            targetSessionGeneration: 4,
            acquisitionGeneration: 9
        )

        #expect(
            !context.matches(
                peripheralIdentifier: peripheral,
                targetSessionGeneration: 5,
                acquisitionGeneration: 9
            )
        )
    }

    @Test
    func differentOrMissingPeripheralRejectsStaleWatchdog() {
        let context = PassiveCoreBluetoothAcquisitionWatchdogContext(
            peripheralIdentifier: peripheral,
            targetSessionGeneration: 4,
            acquisitionGeneration: 9
        )
        let other = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

        #expect(
            !context.matches(
                peripheralIdentifier: other,
                targetSessionGeneration: 4,
                acquisitionGeneration: 9
            )
        )
        #expect(
            !context.matches(
                peripheralIdentifier: nil,
                targetSessionGeneration: 4,
                acquisitionGeneration: 9
            )
        )
    }
}
