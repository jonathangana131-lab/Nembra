import Testing
@testable import NembraCore

private actor CommandAcknowledgementGate {
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

@Suite("Simulated scooter command semantics")
struct SimulatedScooterServiceTests {
    @Test("commands fail while disconnected and do not lie about state")
    func disconnectedCommandFails() async {
        let service = SimulatedScooterService(commandLatencyNanoseconds: 0)
        await #expect(throws: ScooterCommandError.disconnected) {
            try await service.setHeadlight(true)
        }
        let snapshot = await service.snapshot()
        #expect(snapshot.isHeadlightOn == false)
    }

    @Test("headlight commits only after a connected acknowledgement")
    func headlightAcknowledgement() async throws {
        let service = SimulatedScooterService(commandLatencyNanoseconds: 0)
        await service.connect()
        try await service.setHeadlight(true)
        let snapshot = await service.snapshot()
        #expect(snapshot.connection == .connected)
        #expect(snapshot.isHeadlightOn == true)
    }

    @Test("speed-limit slot 3 respects its verified schema ceiling")
    func speedLimitSlotValidation() async throws {
        let service = SimulatedScooterService(commandLatencyNanoseconds: 0)
        await service.connect()
        try await service.setSpeedLimit(kilometersPerHour: 35, slot: .limit3)
        await #expect(throws: ScooterCommandError.valueOutOfRange) {
            try await service.setSpeedLimit(kilometersPerHour: 40, slot: .limit3)
        }
    }

    @Test("locking is rejected while moving")
    func movingLockRejected() async {
        let service = SimulatedScooterService(commandLatencyNanoseconds: 0)
        await service.connect()
        await service.simulateRide(speedKilometersPerHour: 18, elapsedSeconds: 1)
        await #expect(throws: ScooterCommandError.commandRejected) {
            try await service.setLocked(true)
        }
        let snapshot = await service.snapshot()
        #expect(snapshot.isLocked == false)
    }

    @Test("locking requires confirmed stationary speed while unlocking remains available")
    func unknownSpeedRejectsLockButAllowsUnlock() async throws {
        var unlockedUnknown = SimulatedScooterService.state(for: .connectedStopped)
        unlockedUnknown.speedKilometersPerHour = nil
        unlockedUnknown.isLocked = false
        let unlockedService = SimulatedScooterService(
            initialState: unlockedUnknown,
            commandLatencyNanoseconds: 0
        )

        await #expect(throws: ScooterCommandError.commandRejected) {
            try await unlockedService.setLocked(true)
        }
        #expect((await unlockedService.snapshot()).isLocked == false)

        var lockedUnknown = unlockedUnknown
        lockedUnknown.isLocked = true
        let lockedService = SimulatedScooterService(
            initialState: lockedUnknown,
            commandLatencyNanoseconds: 0
        )
        try await lockedService.setLocked(false)
        #expect((await lockedService.snapshot()).isLocked == false)
    }

    @Test("locking rechecks speed after acknowledgement before committing")
    func movementDuringLockAcknowledgementRejectsCommit() async {
        let gate = CommandAcknowledgementGate()
        let service = SimulatedScooterService(
            initialState: SimulatedScooterService.state(for: .connectedStopped),
            commandAcknowledgementGate: {
                await gate.waitForRelease()
            }
        )

        let command = Task {
            try await service.setLocked(true)
        }
        await gate.waitUntilEntered()
        await service.simulateRide(speedKilometersPerHour: 6, elapsedSeconds: 0.1)
        await gate.release()

        await #expect(throws: ScooterCommandError.commandRejected) {
            try await command.value
        }
        let snapshot = await service.snapshot()
        #expect(snapshot.isLocked == false)
        #expect((snapshot.speedKilometersPerHour ?? 0) >= 0.5)
    }

    @Test("speed-limit slots remain independent of ride mode")
    func speedLimitSlotsAreIndependent() async throws {
        let service = SimulatedScooterService(commandLatencyNanoseconds: 0)
        await service.connect()

        try await service.setSpeedLimit(kilometersPerHour: 19, slot: .limit2)
        #expect((await service.snapshot()).speedLimitsKilometersPerHour[.limit2] == 19)

        try await service.setRideMode(.sport)
        #expect((await service.snapshot()).speedLimitsKilometersPerHour[.limit2] == 19)

        try await service.setRideMode(.eco)
        let snapshot = await service.snapshot()
        #expect(snapshot.speedLimitsKilometersPerHour[.limit2] == 19)
        #expect(snapshot.speedLimitsKilometersPerHour[.limit3] == 35)
    }

    @Test("MAXSHOT profile does not invent a speed-limit to ride-mode mapping")
    func maxshotProfileKeepsMappingUnknown() {
        let capabilities = VehicleProfile.maxshotV1SPro.capabilities
        #expect(capabilities.supportsSpeedLimit)
        #expect(capabilities.speedLimitRangesBySlot.count == 3)
        #expect(capabilities.verifiedSpeedLimitSlotByRideMode.isEmpty)
        #expect(capabilities.hasUserFacingSpeedLimitMapping == false)
    }

    @Test("cruise and start mode commit after acknowledgement")
    func confirmedConfigurationCommands() async throws {
        let service = SimulatedScooterService(commandLatencyNanoseconds: 0)
        await service.connect()

        try await service.setCruise(true)
        try await service.setStartMode(.kickStart)

        let snapshot = await service.snapshot()
        #expect(snapshot.isCruiseEnabled == true)
        #expect(snapshot.startMode == .kickStart)
    }

    @Test("service rejects overlapping state-changing commands")
    func overlappingCommandsAreRejected() async throws {
        let gate = CommandAcknowledgementGate()
        let service = SimulatedScooterService(commandAcknowledgementGate: {
            await gate.waitForRelease()
        })
        await service.connect()

        let firstCommand = Task {
            try await service.setHeadlight(true)
        }
        await gate.waitUntilEntered()

        await #expect(throws: ScooterCommandError.commandInProgress) {
            try await service.setCruise(true)
        }
        await gate.release()
        try await firstCommand.value

        let snapshot = await service.snapshot()
        #expect(snapshot.isHeadlightOn == true)
        #expect(snapshot.isCruiseEnabled == false)
    }

    @Test("disconnect and fast reconnect still invalidates the old command")
    func reconnectCannotResurrectOldCommand() async {
        let gate = CommandAcknowledgementGate()
        let service = SimulatedScooterService(commandAcknowledgementGate: {
            await gate.waitForRelease()
        })
        await service.connect()

        let command = Task {
            try await service.setHeadlight(true)
        }
        await gate.waitUntilEntered()
        await service.simulateConnectionDrop()
        await service.simulateReconnected()
        await gate.release()

        await #expect(throws: ScooterCommandError.disconnected) {
            try await command.value
        }
        let snapshot = await service.snapshot()
        #expect(snapshot.connection == .connected)
        #expect(snapshot.isHeadlightOn == false)
    }

    @Test("connection loss during command latency prevents a false commit")
    func disconnectDuringCommandPreventsCommit() async {
        let gate = CommandAcknowledgementGate()
        let service = SimulatedScooterService(commandAcknowledgementGate: {
            await gate.waitForRelease()
        })
        await service.connect()

        let command = Task {
            try await service.setHeadlight(true)
        }
        await gate.waitUntilEntered()
        await service.simulateConnectionDrop()
        await gate.release()

        await #expect(throws: ScooterCommandError.disconnected) {
            try await command.value
        }
        #expect((await service.snapshot()).isHeadlightOn == false)
    }

    @Test("disconnect cancels an in-progress connection attempt")
    func disconnectCancelsConnectionAttempt() async {
        let service = SimulatedScooterService(commandLatencyNanoseconds: 0)
        let connection = Task { await service.connect() }
        try? await Task.sleep(nanoseconds: 20_000_000)
        await service.disconnect()
        await connection.value
        #expect((await service.snapshot()).connection == .disconnected)
    }

    @Test("Bluetooth-off and denied states block fake connection success")
    func blockedConnectionIssuesStayBlocked() async {
        for scenario in [ScooterSimulationScenario.bluetoothOff, .permissionDenied] {
            let initial = SimulatedScooterService.state(for: scenario)
            let service = SimulatedScooterService(initialState: initial, commandLatencyNanoseconds: 0)
            await service.connect()
            let snapshot = await service.snapshot()
            #expect(snapshot.connection == .disconnected)
            #expect(snapshot.connectionIssue == initial.connectionIssue)
        }
    }

    @Test("connection issue fixtures distinguish Bluetooth state from scooter availability")
    func connectionIssueFixtures() {
        let bluetoothOff = SimulatedScooterService.state(for: .bluetoothOff)
        #expect(bluetoothOff.connectionIssue == .bluetoothPoweredOff)
        #expect(bluetoothOff.batteryPercent == nil)

        let denied = SimulatedScooterService.state(for: .permissionDenied)
        #expect(denied.connectionIssue == .bluetoothPermissionDenied)
        #expect(denied.rideMode == nil)

        let unavailable = SimulatedScooterService.state(for: .scooterUnavailable)
        #expect(unavailable.connectionIssue == .scooterUnavailable)
        #expect(unavailable.batteryPercent == 71)
        #expect(unavailable.rideMode == .drive)

        let unsupported = SimulatedScooterService.state(for: .unsupportedConfiguration)
        #expect(unsupported.connectionIssue == .unsupportedConfiguration)
        #expect(unsupported.odometerKilometers == nil)
    }

    @Test("scooter-unavailable scenario can recover only after an explicit retry")
    func unavailableScenarioCanRecover() async {
        let initial = SimulatedScooterService.state(for: .scooterUnavailable)
        let service = SimulatedScooterService(initialState: initial, commandLatencyNanoseconds: 0)
        #expect((await service.snapshot()).connectionIssue == .scooterUnavailable)
        await service.connect()
        let snapshot = await service.snapshot()
        #expect(snapshot.connection == .connected)
        #expect(snapshot.connectionIssue == nil)
    }


    @Test("cold disconnected retry hydrates confirmed data after simulated handshake")
    func coldReconnectHydratesMissingData() async {
        let service = SimulatedScooterService(
            initialState: SimulatedScooterService.state(for: .coldDisconnected),
            commandLatencyNanoseconds: 0
        )
        #expect((await service.snapshot()).dataAvailability == .unavailable)

        await service.connect()
        let snapshot = await service.snapshot()

        #expect(snapshot.connection == .connected)
        #expect(snapshot.dataAvailability == .live)
        #expect(snapshot.batteryPercent != nil)
        #expect(snapshot.rideMode != nil)
        #expect(snapshot.isHeadlightOn != nil)
        #expect(snapshot.isLocked != nil)
        #expect(snapshot.speedLimitsKilometersPerHour.count == 3)
    }

    @Test("reconnect keeps retained confirmed values instead of replacing them with fixture defaults")
    func reconnectPreservesRetainedValues() async {
        let initial = SimulatedScooterService.state(for: .scooterUnavailable)
        let service = SimulatedScooterService(initialState: initial, commandLatencyNanoseconds: 0)

        await service.connect()
        let snapshot = await service.snapshot()

        #expect(snapshot.connection == .connected)
        #expect(snapshot.connectionIssue == nil)
        #expect(snapshot.batteryPercent == initial.batteryPercent)
        #expect(snapshot.odometerKilometers == initial.odometerKilometers)
        #expect(snapshot.tripKilometers == initial.tripKilometers)
        #expect(snapshot.rideMode == initial.rideMode)
    }

    @Test("unsupported configuration stays blocked instead of faking reconnect")
    func unsupportedConfigurationStaysBlocked() async {
        let initial = SimulatedScooterService.state(for: .unsupportedConfiguration)
        let service = SimulatedScooterService(initialState: initial, commandLatencyNanoseconds: 0)
        await service.connect()
        let snapshot = await service.snapshot()
        #expect(snapshot.connection == .disconnected)
        #expect(snapshot.connectionIssue == .unsupportedConfiguration)
    }


    @Test("vehicle data availability distinguishes never-observed, live, and retained state")
    func vehicleDataAvailability() {
        let cold = SimulatedScooterService.state(for: .coldDisconnected)
        #expect(cold.hasConfirmedVehicleData == false)
        #expect(cold.dataAvailability == .unavailable)

        let connected = SimulatedScooterService.state(for: .connectedStopped)
        #expect(connected.hasConfirmedVehicleData)
        #expect(connected.dataAvailability == .live)

        let reconnecting = SimulatedScooterService.state(for: .reconnecting)
        #expect(reconnecting.hasConfirmedVehicleData)
        #expect(reconnecting.dataAvailability == .retained)

        let unavailable = SimulatedScooterService.state(for: .scooterUnavailable)
        #expect(unavailable.dataAvailability == .retained)

        let unsupported = SimulatedScooterService.state(for: .unsupportedConfiguration)
        #expect(unsupported.dataAvailability == .unavailable)
    }

    @Test("simulation launch scenarios preserve truthful known versus unknown state")
    func simulationScenarioFixtures() {
        let cold = SimulatedScooterService.state(for: .coldDisconnected)
        #expect(cold.connection == .disconnected)
        #expect(cold.rideMode == nil)
        #expect(cold.batteryPercent == nil)
        #expect(cold.speedLimitsKilometersPerHour.isEmpty)

        let connectedUnknown = SimulatedScooterService.state(for: .connectedSpeedUnknown)
        #expect(connectedUnknown.connection == .connected)
        #expect(connectedUnknown.speedKilometersPerHour == nil)
        #expect(connectedUnknown.isLocked == false)
        #expect(connectedUnknown.dataAvailability == .live)

        let riding = SimulatedScooterService.state(for: .riding)
        #expect(riding.connection == .connected)
        #expect((riding.speedKilometersPerHour ?? 0) > 0)
        #expect(riding.rideMode == .drive)
        #expect(riding.isLocked == false)
        #expect(riding.speedLimitsKilometersPerHour[.limit1] == 12)
        #expect(riding.speedLimitsKilometersPerHour[.limit2] == 18)
        #expect(riding.speedLimitsKilometersPerHour[.limit3] == 35)

        let lowBattery = SimulatedScooterService.state(for: .lowBattery)
        #expect(lowBattery.batteryPercent == 14)
        #expect(lowBattery.rideMode == .eco)
        #expect(lowBattery.isLocked == true)
    }

    @Test("cold disconnected service preserves unknown limiter state")
    func coldDisconnectedServiceDoesNotInventLimiterValues() async {
        let service = SimulatedScooterService(
            initialState: SimulatedScooterService.state(for: .coldDisconnected),
            commandLatencyNanoseconds: 0
        )
        let snapshot = await service.snapshot()
        #expect(snapshot.speedLimitsKilometersPerHour.isEmpty)
    }


    @Test("disconnect preserves last confirmed telemetry instead of inventing zero")
    func disconnectPreservesLastKnownTelemetry() async {
        let service = SimulatedScooterService(commandLatencyNanoseconds: 0)
        await service.connect()
        await service.simulateRide(speedKilometersPerHour: 18, elapsedSeconds: 2)
        let before = await service.snapshot()

        await service.disconnect()
        let after = await service.snapshot()

        #expect(after.connection == .disconnected)
        #expect(after.speedKilometersPerHour == before.speedKilometersPerHour)
        #expect(after.powerWatts == before.powerWatts)
        #expect(after.currentAmps == before.currentAmps)
        #expect(after.tripKilometers == before.tripKilometers)
        #expect(after.odometerKilometers == before.odometerKilometers)
    }

    @Test("connection issue preserves last confirmed telemetry as stale data")
    func connectionIssuePreservesLastKnownTelemetry() async {
        let service = SimulatedScooterService(commandLatencyNanoseconds: 0)
        await service.connect()
        await service.simulateRide(speedKilometersPerHour: 22, elapsedSeconds: 2)
        let before = await service.snapshot()

        await service.simulateConnectionIssue(.scooterUnavailable)
        let after = await service.snapshot()

        #expect(after.connection == .disconnected)
        #expect(after.connectionIssue == .scooterUnavailable)
        #expect(after.speedKilometersPerHour == before.speedKilometersPerHour)
        #expect(after.powerWatts == before.powerWatts)
        #expect(after.currentAmps == before.currentAmps)
    }

    @Test("ride simulation advances trip and odometer from the same evidence")
    func rideDistanceAdvances() async {
        let service = SimulatedScooterService(commandLatencyNanoseconds: 0)
        await service.connect()
        let before = await service.snapshot()
        await service.simulateRide(speedKilometersPerHour: 18, elapsedSeconds: 600)
        let after = await service.snapshot()
        #expect((after.tripKilometers ?? 0) > (before.tripKilometers ?? 0))
        #expect((after.odometerKilometers ?? 0) > (before.odometerKilometers ?? 0))
    }
}
