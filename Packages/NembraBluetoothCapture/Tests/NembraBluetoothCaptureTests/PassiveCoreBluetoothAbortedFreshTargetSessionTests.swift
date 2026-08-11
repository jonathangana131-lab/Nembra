import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Aborted Capture fresh-recorder authority")
struct PassiveCoreBluetoothAbortedFreshTargetSessionTests {
    private typealias FreshSession = PassiveCoreBluetoothAbortedFreshTargetSession
    private typealias Gate = PassiveCoreBluetoothObservationBoundaryQueueGate

    private let es80 = VehicleIdentity(
        manufacturer: "AOVOPRO",
        model: "ES80",
        displayName: "AOVOPRO ES80",
        protocolFamily: "Tuya / AOVOPRO (hardware validation pending)"
    )

    @Test("abort resolution mints proof only after constructing the exact next recorder")
    @MainActor
    func createsExactNextRecorderProof() async throws {
        let resolution = try await resolvedAbort(previousGeneration: 7)
        let sessionID = UUID()
        let startedAt = Date(timeIntervalSince1970: 42)

        let fresh = try FreshSession.create(
            after: resolution,
            id: sessionID,
            vehicleIdentity: es80,
            startedAt: startedAt
        )

        #expect(fresh.receipt.abortedResolution == resolution)
        #expect(fresh.receipt.targetSessionGeneration == 8)
        #expect(fresh.receipt.sessionID == sessionID)
        #expect(fresh.receipt.recorderIdentity == ObjectIdentifier(fresh.recorder))
        #expect(ObjectIdentifier(fresh.receipt.recorder) == ObjectIdentifier(fresh.recorder))
    }

    @Test("detached abort receipt strongly retains the exact recorder that earned authority")
    @MainActor
    func detachedReceiptRetainsExactRecorder() async throws {
        let resolution = try await resolvedAbort(previousGeneration: 9)
        let sessionID = UUID(uuidString: "A3000000-0000-0000-0000-000000000003")!
        let startedAt = Date(timeIntervalSince1970: 1_800_000_200)

        let receipt: FreshSession.Receipt = try {
            let fresh = try FreshSession.create(
                after: resolution,
                id: sessionID,
                vehicleIdentity: es80,
                startedAt: startedAt
            )
            #expect(ObjectIdentifier(fresh.receipt.recorder) == ObjectIdentifier(fresh.recorder))
            return fresh.receipt
        }()

        #expect(receipt.recorderIdentity == ObjectIdentifier(receipt.recorder))
        let snapshot = await receipt.recorder.snapshot()
        #expect(snapshot.id == sessionID)
        #expect(snapshot.vehicleIdentity == es80)
        #expect(snapshot.startedAt == startedAt)
        #expect(snapshot.records.isEmpty)
    }

    @Test("equal-scalar provisioning events remain distinct recorder authority")
    @MainActor
    func independentProvisioningCannotAliasRecorderProof() async throws {
        let resolution = try await resolvedAbort(previousGeneration: 7)
        let first = try FreshSession.create(
            after: resolution,
            vehicleIdentity: es80
        )
        let second = try FreshSession.create(
            after: resolution,
            vehicleIdentity: es80
        )

        #expect(first.receipt.targetSessionGeneration == second.receipt.targetSessionGeneration)
        #expect(first.receipt.recorderIdentity == ObjectIdentifier(first.recorder))
        #expect(second.receipt.recorderIdentity == ObjectIdentifier(second.recorder))
        #expect(first.receipt.recorderIdentity != second.receipt.recorderIdentity)
        #expect(first.receipt.provisioningIdentity != second.receipt.provisioningIdentity)
        #expect(first.receipt != second.receipt)
    }

    @Test("generation exhaustion cannot manufacture fresh recorder authority")
    @MainActor
    func generationExhaustionFailsClosed() async throws {
        let resolution = try await resolvedAbort(previousGeneration: UInt64.max)
        #expect(throws: FreshSession.StateError.targetSessionGenerationExhausted) {
            _ = try FreshSession.create(
                after: resolution,
                vehicleIdentity: es80
            )
        }
    }

    @MainActor
    private func resolvedAbort(
        previousGeneration: UInt64
    ) async throws -> PassiveCoreBluetoothAbortedQueueResolution.Receipt {
        let authority = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: previousGeneration,
            authorityGeneration: 11
        )
        var gate = Gate()
        let fence = PassiveCoreBluetoothArtifactAuthorityFence(authority: authority)
        let recorder = try PassiveCoreBluetoothCaptureRecorder(
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 1)
        )

        let ready = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.beginReady(
            queueCutoff: 2,
            processedThrough: 2,
            authorityFence: fence,
            gate: &gate
        )
        let recorded = try await ready.recordBoundary(on: recorder)
        let committed = try recorded.markBoundaryRecorded(
            on: &gate,
            lastProcessedQueueSequence: 2
        )
        _ = try gate.abortObservationEpoch(committed)

        struct Event: Equatable {
            let queueSequence: UInt64
            let authority: PassiveCoreBluetoothArtifactAuthorityContext
        }
        var pending: [Event] = []
        let retirement = try PassiveCoreBluetoothAbortedObservationQueueRetirement.retire(
            from: &pending,
            currentLastEnqueuedEventSequence: 2,
            currentSettledQueueSequence: 2,
            drainIsIdle: true,
            abortedGate: gate,
            identity: { .init(queueSequence: $0.queueSequence, authority: $0.authority) }
        )
        return try PassiveCoreBluetoothAbortedQueueResolution.resolve(
            currentResolvedThroughQueueSequence: 2,
            currentLastEnqueuedEventSequence: 2,
            retirementReceipt: retirement,
            abortedGate: gate
        )
    }
}
