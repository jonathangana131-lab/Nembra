import Foundation
import Testing
@testable import NembraCore

private actor TransactionSuspendingCheckpointStore: RideCheckpointStore {
    private(set) var value: RideDurableCheckpoint?
    private(set) var saveCount = 0
    private(set) var clearCount = 0
    private(set) var maximumConcurrentSaves = 0

    private let suspendFirstSave: Bool
    private let suspendFirstClear: Bool
    private var activeSaves = 0

    private var firstSaveStarted = false
    private var firstSaveStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var firstSaveRelease: CheckedContinuation<Void, Never>?

    private var firstClearStarted = false
    private var firstClearStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var firstClearRelease: CheckedContinuation<Void, Never>?

    init(
        value: RideDurableCheckpoint? = nil,
        suspendFirstSave: Bool = false,
        suspendFirstClear: Bool = false
    ) {
        self.value = value
        self.suspendFirstSave = suspendFirstSave
        self.suspendFirstClear = suspendFirstClear
    }

    func save(_ checkpoint: RideDurableCheckpoint) async throws {
        activeSaves += 1
        maximumConcurrentSaves = max(maximumConcurrentSaves, activeSaves)
        saveCount += 1

        if suspendFirstSave, saveCount == 1 {
            firstSaveStarted = true
            let waiters = firstSaveStartWaiters
            firstSaveStartWaiters.removeAll()
            for waiter in waiters {
                waiter.resume()
            }
            await withCheckedContinuation { continuation in
                firstSaveRelease = continuation
            }
        }

        value = checkpoint
        activeSaves -= 1
    }

    func load() async throws -> RideDurableCheckpoint? {
        value
    }

    func clear() async throws {
        clearCount += 1
        if suspendFirstClear, clearCount == 1 {
            firstClearStarted = true
            let waiters = firstClearStartWaiters
            firstClearStartWaiters.removeAll()
            for waiter in waiters {
                waiter.resume()
            }
            await withCheckedContinuation { continuation in
                firstClearRelease = continuation
            }
        }
        value = nil
    }

    func waitUntilFirstSaveStarts() async {
        if firstSaveStarted { return }
        await withCheckedContinuation { continuation in
            firstSaveStartWaiters.append(continuation)
        }
    }

    func resumeFirstSave() {
        let continuation = firstSaveRelease
        firstSaveRelease = nil
        continuation?.resume()
    }

    func waitUntilFirstClearStarts() async {
        if firstClearStarted { return }
        await withCheckedContinuation { continuation in
            firstClearStartWaiters.append(continuation)
        }
    }

    func resumeFirstClear() {
        let continuation = firstClearRelease
        firstClearRelease = nil
        continuation?.resume()
    }
}

