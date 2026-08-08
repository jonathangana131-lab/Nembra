import Foundation
import Testing
@testable import NembraBluetoothCapture

struct PassiveCoreBluetoothAcquisitionWatchdogContextTests {
    private let peripheral = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let otherPeripheral = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    private func context(
        peripheralIdentifier: UUID? = nil,
        targetSessionGeneration: UInt64 = 4,
        acquisitionGeneration: UInt64 = 9
    ) -> PassiveCoreBluetoothAcquisitionWatchdogContext {
        PassiveCoreBluetoothAcquisitionWatchdogContext(
            peripheralIdentifier: peripheralIdentifier ?? peripheral,
            targetSessionGeneration: targetSessionGeneration,
            acquisitionGeneration: acquisitionGeneration
        )
    }

    @Test
    func exactActiveTicketCanExpire() throws {
        var state = PassiveCoreBluetoothAcquisitionWatchdogState()
        let current = context()
        let ticket = try state.arm(for: current)

        #expect(state.isArmed)
        #expect(state.activeTicket == ticket)
        #expect(state.acceptsExpiry(ticket, currentContext: current))
    }

    @Test
    func matchingWatchdogExpiryLeavesIncompleteFiniteAcquisitionUnavailable() throws {
        var readiness = PassiveCoreBluetoothAcquisitionReadiness()
        readiness.beginTargetSession()
        readiness.beginConnectionAttempt()
        try readiness.startAcquisition()
        _ = try readiness.beginOperation()

        var state = PassiveCoreBluetoothAcquisitionWatchdogState()
        let current = context(acquisitionGeneration: readiness.generation)
        let ticket = try state.arm(for: current)

        // This is the controller's fail-closed expiry policy expressed through
        // the exact deterministic state contracts used by the runtime: only the
        // active ticket may expire this generation, then cancellation terminates
        // its unresolved finite ledger rather than laundering it as complete.
        #expect(state.acceptsExpiry(ticket, currentContext: current))
        readiness.finishWithoutGattAcquisition()
        state.cancel()

        #expect(readiness.phase == .terminalWithoutGattAcquisition)
        #expect(readiness.isIncomplete)
        #expect(!readiness.isReady)
        #expect(readiness.pendingOperationCount == 0)
        #expect(!state.isArmed)
        #expect(!state.acceptsExpiry(ticket, currentContext: current))
    }

    @Test
    func acquisitionProgressRearmRejectsOldDeadlineEvenWithinSameGeneration() throws {
        var state = PassiveCoreBluetoothAcquisitionWatchdogState()
        let current = context()
        let first = try state.arm(for: current)
        let rearmed = try state.arm(for: current)

        #expect(first.revision != rearmed.revision)
        #expect(!state.acceptsExpiry(first, currentContext: current))
        #expect(state.acceptsExpiry(rearmed, currentContext: current))
    }

    @Test
    func readinessCancellationMakesLaterNotificationSilenceHarmless() throws {
        var state = PassiveCoreBluetoothAcquisitionWatchdogState()
        let current = context()
        let ticket = try state.arm(for: current)

        state.cancel()

        #expect(!state.isArmed)
        #expect(state.activeTicket == nil)
        #expect(!state.acceptsExpiry(ticket, currentContext: current))
    }

    @Test
    func newerAcquisitionGenerationRejectsStaleTicket() throws {
        var state = PassiveCoreBluetoothAcquisitionWatchdogState()
        let oldContext = context(acquisitionGeneration: 9)
        let oldTicket = try state.arm(for: oldContext)
        let newerContext = context(acquisitionGeneration: 10)
        let newerTicket = try state.arm(for: newerContext)

        #expect(!state.acceptsExpiry(oldTicket, currentContext: newerContext))
        #expect(state.acceptsExpiry(newerTicket, currentContext: newerContext))
    }

    @Test
    func newerTargetSessionRejectsStaleTicket() throws {
        var state = PassiveCoreBluetoothAcquisitionWatchdogState()
        let oldContext = context(targetSessionGeneration: 4)
        let oldTicket = try state.arm(for: oldContext)
        let newerContext = context(targetSessionGeneration: 5)
        let newerTicket = try state.arm(for: newerContext)

        #expect(!state.acceptsExpiry(oldTicket, currentContext: newerContext))
        #expect(state.acceptsExpiry(newerTicket, currentContext: newerContext))
    }

    @Test
    func differentOrMissingPeripheralRejectsExpiry() throws {
        var state = PassiveCoreBluetoothAcquisitionWatchdogState()
        let current = context()
        let ticket = try state.arm(for: current)
        let different = context(peripheralIdentifier: otherPeripheral)

        #expect(!state.acceptsExpiry(ticket, currentContext: different))
        #expect(!state.acceptsExpiry(ticket, currentContext: nil))
    }
}
