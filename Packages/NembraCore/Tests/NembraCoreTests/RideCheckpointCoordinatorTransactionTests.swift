import Foundation
import Testing
@testable import NembraCore

private actor TransactionTestCheckpointStore: RideCheckpointStore {
    private(set) var value: RideDurableCheckpoint?
    private(set) var saveCount = 0

    init(value: RideDurableCheckpoint? = nil) {
        self.value = value
    }

    func save(_ checkpoint: RideDurableCheckpoint) async throws {
        value = checkpoint
        saveCount += 1
    }

    func load() async throws -> RideDurableCheckpoint? {
        value
    }

    func clear() async throws {
        value = nil
    }
}

private actor BlockingCheckpointStore: RideCheckpointStore {
    private(set) var value: RideDurableCheckpoint?
    private(set) var saveCount = 0
    private(set) var maximumConcurrentSaves = 0

    private var activeSaves = 0
    private var firstSaveStarted = false
    private var firstSaveWaiters: [CheckedContinuation<Void, Never>] = []
    private var firstSaveRelease: CheckedContinuation<Void, Never>?

    func save(_ checkpoint: RideDurableCheckpoint) async throws {
        activeSaves += 1
        maximumConcurrentSaves = max(maximumConcurrentSaves, activeSaves)
        saveCount += 1

        if saveCount == 1 {
            firstSaveStarted = true
            let waiters = firstSaveWaiters
            firstSaveWaiters.removeAll()
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
        value = nil
    }

    func waitUntilFirstSaveStarts() async {
        if firstSaveStarted {
            return
        }
        await withCheckedContinuation { continuation in
            firstSaveWaiters.append(continuation)
        }
    }

    func releaseFirstSave() {
        let continuation = firstSaveRelease
        firstSaveRelease = nil
        continuation?.resume()
    }
}

private enum TransactionInjectedFailure: Error, Equatable {
    case suspendedSave
    case writeThenThrow
}

private actor SuspendedFailingCheckpointStore: RideCheckpointStore {
    private(set) var saveCount = 0
    private var firstSaveStarted = false
    private var firstSaveWaiters: [CheckedContinuation<Void, Never>] = []
    private var firstSaveRelease: CheckedContinuation<Void, Never>?

    func save(_ checkpoint: RideDurableCheckpoint) async throws {
        _ = checkpoint
        saveCount += 1
        if saveCount == 1 {
            firstSaveStarted = true
            let waiters = firstSaveWaiters
            firstSaveWaiters.removeAll()
            for waiter in waiters {
                waiter.resume()
            }
            await withCheckedContinuation { continuation in
                firstSaveRelease = continuation
            }
            throw TransactionInjectedFailure.suspendedSave
        }
        Issue.record("a queued ingest reached the store after persistence fault")
    }

    func load() async throws -> RideDurableCheckpoint? {
        nil
    }

    func clear() async throws {}

    func waitUntilFirstSaveStarts() async {
        if firstSaveStarted {
            return
        }
        await withCheckedContinuation { continuation in
            firstSaveWaiters.append(continuation)
        }
    }

    func failFirstSaveNow() {
        let continuation = firstSaveRelease
        firstSaveRelease = nil
        continuation?.resume()
    }
}

private actor WriteThenThrowCheckpointStore: RideCheckpointStore {
    private(set) var value: RideDurableCheckpoint?
    private(set) var saveCount = 0
    private var shouldThrowAfterNextWrite = false

    func save(_ checkpoint: RideDurableCheckpoint) async throws {
        value = checkpoint
        saveCount += 1
        if shouldThrowAfterNextWrite {
            shouldThrowAfterNextWrite = false
            throw TransactionInjectedFailure.writeThenThrow
        }
    }

    func load() async throws -> RideDurableCheckpoint? {
        value
    }

    func clear() async throws {
        value = nil
    }

    func throwAfterNextWrite() {
        shouldThrowAfterNextWrite = true
    }
}

@Suite("Ride checkpoint coordinator transaction hardening")
struct RideCheckpointCoordinatorTransactionTests {
    private let epoch = Date(timeIntervalSince1970: 1_700_200_000)
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
        let speedSample = try speedKPH.map {
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
            speedSample: speedSample,
            odometerKilometers: odometer
        )
    }

    private func recoveredCheckpoint(
        transportGapEvidence: RideTransportGapEvidence
    ) throws -> RideRecoveryCheckpoint {
        try RideRecoveryCheckpoint(
            sessionID: fixedSessionID,
            beganAtDate: epoch,
            confirmedAtDate: epoch.addingTimeInterval(1),
            persistedPhase: .active,
            phaseBeganAtDate: nil,
            lastObservedAtDate: epoch.addingTimeInterval(2),
            checkpointedAtDate: epoch.addingTimeInterval(2),
            startingOdometerKilometers: 100,
            latestOdometerKilometers: 100.5,
            accumulatedGPSDistanceMeters: 500,
            transportGapEvidence: transportGapEvidence
        )
    }

    private func waitUntilOneMutationIsQueued(
        on coordinator: RideCheckpointCoordinator
    ) async -> Bool {
        for _ in 0..<100_000 {
            if await coordinator.queuedMutationCountForTesting() == 1 {
                return true
            }
            await Task.yield()
        }
        return false
    }

    @Test("fresh post-recovery direct gap evidence checkpoints immediately and survives another recovery")
    func recoveredDirectGapEvidenceIsImmediatelyDurable() async throws {
        let sessionID = fixedSessionID
        for initialEvidence in [RideTransportGapEvidence.noneObserved, .unknown] {
            let store = TransactionTestCheckpointStore(
                value: .inProgress(try recoveredCheckpoint(transportGapEvidence: initialEvidence))
            )
            let firstRecoveryUptime: UInt64 = 50_000_000_000
            let firstRecovery = try await RideCheckpointCoordinator.restoring(
                policy: try policy(),
                store: store,
                cadence: try cadence(),
                recoveredAtUptimeNanoseconds: firstRecoveryUptime,
                recoveredAtDate: epoch.addingTimeInterval(50),
                makeSessionID: { sessionID }
            )

            _ = try await firstRecovery.ingest(
                observation(
                    firstRecoveryUptime + 1,
                    connection: .reconnecting,
                    odometer: 100.5
                )
            )

            guard case let .inProgress(afterFreshGap)? = await store.value else {
                Issue.record("fresh direct gap evidence must remain in the in-progress journal")
                continue
            }
            #expect(afterFreshGap.transportGapEvidence == .observed)
            #expect(await store.saveCount == 1)

            let secondRecoveryUptime: UInt64 = 60_000_000_000
            let secondRecovery = try await RideCheckpointCoordinator.restoring(
                policy: try policy(),
                store: store,
                cadence: try cadence(),
                recoveredAtUptimeNanoseconds: secondRecoveryUptime,
                recoveredAtDate: epoch.addingTimeInterval(60),
                makeSessionID: { sessionID }
            )
            _ = try await secondRecovery.ingest(
                observation(
                    secondRecoveryUptime + 1,
                    connection: .connected,
                    speedKPH: 8,
                    odometer: 100.6
                )
            )

            guard case let .inProgress(afterSecondRecovery)? = await store.value else {
                Issue.record("resumed recovered ride must remain journaled")
                continue
            }
            #expect(afterSecondRecovery.transportGapEvidence == .observed)
        }
    }

    @Test("overlapping ingests serialize after the second mutation is observably queued")
    func overlappingIngestsSerializeAcrossStoreAwait() async throws {
        let sessionID = fixedSessionID
        let store = BlockingCheckpointStore()
        let coordinator = RideCheckpointCoordinator(
            engine: RideEngine(policy: try policy(), makeSessionID: { sessionID }),
            store: store,
            cadence: try cadence()
        )
        let firstObservation = try observation(1_000, speedKPH: 8, odometer: 100)
        let secondObservation = try observation(2_000, speedKPH: 8, odometer: 100.1)

        let firstTask = Task {
            try await coordinator.ingest(firstObservation)
        }
        await store.waitUntilFirstSaveStarts()

        let secondTask = Task {
            try await coordinator.ingest(secondObservation)
        }
        let queued = await waitUntilOneMutationIsQueued(on: coordinator)
        #expect(queued)
        #expect(await store.saveCount == 1)
        #expect(await store.maximumConcurrentSaves == 1)

        await store.releaseFirstSave()
        _ = try await firstTask.value
        _ = try await secondTask.value

        #expect(await store.maximumConcurrentSaves == 1)
        #expect(await store.saveCount == 1)

        await #expect(throws: RideEngineError.nonMonotonicObservation) {
            _ = try await coordinator.ingest(
                observation(1_500, speedKPH: 8, odometer: 100.05)
            )
        }
    }

    @Test("queued ingest observes a save fault only after it is confirmed waiting behind the permit")
    func queuedIngestFailsClosedAfterSuspendedSaveError() async throws {
        let sessionID = fixedSessionID
        let store = SuspendedFailingCheckpointStore()
        let coordinator = RideCheckpointCoordinator(
            engine: RideEngine(policy: try policy(), makeSessionID: { sessionID }),
            store: store,
            cadence: try cadence()
        )
        let firstObservation = try observation(1_000, speedKPH: 8, odometer: 100)
        let secondObservation = try observation(2_000, speedKPH: 8, odometer: 100.1)

        let firstTask = Task {
            try await coordinator.ingest(firstObservation)
        }
        await store.waitUntilFirstSaveStarts()

        let secondTask = Task {
            try await coordinator.ingest(secondObservation)
        }
        let queued = await waitUntilOneMutationIsQueued(on: coordinator)
        #expect(queued)
        #expect(await store.saveCount == 1)

        await store.failFirstSaveNow()
        await #expect(throws: TransactionInjectedFailure.suspendedSave) {
            _ = try await firstTask.value
        }
        await #expect(throws: RideCheckpointCoordinatorError.checkpointPersistenceUnavailable) {
            _ = try await secondTask.value
        }

        #expect(await store.saveCount == 1)
        #expect(await coordinator.currentPhase() == .idle)
    }

    @Test("terminal write that physically lands before throwing is reconciled only by fresh restore")
    func terminalWriteThenThrowCannotBeSupersededInProcess() async throws {
        let sessionID = fixedSessionID
        let store = WriteThenThrowCheckpointStore()
        let coordinator = RideCheckpointCoordinator(
            engine: RideEngine(policy: try policy(), makeSessionID: { sessionID }),
            store: store,
            cadence: try cadence()
        )

        _ = try await coordinator.ingest(observation(1_000, speedKPH: 8, odometer: 100))
        _ = try await coordinator.ingest(observation(1_500, speedKPH: 8, odometer: 100.1))
        _ = try await coordinator.ingest(observation(2_000, speedKPH: 0, odometer: 100.1))
        let preTerminalPhase = await coordinator.currentPhase()
        await store.throwAfterNextWrite()

        await #expect(throws: TransactionInjectedFailure.writeThenThrow) {
            _ = try await coordinator.ingest(
                observation(7_000, speedKPH: 0, odometer: 100.1)
            )
        }

        #expect(await coordinator.currentPhase() == preTerminalPhase)
        #expect(await coordinator.pendingCompletedRideEvidence() == nil)
        guard case let .completedPendingCommit(writtenCompletion)? = await store.value else {
            Issue.record("terminal bytes must have landed before the injected error")
            return
        }

        await #expect(throws: RideCheckpointCoordinatorError.checkpointPersistenceUnavailable) {
            _ = try await coordinator.ingest(
                observation(8_000, speedKPH: 8, odometer: 100.2)
            )
        }
        #expect(await store.value == .completedPendingCommit(writtenCompletion))

        let restored = try await RideCheckpointCoordinator.restoring(
            policy: try policy(),
            store: store,
            cadence: try cadence(),
            recoveredAtUptimeNanoseconds: 50_000,
            recoveredAtDate: epoch.addingTimeInterval(50),
            makeSessionID: { sessionID }
        )
        #expect(await restored.pendingCompletedRideEvidence() == writtenCompletion)
        #expect(await restored.currentPhase() == .idle)
        await #expect(throws: RideCheckpointCoordinatorError.completedRideAwaitingCommit(sessionID)) {
            _ = try await restored.ingest(
                observation(51_000, speedKPH: 8, odometer: 100.3)
            )
        }
    }
}
