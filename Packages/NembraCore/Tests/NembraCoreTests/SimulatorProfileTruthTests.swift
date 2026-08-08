import Testing
@testable import NembraCore

private actor SimulatorTruthCommandGate {
    private var hasEntered = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func waitForRelease() async {
        hasEntered = true
        let waiters = entryWaiters
        entryWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }

        await withCheckedContinuation { continuation in
            releaseWaiters.append(continuation)
        }
    }

    func waitUntilEntered() async {
        if hasEntered { return }
        await withCheckedContinuation { continuation in
            entryWaiters.append(continuation)
        }
    }

    func release() {
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }
}

@Suite("Simulator profile truth")
struct SimulatorProfileTruthTests {
    @Test("default simulator service uses an explicitly synthetic profile")
    func defaultSimulatorProfileIsSynthetic() {
        let service = SimulatedScooterService(commandLatencyNanoseconds: 0)

        #expect(service.profile == .simulatorQA)
        #expect(service.profile.identity.displayName == "Nembra Simulator")
        #expect(service.profile.identity.protocolFamily.contains("Synthetic QA"))
        #expect(service.profile != .aovoproES80)
        #expect(service.profile != .maxshotV1SPro)
    }

    @Test("synthetic capabilities stay separate from ES80 hardware claims")
    func simulatorCapabilitiesDoNotExpandES80Profile() {
        let simulator = VehicleProfile.simulatorQA.capabilities
        let es80 = VehicleProfile.aovoproES80.capabilities

        #expect(simulator.supportsPowerWatts)
        #expect(simulator.supportsCurrentAmps)
        #expect(simulator.supportedRideModes == Set(RideMode.allCases))
        #expect(simulator.speedLimitRangesBySlot.count == 3)

        #expect(!es80.supportsPowerWatts)
        #expect(!es80.supportsCurrentAmps)
        #expect(es80.supportedRideModes.isEmpty)
        #expect(es80.speedLimitRangesBySlot.isEmpty)
    }

    @Test("synthetic profile never acquires a physical protocol family")
    func simulatorIdentityStaysSynthetic() {
        let identity = VehicleProfile.simulatorQA.identity

        #expect(identity.manufacturer == "NEMBRA")
        #expect(identity.model == "Simulator")
        #expect(identity.protocolFamily.contains("not physical scooter protocol"))
        #expect(!identity.protocolFamily.contains("Tuya"))
    }

    @Test("cancelled connection attempt never manufactures connected state")
    func cancelledConnectionReturnsToDisconnected() async {
        let service = SimulatedScooterService(commandLatencyNanoseconds: 0)
        let task = Task {
            withUnsafeCurrentTask { currentTask in
                currentTask?.cancel()
            }
            await service.connect()
        }

        await task.value
        let state = await service.snapshot()

        #expect(state.connection == .disconnected)
        #expect(state.connectionIssue == nil)
    }

    @Test("mid-flight connection cancellation publishes disconnected instead of connected")
    func midFlightCancellationFailsClosed() async throws {
        let service = SimulatedScooterService(commandLatencyNanoseconds: 0)
        let stream = await service.stateUpdates()
        var iterator = stream.makeAsyncIterator()

        let initial = try #require(await iterator.next())
        #expect(initial.connection == .disconnected)

        let task = Task { await service.connect() }
        let connecting = try #require(await iterator.next())
        #expect(connecting.connection == .connecting)

        task.cancel()
        await task.value

        let cancelled = try #require(await iterator.next())
        #expect(cancelled.connection == .disconnected)
        #expect(cancelled.connectionIssue == nil)
        #expect((await service.snapshot()).connection == .disconnected)
    }

    @Test("negative synthetic speed is rejected instead of becoming stopped telemetry")
    func negativeRideSpeedDoesNotMutateState() async {
        let initial = SimulatedScooterService.state(for: .connectedStopped)
        let service = SimulatedScooterService(
            initialState: initial,
            commandLatencyNanoseconds: 0
        )

        await service.simulateRide(speedKilometersPerHour: -4, elapsedSeconds: 30)
        let snapshot = await service.snapshot()

        #expect(snapshot == initial)
    }

    @Test("lock confirmation revalidates stopped speed after acknowledgement")
    func lockFailsIfVehicleStartsMovingWhilePending() async {
        let gate = SimulatorTruthCommandGate()
        var state = SimulatedScooterService.state(for: .connectedStopped)
        state.speedKilometersPerHour = 0
        state.isLocked = false
        let service = SimulatedScooterService(
            initialState: state,
            commandAcknowledgementGate: {
                await gate.waitForRelease()
            }
        )

        let command = Task {
            try await service.setLocked(true)
        }
        await gate.waitUntilEntered()
        await service.simulateRide(speedKilometersPerHour: 18, elapsedSeconds: 1)
        await gate.release()

        await #expect(throws: ScooterCommandError.commandRejected) {
            try await command.value
        }
        let snapshot = await service.snapshot()
        #expect(snapshot.isLocked == false)
        #expect(snapshot.speedKilometersPerHour == 18)
    }

    @Test("lock confirmation requires valid stopped speed evidence")
    func lockFailsClosedWithoutValidStoppedSpeed() async {
        let invalidSpeeds: [Double?] = [nil, .nan, .infinity, -.infinity, -0.1, 0.5, 18]

        for speed in invalidSpeeds {
            var state = SimulatedScooterService.state(for: .connectedStopped)
            state.speedKilometersPerHour = speed
            state.isLocked = false
            let service = SimulatedScooterService(
                initialState: state,
                commandLatencyNanoseconds: 0
            )

            await #expect(throws: ScooterCommandError.commandRejected) {
                try await service.setLocked(true)
            }
            #expect((await service.snapshot()).isLocked == false)
        }
    }

    @Test("known stopped speed can still confirm lock")
    func lockAcceptsKnownStoppedSpeed() async throws {
        var state = SimulatedScooterService.state(for: .connectedStopped)
        state.speedKilometersPerHour = 0
        state.isLocked = false
        let service = SimulatedScooterService(
            initialState: state,
            commandLatencyNanoseconds: 0
        )

        try await service.setLocked(true)
        #expect((await service.snapshot()).isLocked == true)
    }
}
