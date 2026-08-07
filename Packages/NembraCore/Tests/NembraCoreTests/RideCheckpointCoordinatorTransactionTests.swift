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

private actor OverlapDetectingCheckpointStore: RideCheckpointStore {
    private(set) var value: RideDurableCheckpoint?
    private(set) var saveCount = 0
    private(set) var maximumConcurrentSaves = 0

    private var activeSaves = 0
    private var firstSaveStarted = false
    private var firstSaveWaiters: [CheckedContinuation<Void, Never>] = []

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

            // Keep the first durable write suspended long enough for a competing
            // ingest task to reach the coordinator. Before the coordinator's
            // transaction permit existed, that second ingest re-entered the
            // actor, staged from the old engine, and entered this store as a
            // concurrent save. With serialization it cannot reach the store
            // until this first save and engine commit finish.
            try await Task.sleep(for: .milliseconds(75))
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

    @Test("fresh post-recovery direct gap evidence checkpoints immediately and survives another recovery")
    func recoveredDirectGapEvidenceIsImmediatelyDurable() async throws {
        let sessionID = fixedSessionID
        for initialEvidence in [RideTransportGapEvidence.noneObserved, .unknown] {
            let store = TransactionTestCheckpointStore(
                value: .inProgress(try recoveredCheckpoint(transportGapEvidence: initialEvidence))
            )
            let firstRecovery = try await RideCheckpointCoordinator.restoring(
                policy: try policy(),
                store: store,
                cadence: try cadence(),
                recoveredAtUptimeNanoseconds: 50_000,
                recoveredAtDate: epoch.addingTimeInterval(50),
                makeSessionID: { sessionID }
            )

            // Recovery already places the engine in temporarilyDisconnected, so
            // this reconnecting observation changes provenance without producing
            // another phase-transition event. Direct evidence must still bypass
            // the long periodic cadence and reach the durable journal now.
            _ = try await firstRecovery.ingest(
                observation(
                    50_001,
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

            // Model a second process loss immediately after that one observation.
            // The new coordinator must reconstruct the direct observation as
            // durable evidence rather than degrading it back to unknown.
            let secondRecovery = try await RideCheckpointCoordinator.restoring(
                policy: try policy(),
                store: store,
                cadence: try cadence(),
                recoveredAtUptimeNanoseconds: 60_000,
                recoveredAtDate: epoch.addingTimeInterval(60),
                makeSessionID: { sessionID }
            )
            _ = try await secondRecovery.ingest(
                observation(
                    60_001,
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

    @Test("overlapping ingests cannot stage from stale engine state while a checkpoint save is suspended")
    func overlappingIngestsSerializeAcrossStoreAwait() async throws {
        let sessionID = fixedSessionID
        let store = OverlapDetectingCheckpointStore()
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

        _ = try await firstTask.value
        _ = try await secondTask.value

        // Without an explicit coordinator transaction permit, the actor can
        // re-enter during the first store.save await. The second ingest then
        // stages from the old idle engine and enters a second save concurrently.
        #expect(await store.maximumConcurrentSaves == 1)
        #expect(await store.saveCount == 1)

        // Both observations must nevertheless have committed in order. If the
        // first staged engine overwrote the second after its delayed save, this
        // older timestamp would be accepted instead of rejected.
        await #expect(throws: RideEngineError.nonMonotonicObservation) {
            _ = try await coordinator.ingest(
                observation(1_500, speedKPH: 8, odometer: 100.05)
            )
        }
    }
}
