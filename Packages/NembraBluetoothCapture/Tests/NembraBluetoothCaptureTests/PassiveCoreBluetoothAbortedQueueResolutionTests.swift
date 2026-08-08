import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Pre-H aborted queue resolution")
struct PassiveCoreBluetoothAbortedQueueResolutionTests {
    private typealias Gate = PassiveCoreBluetoothObservationBoundaryQueueGate
    private typealias Retirement = PassiveCoreBluetoothAbortedObservationQueueRetirement
    private typealias Resolution = PassiveCoreBluetoothAbortedQueueResolution

    private struct PendingEvent: Equatable {
        let queueSequence: UInt64
        let authority: PassiveCoreBluetoothArtifactAuthorityContext
    }

    private let authority = PassiveCoreBluetoothArtifactAuthorityContext(
        targetSessionGeneration: 7,
        authorityGeneration: 11
    )

    private let es80 = VehicleIdentity(
        manufacturer: "AOVOPRO",
        model: "ES80",
        displayName: "AOVOPRO ES80",
        protocolFamily: "Tuya / AOVOPRO (hardware validation pending)"
    )

    @Test("complete abandoned-session suffix advances resolved frontier without recorder claim")
    @MainActor
    func exactRetirementResolvesThroughQueueTail() async throws {
        let gate = try await quarantinedCommittedReadyGate()
        var pending = [
            pendingEvent(sequence: 1, authorityGeneration: 12),
            pendingEvent(sequence: 2, authorityGeneration: 13),
        ]

        let retirement = try Retirement.retire(
            from: &pending,
            currentLastEnqueuedEventSequence: 2,
            currentSettledQueueSequence: 0,
            drainIsIdle: true,
            abortedGate: gate,
            identity: identity
        )
        #expect(pending.isEmpty)
        #expect(retirement.retiredEvidenceCount == 2)

        let resolution = try Resolution.resolve(
            currentResolvedThroughQueueSequence: 0,
            currentLastEnqueuedEventSequence: 2,
            retirementReceipt: retirement
        )

        #expect(resolution.abortReceipt == retirement.abortReceipt)
        #expect(resolution.previouslyResolvedThroughQueueSequence == 0)
        #expect(resolution.resolvedThroughQueueSequence == 2)
        #expect(resolution.retiredEvidenceCount == 2)
        #expect(resolution.advancesResolvedFrontier)
        #expect(gate.isAbortQuarantined)
    }

    @Test("already-settled prefix remains distinct from retired suffix")
    @MainActor
    func settledPrefixMayExtendPastReadyBeforeRetirement() async throws {
        let gate = try await quarantinedCommittedReadyGate()
        var pending = [
            pendingEvent(sequence: 2, authorityGeneration: 12),
            pendingEvent(sequence: 3, authorityGeneration: 13),
        ]

        // Queue position 1 was already settled before quarantine. This fixture does
        // not claim whether it was recorder-written or resolved by another accepted
        // lifecycle operation. Retirement owns only 2...3; resolution therefore
        // advances 1 -> 3 without relabeling position 1 or the retired suffix.
        let retirement = try Retirement.retire(
            from: &pending,
            currentLastEnqueuedEventSequence: 3,
            currentSettledQueueSequence: 1,
            drainIsIdle: true,
            abortedGate: gate,
            identity: identity
        )
        let resolution = try Resolution.resolve(
            currentResolvedThroughQueueSequence: 1,
            currentLastEnqueuedEventSequence: 3,
            retirementReceipt: retirement
        )

        #expect(resolution.previouslyResolvedThroughQueueSequence == 1)
        #expect(resolution.resolvedThroughQueueSequence == 3)
        #expect(resolution.retiredEvidenceCount == 2)
    }

    @Test("callback accepted after retirement invalidates resolution")
    @MainActor
    func queueTailMovementFailsClosed() async throws {
        let gate = try await quarantinedCommittedReadyGate()
        var pending = [pendingEvent(sequence: 1, authorityGeneration: 12)]
        let retirement = try Retirement.retire(
            from: &pending,
            currentLastEnqueuedEventSequence: 1,
            currentSettledQueueSequence: 0,
            drainIsIdle: true,
            abortedGate: gate,
            identity: identity
        )

        let error = captureResolutionError {
            _ = try Resolution.resolve(
                currentResolvedThroughQueueSequence: 0,
                currentLastEnqueuedEventSequence: 2,
                retirementReceipt: retirement
            )
        }
        #expect(error == .controllerQueueChangedAfterRetirement(expected: 1, actual: 2))
    }

