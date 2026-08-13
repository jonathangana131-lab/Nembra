import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Terminal fresh target-session authority")
struct PassiveCoreBluetoothTerminalFreshTargetSessionTests {
    private typealias FreshSession = PassiveCoreBluetoothTerminalFreshTargetSession
    private typealias Retirement = PassiveCoreBluetoothTerminalQueueRetirement
    private typealias Resolution = PassiveCoreBluetoothTerminalQueueResolution

    private struct Event: Equatable {
        let queueSequence: UInt64
        let authority: PassiveCoreBluetoothArtifactAuthorityContext
    }

    private let es80 = VehicleIdentity(
        manufacturer: "AOVOPRO",
        model: "ES80",
        displayName: "AOVOPRO ES80",
        protocolFamily: "Tuya / AOVOPRO (hardware validation pending)"
    )

    @Test("proof is issued only with a real exact-next recorder session")
    @MainActor
    func realRecorderMintsExactNextGeneration() async throws {
        let authority = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: 7,
            authorityGeneration: 11
        )
        let resolution = try await terminalResolution(authority: authority)
        let sessionID = UUID(uuidString: "A1000000-0000-0000-0000-000000000001")!
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)

        let fresh = try FreshSession.create(
            after: resolution,
            id: sessionID,
            vehicleIdentity: es80,
            startedAt: startedAt
        )

        #expect(fresh.receipt.terminalResolution == resolution)
        #expect(fresh.receipt.targetSessionGeneration == 8)
        #expect(fresh.receipt.sessionID == sessionID)
        #expect(fresh.receipt.recorderIdentity == ObjectIdentifier(fresh.recorder))
        #expect(ObjectIdentifier(fresh.receipt.recorder) == ObjectIdentifier(fresh.recorder))

        let snapshot = await fresh.recorder.snapshot()
        #expect(snapshot.id == sessionID)
        #expect(snapshot.vehicleIdentity == es80)
        #expect(snapshot.startedAt == startedAt)
        #expect(snapshot.records.isEmpty)
    }

    @Test("detached receipt strongly retains the exact recorder that earned authority")
    @MainActor
    func detachedReceiptRetainsExactRecorder() async throws {
        let authority = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: 9,
            authorityGeneration: 4
        )
        let resolution = try await terminalResolution(authority: authority)
        let sessionID = UUID(uuidString: "A2000000-0000-0000-0000-000000000002")!
        let startedAt = Date(timeIntervalSince1970: 1_800_000_100)

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

        // The outer fresh-session value is gone. The detached authority still owns the
        // exact actor, so its process-local identity cannot become a dangling scalar
        // that a later recorder could satisfy through address reuse.
        #expect(receipt.recorderIdentity == ObjectIdentifier(receipt.recorder))
        let snapshot = await receipt.recorder.snapshot()
        #expect(snapshot.id == sessionID)
        #expect(snapshot.vehicleIdentity == es80)
        #expect(snapshot.startedAt == startedAt)
        #expect(snapshot.records.isEmpty)
    }

    @Test("equal-scalar sessions still carry distinct recorder and producer identity")
    @MainActor
    func separateProvisioningCannotBecomeTheSameProof() async throws {
        let authority = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: 7,
            authorityGeneration: 11
        )
        let resolution = try await terminalResolution(authority: authority)

        let first = try FreshSession.create(
            after: resolution,
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 1)
        )
        let second = try FreshSession.create(
            after: resolution,
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 1)
        )

        #expect(first.receipt.targetSessionGeneration == second.receipt.targetSessionGeneration)
        #expect(first.receipt.terminalResolution == second.receipt.terminalResolution)
        #expect(first.receipt.recorderIdentity == ObjectIdentifier(first.recorder))
        #expect(second.receipt.recorderIdentity == ObjectIdentifier(second.recorder))
        #expect(first.receipt.recorderIdentity != second.receipt.recorderIdentity)
        #expect(first.receipt.provisioningIdentity != second.receipt.provisioningIdentity)
        #expect(first.receipt != second.receipt)
    }

    @Test("exhausted predecessor cannot manufacture a fresh-session proof")
    @MainActor
    func generationExhaustionFailsClosed() async throws {
        let authority = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: UInt64.max,
            authorityGeneration: 1
        )
        let resolution = try await terminalResolution(authority: authority)

        #expect(throws: FreshSession.StateError.targetSessionGenerationExhausted) {
            _ = try FreshSession.create(
                after: resolution,
                vehicleIdentity: es80,
                startedAt: Date(timeIntervalSince1970: 1)
            )
        }
    }

    @MainActor
    private func terminalResolution(
        authority: PassiveCoreBluetoothArtifactAuthorityContext
    ) async throws -> Resolution.Receipt {
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let fence = PassiveCoreBluetoothArtifactAuthorityFence(authority: authority)
        let recorder = try PassiveCoreBluetoothCaptureRecorder(
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 1)
        )

        let ready = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.beginReady(
            queueCutoff: 5,
            processedThrough: 5,
            authorityFence: fence,
            gate: &gate
        )
        let recordedReady = try await ready.recordBoundary(on: recorder)
        let committedReady = try recordedReady.markBoundaryRecorded(
            on: &gate,
            lastProcessedQueueSequence: 5
        )
        let horizon = try committedReady.beginHorizon(
            queueCutoff: 12,
            processedThrough: 12,
            gate: &gate
        )
        let recordedHorizon = try await horizon.recordBoundary(on: recorder)
        let committedHorizon = try recordedHorizon.markBoundaryRecorded(
            on: &gate,
            lastProcessedQueueSequence: 12
        )
        try committedHorizon.completeHorizonArtifactFreeze(on: &gate)

        var events: [Event] = []
        let retirement = try Retirement.retire(
            from: &events,
            currentLastEnqueuedEventSequence: 12,
            terminalGate: gate
        ) {
            Retirement.PendingEvidenceIdentity(
                queueSequence: $0.queueSequence,
                authority: $0.authority
            )
        }
        return try Resolution.resolve(
            currentResolvedThroughQueueSequence: 12,
            currentLastEnqueuedEventSequence: 12,
            retirementReceipt: retirement,
            terminalGate: gate
        )
    }
}
