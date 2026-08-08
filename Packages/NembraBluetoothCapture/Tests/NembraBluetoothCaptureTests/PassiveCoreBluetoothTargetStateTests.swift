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

        let retiredA = state.retireActiveAttempt()
        #expect(retiredA == attemptA)
        #expect(state.isAwaitingTerminalCallback(for: a))
        state.selectTarget(b)
        let attemptB = try state.beginAttempt(for: b)
        #expect(attemptB.generation == 2)
        #expect(state.acceptsActiveCallback(from: b))
        #expect(!state.acceptsActiveCallback(from: a))
        #expect(state.isAwaitingTerminalCallback(for: a))
        #expect(!state.isAwaitingTerminalCallback(for: b))

        let lateFailure = state.completeFailedConnection(from: a)
        #expect(lateFailure == .retired)
        #expect(!state.isAwaitingTerminalCallback(for: a))
        #expect(state.activeAttempt == attemptB)
        let secondLateTerminal = state.completeDisconnect(from: a)
        #expect(secondLateTerminal == .ignored)
        #expect(state.activeAttempt == attemptB)
    }

    @Test
    func cancelledSamePeripheralIsQuarantinedUntilEitherTerminalCallback() throws {
        let peripheral = UUID()
        var state = PassiveCoreBluetoothTargetState()

        state.selectTarget(peripheral)
        let first = try state.beginAttempt(for: peripheral)
        let retiredFirst = state.retireActiveAttempt()
        #expect(retiredFirst == first)
        #expect(state.isAwaitingTerminalCallback(for: peripheral))

        do {
            _ = try state.beginAttempt(for: peripheral)
            Issue.record("Expected the cancelled peripheral to remain quarantined")
        } catch let error as PassiveCoreBluetoothTargetState.StateError {
            #expect(error == .peripheralAwaitingTerminalCallback(peripheral))
        }

        let failedTerminal = state.completeFailedConnection(from: peripheral)
        #expect(failedTerminal == .retired)
        #expect(!state.isAwaitingTerminalCallback(for: peripheral))
        let second = try state.beginAttempt(for: peripheral)
        #expect(second.generation == first.generation + 1)

        let retiredSecond = state.retireActiveAttempt()
        #expect(retiredSecond == second)
        #expect(state.isAwaitingTerminalCallback(for: peripheral))
        let disconnectedTerminal = state.completeDisconnect(from: peripheral)
        #expect(disconnectedTerminal == .retired)
        #expect(!state.isAwaitingTerminalCallback(for: peripheral))
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
        #expect(state.isAwaitingTerminalCallback(for: a))
        #expect(!state.isAwaitingTerminalCallback(for: b))
        #expect(state.activeAttempt == attemptB)
        let lateDisconnect = state.completeDisconnect(from: a)
        #expect(lateDisconnect == .retired)
        #expect(!state.isAwaitingTerminalCallback(for: a))
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

        let untracked = state.consumeReadRequest(key)
        #expect(!untracked)
        state.markReadRequested(key)
        let tracked = state.consumeReadRequest(key)
        #expect(tracked)
        let consumedAgain = state.consumeReadRequest(key)
        #expect(!consumedAgain)
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

        let untracked = state.consumeSubscriptionRequest(key)
        #expect(untracked == nil)
        state.markSubscriptionRequested(key, enabled: true)
        let tracked = state.consumeSubscriptionRequest(key)
        #expect(tracked == true)
        let consumedAgain = state.consumeSubscriptionRequest(key)
        #expect(consumedAgain == nil)
    }

    @Test
    func centralInvalidationRetiresActiveAttemptAndBlocksSamePeripheralRetryUntilTerminal() throws {
        let peripheral = UUID()
        var state = PassiveCoreBluetoothTargetState()
        state.selectTarget(peripheral)
        let first = try state.beginAttempt(for: peripheral)

        state.resetForCentralInvalidation()

        #expect(state.selectedTargetIdentifier == peripheral)
        #expect(state.activeAttempt == nil)
        #expect(state.isAwaitingTerminalCallback(for: peripheral))

        do {
            _ = try state.beginAttempt(for: peripheral)
            Issue.record("Expected central invalidation to preserve same-peripheral quarantine")
        } catch let error as PassiveCoreBluetoothTargetState.StateError {
            #expect(error == .peripheralAwaitingTerminalCallback(peripheral))
        }

        let oldTerminal = state.completeDisconnect(from: peripheral)
        #expect(oldTerminal == .retired)
        #expect(!state.isAwaitingTerminalCallback(for: peripheral))

        let retry = try state.beginAttempt(for: peripheral)
        #expect(retry.generation == first.generation + 1)
        #expect(state.activeAttempt == retry)
    }

    @Test
    func centralInvalidationPreservesExistingRetiredQuarantineUntilTerminal() throws {
        let peripheral = UUID()
        var state = PassiveCoreBluetoothTargetState()
        state.selectTarget(peripheral)
        let first = try state.beginAttempt(for: peripheral)
        let retired = state.retireActiveAttempt()
        #expect(retired == first)
        #expect(state.isAwaitingTerminalCallback(for: peripheral))

        state.resetForCentralInvalidation()

        #expect(state.selectedTargetIdentifier == peripheral)
        #expect(state.activeAttempt == nil)
        #expect(state.isAwaitingTerminalCallback(for: peripheral))

        do {
            _ = try state.beginAttempt(for: peripheral)
            Issue.record("Expected an already-retired attempt to stay quarantined across central invalidation")
        } catch let error as PassiveCoreBluetoothTargetState.StateError {
            #expect(error == .peripheralAwaitingTerminalCallback(peripheral))
        }

        let terminal = state.completeFailedConnection(from: peripheral)
        #expect(terminal == .retired)
        let retry = try state.beginAttempt(for: peripheral)
        #expect(retry.generation == first.generation + 1)
    }
}