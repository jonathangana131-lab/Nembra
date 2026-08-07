import Foundation
import Testing
@testable import NembraBluetoothCapture

struct PassiveCoreBluetoothTargetStateTests {
    @Test
    func lateCallbacksFromRetiredACannotMutateActiveB() throws {
        let a = UUID()
        let b = UUID()
        var state = PassiveCoreBluetoothTargetState()

        state.selectTarget(a)
        let attemptA = try state.beginAttempt(for: a)
        #expect(attemptA.generation == 1)
        #expect(state.acceptsActiveCallback(from: a))

        #expect(state.retireActiveAttempt() == attemptA)
        state.selectTarget(b)
        let attemptB = try state.beginAttempt(for: b)
        #expect(attemptB.generation == 2)
        #expect(state.acceptsActiveCallback(from: b))
        #expect(!state.acceptsActiveCallback(from: a))

        #expect(state.completeFailedConnection(from: a) == .retired)
        #expect(state.activeAttempt == attemptB)
        #expect(state.completeDisconnect(from: a) == .ignored)
        #expect(state.activeAttempt == attemptB)
    }

    @Test
    func cancelledSamePeripheralIsQuarantinedUntilEitherTerminalCallback() throws {
        let peripheral = UUID()
        var state = PassiveCoreBluetoothTargetState()

        state.selectTarget(peripheral)
        let first = try state.beginAttempt(for: peripheral)
        #expect(state.retireActiveAttempt() == first)

        do {
            _ = try state.beginAttempt(for: peripheral)
            Issue.record("Expected the cancelled peripheral to remain quarantined")
        } catch let error as PassiveCoreBluetoothTargetState.StateError {
            #expect(error == .peripheralAwaitingTerminalCallback(peripheral))
        }

        #expect(state.completeFailedConnection(from: peripheral) == .retired)
        let second = try state.beginAttempt(for: peripheral)
        #expect(second.generation == first.generation + 1)

        #expect(state.retireActiveAttempt() == second)
        #expect(state.completeDisconnect(from: peripheral) == .retired)
        let third = try state.beginAttempt(for: peripheral)
        #expect(third.generation == second.generation + 1)
    }

    @Test
    func changingTargetRetiresAnUnexpectedlyActiveOldAttempt() throws {
        let a = UUID()
        let b = UUID()
        var state = PassiveCoreBluetoothTargetState()

        state.selectTarget(a)
        _ = try state.beginAttempt(for: a)
        state.selectTarget(b)
        let attemptB = try state.beginAttempt(for: b)

        #expect(!state.acceptsActiveCallback(from: a))
        #expect(state.activeAttempt == attemptB)
        #expect(state.completeDisconnect(from: a) == .retired)
        #expect(state.activeAttempt == attemptB)
    }

    @Test
    func readProvenanceIsConsumedExactlyOnce() throws {
        let peripheral = UUID()
        let key = PassiveCoreBluetoothTargetState.AttributeKey(
            peripheralIdentifier: peripheral,
            serviceUUID: "FD50",
            characteristicUUID: "0001"
        )
        var state = PassiveCoreBluetoothTargetState()
        state.selectTarget(peripheral)
        _ = try state.beginAttempt(for: peripheral)

        #expect(!state.consumeReadRequest(key))
        state.markReadRequested(key)
        #expect(state.consumeReadRequest(key))
        #expect(!state.consumeReadRequest(key))
    }

    @Test
    func subscriptionProvenancePreservesUnknownWhenNoTrackedRequest() throws {
        let peripheral = UUID()
        let key = PassiveCoreBluetoothTargetState.AttributeKey(
            peripheralIdentifier: peripheral,
            serviceUUID: "FD50",
            characteristicUUID: "0002"
        )
        var state = PassiveCoreBluetoothTargetState()
        state.selectTarget(peripheral)
        _ = try state.beginAttempt(for: peripheral)

        #expect(state.consumeSubscriptionRequest(key) == nil)
        state.markSubscriptionRequested(key, enabled: true)
        #expect(state.consumeSubscriptionRequest(key) == true)
        #expect(state.consumeSubscriptionRequest(key) == nil)
    }

    @Test
    func centralInvalidationClearsAttemptAndQuarantineButKeepsSelectedTarget() throws {
        let peripheral = UUID()
        var state = PassiveCoreBluetoothTargetState()
        state.selectTarget(peripheral)
        _ = try state.beginAttempt(for: peripheral)
        _ = state.retireActiveAttempt()

        state.resetForCentralInvalidation()

        #expect(state.selectedTargetIdentifier == peripheral)
        #expect(state.activeAttempt == nil)
        let retry = try state.beginAttempt(for: peripheral)
        #expect(retry.generation == 2)
    }
}