    @Test("resolution requires the exact previously-settled frontier")
    @MainActor
    func staleResolvedFrontierFailsClosed() async throws {
        let gate = try await quarantinedCommittedReadyGate()
        var pending = [
            pendingEvent(sequence: 2, authorityGeneration: 12),
            pendingEvent(sequence: 3, authorityGeneration: 13),
        ]
        let retirement = try Retirement.retire(
            from: &pending,
            currentLastEnqueuedEventSequence: 3,
            currentSettledQueueSequence: 1,
            drainIsIdle: true,
            abortedGate: gate,
            identity: identity
        )

        let error = captureResolutionError {
            _ = try Resolution.resolve(
                currentResolvedThroughQueueSequence: 0,
                currentLastEnqueuedEventSequence: 3,
                retirementReceipt: retirement
            )
        }
        #expect(error == .resolvedFrontierDoesNotMatchRetirementSettled(current: 0, settled: 1))
    }

    @Test("empty retirement is an exact no-op resolution")
    @MainActor
    func noPendingSuffixKeepsResolvedFrontierStable() async throws {
        let gate = try await quarantinedCommittedReadyGate()
        var pending: [PendingEvent] = []
        let retirement = try Retirement.retire(
            from: &pending,
            currentLastEnqueuedEventSequence: 0,
            currentSettledQueueSequence: 0,
            drainIsIdle: true,
            abortedGate: gate,
            identity: identity
        )

        let resolution = try Resolution.resolve(
            currentResolvedThroughQueueSequence: 0,
            currentLastEnqueuedEventSequence: 0,
            retirementReceipt: retirement
        )
        #expect(resolution.previouslyResolvedThroughQueueSequence == 0)
        #expect(resolution.resolvedThroughQueueSequence == 0)
        #expect(resolution.retiredEvidenceCount == 0)
        #expect(!resolution.advancesResolvedFrontier)
    }

    @Test("same retirement proof cannot be replayed after caller advances frontier")
    @MainActor
    func replayAfterResolutionFailsClosed() async throws {
        let gate = try await quarantinedCommittedReadyGate()
        var pending = [pendingEvent(sequence: 1, authorityGeneration: 12)]
        let retirement = try Retirement.retire(
            from: &pending,
            currentLastEnqueuedEventSequence: 1,
            currentSettledQueueSequence: 0,
            drainIsIdle: true,
            abortedGate: gate,
            identity: identity
        )
        let first = try Resolution.resolve(
            currentResolvedThroughQueueSequence: 0,
            currentLastEnqueuedEventSequence: 1,
            retirementReceipt: retirement
        )
        #expect(first.resolvedThroughQueueSequence == 1)

        let replayError = captureResolutionError {
            _ = try Resolution.resolve(
                currentResolvedThroughQueueSequence: first.resolvedThroughQueueSequence,
                currentLastEnqueuedEventSequence: 1,
                retirementReceipt: retirement
            )
        }
        #expect(replayError == .resolvedFrontierDoesNotMatchRetirementSettled(current: 1, settled: 0))
    }

    @MainActor
    private func quarantinedCommittedReadyGate() async throws -> Gate {
        var gate = Gate()
        let fence = PassiveCoreBluetoothArtifactAuthorityFence(authority: authority)
        let recorder = try PassiveCoreBluetoothCaptureRecorder(
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 1)
        )
        let ready = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.beginReady(
            queueCutoff: 0,
            processedThrough: 0,
            authorityFence: fence,
            gate: &gate
        )
        let recordedReady = try await ready.recordBoundary(on: recorder)
        let committedReady = try recordedReady.markBoundaryRecorded(
            on: &gate,
            lastProcessedQueueSequence: 0
        )
        _ = try gate.abortObservationEpoch(committedReady)
        return gate
    }

    private func pendingEvent(
        sequence: UInt64,
        authorityGeneration: UInt64
    ) -> PendingEvent {
        PendingEvent(
            queueSequence: sequence,
            authority: .init(
                targetSessionGeneration: authority.targetSessionGeneration,
                authorityGeneration: authorityGeneration
            )
        )
    }

    private func identity(_ event: PendingEvent) -> Retirement.PendingEvidenceIdentity {
        .init(queueSequence: event.queueSequence, authority: event.authority)
    }

    @MainActor
    private func captureResolutionError(
        _ operation: () throws -> Void
    ) -> Resolution.StateError? {
        do {
            try operation()
            return nil
        } catch {
            return error as? Resolution.StateError
        }
    }
}
