import Foundation
import Testing
@testable import NembraBluetoothCapture

struct PassiveCoreBluetoothTargetStateTests {
    @Test
    func lateCallbacksFromRetiredA cannotMutateActiveB() throws {
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

        #expect(state.completeFailedConnection(from: a) == nil)
        #expect(state.activeAttempt == attemptB)
        #expect(state.completeDisconnect(from: a) == .retired)
        #expect(state.activeAttempt == attemptB)
    }

    @Test
    func cancelledSamePeripheralIsQuarantinedUntilDisconnect() throws {
        let peripheral = UUID()
        var state = PassiveCoreBluetoothTargetState()

        state.selectTarget(peripheral)
        let first = try state.beginAttempt(for: peripheral)
        #expect(state.retireActiveAttempt() == first)

        #expect(throws: PassiveCoreBluetoothTargetState.StateError.peripheralAwaitingDisconnect(peripheral)) {
            _ = try state.beginAttempt(for: peripheral)
        }

        #expect(state.completeDisconnect(from: peripheral) == .retired)
        let second = try state.beginAttempt(for: peripheral)
        #expect(second.generation == first.generation + 1)
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
