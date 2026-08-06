import Foundation
import Testing
@testable import NembraCore

private final class RideRuntimeTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var uptimeValue: UInt64
    private var dateValue: Date

    init(uptime: UInt64, date: Date) {
        uptimeValue = uptime
        dateValue = date
    }

    func set(uptime: UInt64, date: Date) {
        lock.lock()
        uptimeValue = uptime
        dateValue = date
        lock.unlock()
    }

    func uptime() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return uptimeValue
    }

    func date() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return dateValue
    }
}

private actor RideRuntimeTestScooterService: ScooterService {
    nonisolated let profile: VehicleProfile = .maxshotV1SPro
    private var state: VehicleState
    private var stateContinuations: [UUID: AsyncStream<VehicleState>.Continuation] = [:]
    private var speedContinuations: [UUID: AsyncStream<SpeedTelemetrySample>.Continuation] = [:]

    init(speedFieldKilometersPerHour: Double? = 0, odometerKilometers: Double? = 10) {
        state = VehicleState(
            connection: .connected,
            batteryPercent: 80,
            speedKilometersPerHour: speedFieldKilometersPerHour,
            odometerKilometers: odometerKilometers,
            tripKilometers: 1,
            rideMode: .drive,
            startMode: .zeroStart,
            speedLimitsKilometersPerHour: [:],
            isLocked: false,
            isHeadlightOn: false,
            isCruiseEnabled: false,
            powerWatts: nil,
            currentAmps: nil
        )
    }

    func stateUpdates() -> AsyncStream<VehicleState> {
        let id = UUID()
        let current = state
        return AsyncStream { continuation in
            stateContinuations[id] = continuation
            continuation.yield(current)
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeStateContinuation(id) }
            }
        }
    }

    func speedTelemetryUpdates() -> AsyncStream<SpeedTelemetrySample> {
        let id = UUID()
        return AsyncStream { continuation in
            speedContinuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeSpeedContinuation(id) }
            }
        }
    }

    func snapshot() -> VehicleState { state }
    func connect() async {}
    func disconnect() async { setConnection(.disconnected) }
    func setHeadlight(_ enabled: Bool) async throws { state.isHeadlightOn = enabled; publishState() }
    func setLocked(_ locked: Bool) async throws { state.isLocked = locked; publishState() }
    func setCruise(_ enabled: Bool) async throws { state.isCruiseEnabled = enabled; publishState() }
    func setRideMode(_ mode: RideMode) async throws { state.rideMode = mode; publishState() }
    func setStartMode(_ mode: StartMode) async throws { state.startMode = mode; publishState() }
    func setSpeedLimit(kilometersPerHour: Int, slot: SpeedLimitSlot) async throws {
        state.speedLimitsKilometersPerHour[slot] = kilometersPerHour
        publishState()
    }

    func emitSpeed(
        kilometersPerHour: Double,
        uptime: UInt64,
        date: Date,
        odometerKilometers: Double? = nil
    ) throws {
        state.speedKilometersPerHour = kilometersPerHour
        if let odometerKilometers { state.odometerKilometers = odometerKilometers }
        let sample = try SpeedTelemetrySample(
            source: .scooterBluetooth,
            provenance: .absoluteMeasurement,
            metersPerSecond: kilometersPerHour / 3.6,
            receivedAtUptimeNanoseconds: uptime,
            receivedAtDate: date
        )
        for continuation in speedContinuations.values { continuation.yield(sample) }
        publishState()
    }

    func setConnection(_ connection: VehicleConnectionState) {
        state.connection = connection
        publishState()
    }

    private func publishState() {
        for continuation in stateContinuations.values { continuation.yield(state) }
    }

    private func removeStateContinuation(_ id: UUID) { stateContinuations[id] = nil }
    private func removeSpeedContinuation(_ id: UUID) { speedContinuations[id] = nil }
}