private actor TransactionAttemptSignal {
    private var didSignal = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func signal() {
        guard !didSignal else { return }
        didSignal = true
        let current = waiters
        waiters.removeAll()
        for waiter in current {
            waiter.resume()
        }
    }

    func wait() async {
        if didSignal { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}

@Suite("Ride checkpoint coordinator transactions")
struct RideCheckpointCoordinatorTransactionTests {
    private let epoch = Date(timeIntervalSince1970: 1_700_300_000)
    private let fixedSessionID = UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!

    private func policy() throws -> RideDetectionPolicy {
        try RideDetectionPolicy(
            candidateSpeedKilometersPerHour: 1,
            confirmationSpeedKilometersPerHour: 4,
            confirmationDurationNanoseconds: 0,
            confirmationOdometerDeltaKilometers: 0.05,
            confirmationGPSDistanceMeters: 8,
            endingDurationNanoseconds: 5_000,
            maximumSpeedSampleAgeNanoseconds: 1_000
        )
    }

    private func cadence(_ interval: UInt64 = 10_000_000) throws -> RideCheckpointCadence {
        try RideCheckpointCadence(minimumIntervalNanoseconds: interval)
    }

    private func observation(
        _ uptime: UInt64,
        connection: VehicleConnectionState = .connected,
        speedKPH: Double? = nil,
        odometer: Double? = nil
    ) throws -> RideObservation {
        let date = epoch.addingTimeInterval(Double(uptime) / 1_000_000_000)
        let sample = try speedKPH.map {
            try SpeedTelemetrySample(
                source: .scooterBluetooth,
                provenance: .absoluteMeasurement,
                metersPerSecond: $0 / 3.6,
                receivedAtUptimeNanoseconds: uptime,
                receivedAtDate: date
            )
        }
        return try RideObservation(
            receivedAtUptimeNanoseconds: uptime,
            receivedAtDate: date,
            connection: connection,
            speedSample: sample,
            odometerKilometers: odometer
        )
    }

    private func completedEvidence() throws -> CompletedRideEvidence {
        try CompletedRideEvidence(
            sessionID: fixedSessionID,
            beganAtDate: epoch,
            confirmedAtDate: epoch.addingTimeInterval(1),
            endedAtDate: epoch.addingTimeInterval(60),
            startingOdometerKilometers: 100,
            endingOdometerKilometers: 101,
            qualityScreenedGPSDistanceMeters: 1_000,
            continuity: .uninterruptedProcess
        )
    }

    @Test("overlapping ingests cannot stage from stale engine state across a durable save")
    func overlappingIngestsSerializeAcrossStoreAwait() async throws {
        let sessionID = fixedSessionID
        let store = TransactionSuspendingCheckpointStore(suspendFirstSave: true)
        let coordinator = RideCheckpointCoordinator(
            engine: RideEngine(policy: try policy(), makeSessionID: { sessionID }),
            store: store,
            cadence: try cadence()
        )
        let firstObservation = try observation(1_000, speedKPH: 8, odometer: 100)
        let secondObservation = try observation(2_000, speedKPH: 8, odometer: 100.1)
        let secondAttempt = TransactionAttemptSignal()

        let firstTask = Task {
            try await coordinator.ingest(firstObservation)
        }
        await store.waitUntilFirstSaveStarts()

        let secondTask = Task {
            await secondAttempt.signal()
            return try await coordinator.ingest(secondObservation)
        }
        await secondAttempt.wait()

        // Give the competing task repeated opportunities to enter the reentrant
        // coordinator while the first store write remains deliberately suspended.
        // A transaction permit keeps it outside the store; the old implementation
        // could stage from idle and start a second overlapping save here.
        for _ in 0..<32 {
            await Task.yield()
        }
        #expect(await store.saveCount == 1)
        #expect(await store.maximumConcurrentSaves == 1)

        await store.resumeFirstSave()
        _ = try await firstTask.value
        _ = try await secondTask.value

        // The long cadence means only ride-start needs a write, but both accepted
        // observations must have committed to the engine in FIFO order.
        #expect(await store.saveCount == 1)
        #expect(await store.maximumConcurrentSaves == 1)
        await #expect(throws: RideEngineError.nonMonotonicObservation) {
            _ = try await coordinator.ingest(
                observation(1_500, speedKPH: 8, odometer: 100.05)
            )
        }
    }

    @Test("cancellation before permit admission drops the queued observation")
    func cancelledQueuedIngestNeverMutatesRideState() async throws {
        let sessionID = fixedSessionID
        let store = TransactionSuspendingCheckpointStore(suspendFirstSave: true)
        let coordinator = RideCheckpointCoordinator(
            engine: RideEngine(policy: try policy(), makeSessionID: { sessionID }),
            store: store,
            cadence: try cadence()
        )
        let firstObservation = try observation(1_000, speedKPH: 8, odometer: 100)
        let cancelledObservation = try observation(2_000, speedKPH: 8, odometer: 100.1)
        let secondAttempt = TransactionAttemptSignal()

        let firstTask = Task {
            try await coordinator.ingest(firstObservation)
        }
        await store.waitUntilFirstSaveStarts()

        let cancelledTask = Task {
            await secondAttempt.signal()
            return try await coordinator.ingest(cancelledObservation)
        }
        await secondAttempt.wait()
        cancelledTask.cancel()

        // Keep the first durable write suspended while cancellation gets actor
        // scheduling opportunities. A cancellation-blind queue would retain this
        // work and execute it after the first transaction releases its permit.
        for _ in 0..<16 {
            await Task.yield()
        }
        #expect(await store.saveCount == 1)

        await store.resumeFirstSave()
        _ = try await firstTask.value

        do {
            _ = try await cancelledTask.value
            Issue.record("a mutation cancelled before permit admission must not execute later")
        } catch is CancellationError {
            // Expected: cancellation removes the queued waiter, or a cancellation
            // racing with FIFO handoff immediately returns the transferred permit.
        } catch {
            Issue.record("expected CancellationError, received \(error)")
        }

        // 1_500 is newer than the admitted 1_000 observation but older than the
        // cancelled 2_000 observation. Acceptance proves the cancelled observation
        // never advanced the engine's monotonic receive clock.
        _ = try await coordinator.ingest(
            observation(1_500, speedKPH: 8, odometer: 100.05)
        )
        #expect(await store.saveCount == 1)
    }

    @Test("completion acknowledgement and new ingress share one mutation transaction boundary")
    func acknowledgementSerializesAgainstNewIngress() async throws {
        let sessionID = fixedSessionID
        let evidence = try completedEvidence()
        let store = TransactionSuspendingCheckpointStore(
            value: .completedPendingCommit(evidence),
            suspendFirstClear: true
        )
        let coordinator = try await RideCheckpointCoordinator.restoring(
            policy: try policy(),
            store: store,
            cadence: try cadence(),
            recoveredAtUptimeNanoseconds: 50_000,
            recoveredAtDate: epoch.addingTimeInterval(50),
            makeSessionID: { sessionID }
        )
        let ingestAttempt = TransactionAttemptSignal()

        let acknowledgement = Task {
            try await coordinator.acknowledgeCompletedRideCommitted(sessionID: sessionID)
        }
        await store.waitUntilFirstClearStarts()

        let ingress = Task {
            await ingestAttempt.signal()
            return try await coordinator.ingest(
                observation(60_000, speedKPH: 8, odometer: 101)
            )
        }
        await ingestAttempt.wait()
        for _ in 0..<16 {
            await Task.yield()
        }

        // While clear is suspended, the pending completion remains the committed
        // actor truth. The ingress must wait behind acknowledgement rather than
        // re-entering and spuriously failing `completedRideAwaitingCommit`.
        #expect(await coordinator.pendingCompletedRideEvidence() == evidence)

        await store.resumeFirstClear()
        try await acknowledgement.value
        let update = try await ingress.value

        #expect(await coordinator.pendingCompletedRideEvidence() == nil)
        guard case .active = update.phase else {
            Issue.record("ingress admitted after acknowledgement should start the next ride")
            return
        }
        #expect(await store.clearCount == 1)
    }
}
