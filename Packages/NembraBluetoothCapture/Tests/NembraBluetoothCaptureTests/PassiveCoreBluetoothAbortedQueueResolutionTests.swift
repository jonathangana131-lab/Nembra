import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Aborted queue resolution")
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

    @Test("committed Ready retirement advances resolved frontier without recorder claim")
    @MainActor
    func exactReadyRetirementResolvesThroughQueueTail() async throws {
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
            retirementReceipt: retirement,
            abortedGate: gate
        )

        #expect(resolution.abortReceipt == retirement.abortReceipt)
        #expect(resolution.previouslyResolvedThroughQueueSequence == 0)
        #expect(resolution.resolvedThroughQueueSequence == 2)
        #expect(resolution.retiredEvidenceCount == 2)
        #expect(resolution.advancesResolvedFrontier)
        #expect(gate.isAbortQuarantined)
    }

    @Test("recorded Horizon resolution preserves H as the durable evidence cutoff")
    @MainActor
    func recordedHorizonRetirementResolvesOnlyAfterSettledThroughH() async throws {
        let gate = try await quarantinedRecordedHorizonGate(readyCutoff: 2, horizonCutoff: 4)
        guard case let .abortQuarantined(abort) = gate.phase else {
            Issue.record("expected recorded-H abort quarantine")
            return
        }
        #expect(abort.origin == .recordedHorizonInvalidatedBeforeGateCommit)
        #expect(abort.abandonedReadyQueueCutoff == 2)
        #expect(abort.abandonedHorizonQueueCutoff == 4)
        #expect(abort.abandonedEvidenceQueueCutoff == 4)

        var pending = [pendingEvent(sequence: 5, authorityGeneration: 12)]
        let retirement = try Retirement.retire(
            from: &pending,
            currentLastEnqueuedEventSequence: 5,
            currentSettledQueueSequence: 4,
            drainIsIdle: true,
            abortedGate: gate,
            identity: identity
        )
        #expect(pending.isEmpty)
        #expect(retirement.validatedSettledQueueSequence == 4)

        let resolution = try Resolution.resolve(
            currentResolvedThroughQueueSequence: 4,
            currentLastEnqueuedEventSequence: 5,
            retirementReceipt: retirement,
            abortedGate: gate
        )
        #expect(resolution.abortReceipt == abort)
        #expect(resolution.previouslyResolvedThroughQueueSequence == 4)
        #expect(resolution.resolvedThroughQueueSequence == 5)
        #expect(resolution.retiredEvidenceCount == 1)
    }

    @Test("already-settled prefix remains distinct from retired suffix")
    @MainActor
    func settledPrefixMayExtendPastReadyBeforeRetirement() async throws {
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
        let resolution = try Resolution.resolve(
            currentResolvedThroughQueueSequence: 1,
            currentLastEnqueuedEventSequence: 3,
            retirementReceipt: retirement,
            abortedGate: gate
        )

        #expect(resolution.previouslyResolvedThroughQueueSequence == 1)
        #expect(resolution.resolvedThroughQueueSequence == 3)
        #expect(resolution.retiredEvidenceCount == 2)
    }

    @Test("equal-scalar foreign abort epoch cannot resolve another gate")
    @MainActor
    func foreignGateReceiptFailsExactIdentity() async throws {
        let gateA = try await quarantinedCommittedReadyGate()
        let gateB = try await quarantinedCommittedReadyGate()
        guard case let .abortQuarantined(abortA) = gateA.phase,
              case let .abortQuarantined(abortB) = gateB.phase else {
            Issue.record("expected both gates to be quarantined")
            return
        }
        #expect(abortA.abandonedReadyAuthority == abortB.abandonedReadyAuthority)
        #expect(abortA.abandonedReadyQueueCutoff == abortB.abandonedReadyQueueCutoff)
        #expect(abortA.abandonedReadyTransactionRevision == abortB.abandonedReadyTransactionRevision)
        #expect(abortA.abandonedReadyTransactionIdentity != abortB.abandonedReadyTransactionIdentity)

        var pending: [PendingEvent] = []
        let retirementA = try Retirement.retire(
            from: &pending,
            currentLastEnqueuedEventSequence: 0,
            currentSettledQueueSequence: 0,
            drainIsIdle: true,
            abortedGate: gateA,
            identity: identity
        )

        let error = captureResolutionError {
            _ = try Resolution.resolve(
                currentResolvedThroughQueueSequence: 0,
                currentLastEnqueuedEventSequence: 0,
                retirementReceipt: retirementA,
                abortedGate: gateB
            )
        }
        #expect(error == .abortReceiptMismatch)
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
                retirementReceipt: retirement,
                abortedGate: gate
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
                retirementReceipt: retirement,
                abortedGate: gate
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
            retirementReceipt: retirement,
            abortedGate: gate
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
            retirementReceipt: retirement,
            abortedGate: gate
        )
        #expect(first.resolvedThroughQueueSequence == 1)

        let replayError = captureResolutionError {
            _ = try Resolution.resolve(
                currentResolvedThroughQueueSequence: first.resolvedThroughQueueSequence,
                currentLastEnqueuedEventSequence: 1,
                retirementReceipt: retirement,
                abortedGate: gate
            )
        }
        #expect(replayError == .resolvedFrontierDoesNotMatchRetirementSettled(current: 1, settled: 0))
    }

    @Test("retirement and resolution alone do not reopen lifecycle admission")
    @MainActor
    func rawResolutionKeepsAbortQuarantineClosed() async throws {
        var gate = try await quarantinedCommittedReadyGate()
        var pending: [PendingEvent] = []
        let retirement = try Retirement.retire(
            from: &pending,
            currentLastEnqueuedEventSequence: 0,
            currentSettledQueueSequence: 0,
            drainIsIdle: true,
            abortedGate: gate,
            identity: identity
        )
        _ = try Resolution.resolve(
            currentResolvedThroughQueueSequence: 0,
            currentLastEnqueuedEventSequence: 0,
            retirementReceipt: retirement,
            abortedGate: gate
        )

        #expect(gate.isAbortQuarantined)
        let resetAfterResolution = gate.resetForNewCaptureSession()
        #expect(!resetAfterResolution)
        #expect(gate.isAbortQuarantined)
    }

    @MainActor
    private func quarantinedCommittedReadyGate(
        readyCutoff: UInt64 = 0
    ) async throws -> Gate {
        var gate = Gate()
        let fence = PassiveCoreBluetoothArtifactAuthorityFence(authority: authority)
        let recorder = try PassiveCoreBluetoothCaptureRecorder(
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 1)
        )
        let ready = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.beginReady(
            queueCutoff: readyCutoff,
            processedThrough: readyCutoff,
            authorityFence: fence,
            gate: &gate
        )
        let recordedReady = try await ready.recordBoundary(on: recorder)
        let committedReady = try recordedReady.markBoundaryRecorded(
            on: &gate,
            lastProcessedQueueSequence: readyCutoff
        )
        _ = try gate.abortObservationEpoch(committedReady)
        return gate
    }

    @MainActor
    private func quarantinedRecordedHorizonGate(
        readyCutoff: UInt64,
        horizonCutoff: UInt64
    ) async throws -> Gate {
        var gate = Gate()
        let fence = PassiveCoreBluetoothArtifactAuthorityFence(authority: authority)
        let recorder = try PassiveCoreBluetoothCaptureRecorder(
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 1)
        )
        let ready = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.beginReady(
            queueCutoff: readyCutoff,
            processedThrough: readyCutoff,
            authorityFence: fence,
            gate: &gate
        )
        let recordedReady = try await ready.recordBoundary(on: recorder)
        let committedReady = try recordedReady.markBoundaryRecorded(
            on: &gate,
            lastProcessedQueueSequence: readyCutoff
        )
        let horizon = try committedReady.beginHorizon(
            queueCutoff: horizonCutoff,
            processedThrough: readyCutoff,
            gate: &gate
        )
        let recordedHorizon = try await horizon.recordBoundary(on: recorder)
        _ = try gate.abortRecordedHorizonBeforeGateCommit(recordedHorizon)
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