@Suite("Ride application runtime")
struct RideApplicationRuntimeTests {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)
    private let sessionID = UUID(uuidString: "77777777-7777-7777-7777-777777777777")!

    private func policy() throws -> RideDetectionPolicy {
        try RideDetectionPolicy(
            candidateSpeedKilometersPerHour: 1,
            confirmationSpeedKilometersPerHour: 4,
            confirmationDurationNanoseconds: 0,
            confirmationOdometerDeltaKilometers: 0.05,
            confirmationGPSDistanceMeters: 8,
            endingDurationNanoseconds: 100,
            maximumSpeedSampleAgeNanoseconds: 500
        )
    }

    private func cadence() throws -> RideCheckpointCadence {
        try RideCheckpointCadence(minimumIntervalNanoseconds: 100)
    }

    private func directories() throws -> (checkpoint: URL, history: URL, root: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nembra-ride-runtime-tests-\(UUID().uuidString)", isDirectory: true)
        let checkpoint = root.appendingPathComponent("checkpoint", isDirectory: true)
        let history = root.appendingPathComponent("history", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (checkpoint, history, root)
    }

    private func runtime(
        service: RideRuntimeTestScooterService,
        checkpoint: AtomicRideCheckpointStore,
        history: AtomicRideHistoryStore,
        clock: RideRuntimeTestClock
    ) async throws -> RideApplicationRuntime {
        try await RideApplicationRuntime.restoring(
            service: service,
            detectionPolicy: try policy(),
            checkpointStore: checkpoint,
            checkpointCadence: try cadence(),
            historyStore: history,
            uptimeClock: { clock.uptime() },
            dateClock: { clock.date() },
            makeSessionID: { sessionID }
        )
    }

    private func waitForSnapshot(
        _ runtime: RideApplicationRuntime,
        timeoutIterations: Int = 400,
        predicate: @escaping (RideApplicationRuntimeSnapshot) -> Bool
    ) async -> RideApplicationRuntimeSnapshot? {
        for _ in 0..<timeoutIterations {
            let value = await runtime.snapshot()
            if predicate(value) { return value }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return nil
    }

    private func sendRideConfirmationPackets(
        service: RideRuntimeTestScooterService,
        clock: RideRuntimeTestClock,
        startingOdometer: Double = 10
    ) async throws {
        clock.set(uptime: 1_000, date: epoch.addingTimeInterval(1))
        try await service.emitSpeed(
            kilometersPerHour: 8,
            uptime: 1_000,
            date: epoch.addingTimeInterval(1),
            odometerKilometers: startingOdometer
        )

        clock.set(uptime: 1_100, date: epoch.addingTimeInterval(1.1))
        try await service.emitSpeed(
            kilometersPerHour: 8,
            uptime: 1_100,
            date: epoch.addingTimeInterval(1.1),
            odometerKilometers: startingOdometer
        )
    }

    @Test("cached VehicleState speed never starts a ride without a raw packet")
    func cachedStateSpeedIsNotRawEvidence() async throws {
        let dirs = try directories()
        defer { try? FileManager.default.removeItem(at: dirs.root) }
        let service = RideRuntimeTestScooterService(speedFieldKilometersPerHour: 20)
        let checkpoint = AtomicRideCheckpointStore(directoryURL: dirs.checkpoint)
        let history = AtomicRideHistoryStore(directoryURL: dirs.history)
        let clock = RideRuntimeTestClock(uptime: 100, date: epoch)
        let runtime = try await runtime(service: service, checkpoint: checkpoint, history: history, clock: clock)

        try await runtime.start()
        try? await Task.sleep(nanoseconds: 5_000_000)
        #expect(await runtime.snapshot().phase == .idle)
        #expect(try await checkpoint.load() == nil)
        await runtime.stop()
    }

    @Test("authoritative raw speed starts a ride and journals it")
    func rawSpeedStartsRide() async throws {
        let dirs = try directories()
        defer { try? FileManager.default.removeItem(at: dirs.root) }
        let service = RideRuntimeTestScooterService()
        let checkpoint = AtomicRideCheckpointStore(directoryURL: dirs.checkpoint)
        let history = AtomicRideHistoryStore(directoryURL: dirs.history)
        let clock = RideRuntimeTestClock(uptime: 100, date: epoch)
        let runtime = try await runtime(service: service, checkpoint: checkpoint, history: history, clock: clock)
        try await runtime.start()

        try await sendRideConfirmationPackets(service: service, clock: clock)

        let active = await waitForSnapshot(runtime) {
            if case .active = $0.phase { return true }
            return false
        }
        guard let active, case let .active(session) = active.phase else {
            Issue.record("expected active ride after sequential authoritative packets")
            return
        }
        #expect(session.id == sessionID)
        guard case let .inProgress(saved)? = try await checkpoint.load() else {
            Issue.record("active ride must have a durable checkpoint")
            return
        }
        #expect(saved.sessionID == sessionID)
        await runtime.stop()
    }

    @Test("disconnect and reconnect preserve the same ride identity")
    func disconnectContinuity() async throws {
        let dirs = try directories()
        defer { try? FileManager.default.removeItem(at: dirs.root) }
        let service = RideRuntimeTestScooterService()
        let checkpoint = AtomicRideCheckpointStore(directoryURL: dirs.checkpoint)
        let history = AtomicRideHistoryStore(directoryURL: dirs.history)
        let clock = RideRuntimeTestClock(uptime: 100, date: epoch)
        let runtime = try await runtime(service: service, checkpoint: checkpoint, history: history, clock: clock)
        try await runtime.start()

        try await sendRideConfirmationPackets(service: service, clock: clock)
        guard let started = await waitForSnapshot(runtime, predicate: {
            if case .active = $0.phase { return true }; return false
        }), case let .active(startedSession) = started.phase else {
            Issue.record("expected active ride")
            return
        }

        clock.set(uptime: 2_000, date: epoch.addingTimeInterval(2))
        await service.setConnection(.reconnecting)
        guard let disconnected = await waitForSnapshot(runtime, predicate: {
            if case .temporarilyDisconnected = $0.phase { return true }; return false
        }), case let .temporarilyDisconnected(disconnectedRide) = disconnected.phase else {
            Issue.record("expected temporary disconnect")
            return
        }
        #expect(disconnectedRide.session.id == startedSession.id)

        clock.set(uptime: 3_000, date: epoch.addingTimeInterval(3))
        await service.setConnection(.connected)
        try await service.emitSpeed(kilometersPerHour: 7, uptime: 3_000, date: epoch.addingTimeInterval(3))
        guard let resumed = await waitForSnapshot(runtime, predicate: {
            if case .active = $0.phase { return true }; return false
        }), case let .active(resumedSession) = resumed.phase else {
            Issue.record("expected resumed ride")
            return
        }
        #expect(resumedSession.id == startedSession.id)
        await runtime.stop()
    }

    @Test("ride completion is committed to permanent history before journal clears")
    func completedRideHandoff() async throws {
        let dirs = try directories()
        defer { try? FileManager.default.removeItem(at: dirs.root) }
        let service = RideRuntimeTestScooterService()
        let checkpoint = AtomicRideCheckpointStore(directoryURL: dirs.checkpoint)
        let history = AtomicRideHistoryStore(directoryURL: dirs.history)
        let clock = RideRuntimeTestClock(uptime: 100, date: epoch)
        let runtime = try await runtime(service: service, checkpoint: checkpoint, history: history, clock: clock)
        try await runtime.start()

        try await sendRideConfirmationPackets(service: service, clock: clock, startingOdometer: 10.0)
        guard await waitForSnapshot(runtime, predicate: {
            if case .active = $0.phase { return true }; return false
        }) != nil else {
            Issue.record("expected active ride before stop sequence")
            return
        }

        clock.set(uptime: 2_000, date: epoch.addingTimeInterval(2))
        try await service.emitSpeed(kilometersPerHour: 0, uptime: 2_000, date: epoch.addingTimeInterval(2), odometerKilometers: 10.0)
        _ = await waitForSnapshot(runtime) { if case .endingCandidate = $0.phase { true } else { false } }

        clock.set(uptime: 2_200, date: epoch.addingTimeInterval(2.2))
        try await service.emitSpeed(kilometersPerHour: 0, uptime: 2_200, date: epoch.addingTimeInterval(2.2), odometerKilometers: 10.0)
        let ended = await waitForSnapshot(runtime) { $0.phase == .idle && $0.pendingCompletedRideID == nil }
        #expect(ended != nil)
        #expect(try await checkpoint.load() == nil)
        #expect(try await history.record(sessionID: sessionID)?.sessionID == sessionID)
        await runtime.stop()
    }

    @Test("completed-pending recovery is flushed before new observations are accepted")
    func startupFlushesPendingCompletion() async throws {
        let dirs = try directories()
        defer { try? FileManager.default.removeItem(at: dirs.root) }
        let service = RideRuntimeTestScooterService()
        let checkpoint = AtomicRideCheckpointStore(directoryURL: dirs.checkpoint)
        let history = AtomicRideHistoryStore(directoryURL: dirs.history)
        let completed = try CompletedRideEvidence(
            sessionID: sessionID,
            beganAtDate: epoch,
            confirmedAtDate: epoch.addingTimeInterval(1),
            endedAtDate: epoch.addingTimeInterval(10),
            startingOdometerKilometers: 10,
            endingOdometerKilometers: 10.2,
            qualityScreenedGPSDistanceMeters: 0,
            continuity: .uninterruptedProcess
        )
        try await checkpoint.save(.completedPendingCommit(completed))
        let clock = RideRuntimeTestClock(uptime: 100, date: epoch.addingTimeInterval(20))
        let runtime = try await runtime(service: service, checkpoint: checkpoint, history: history, clock: clock)

        #expect(await runtime.snapshot().pendingCompletedRideID == sessionID)
        try await runtime.start()
        #expect(await runtime.snapshot().pendingCompletedRideID == nil)
        #expect(try await history.record(sessionID: sessionID) == RideHistoryRecord(evidence: completed))
        #expect(try await checkpoint.load() == nil)
        await runtime.stop()
    }
}
