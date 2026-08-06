#!/usr/bin/env python3
from pathlib import Path


def replace_once(path: str, old: str, new: str, label: str) -> None:
    p = Path(path)
    text = p.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one anchor, found {count}")
    p.write_text(text.replace(old, new, 1))


replace_once(
    "Packages/NembraCore/Sources/NembraCore/SimulatedScooterService.swift",
    '''    public func setLocked(_ locked: Bool) async throws {
        guard profile.capabilities.supportsLock else { throw ScooterCommandError.unsupportedCapability }
        let generation = try beginCommand()
        defer { finishCommand() }
        guard (state.speedKilometersPerHour ?? 0) < 0.5 else { throw ScooterCommandError.commandRejected }
        try await acknowledgeLatency(expectedConnectionGeneration: generation)
        state.isLocked = locked
        publish()
    }
''',
    '''    public func setLocked(_ locked: Bool) async throws {
        guard profile.capabilities.supportsLock else { throw ScooterCommandError.unsupportedCapability }
        let generation = try beginCommand()
        defer { finishCommand() }

        // Locking is safety-sensitive: unknown speed is not the same thing as
        // stopped. Require a fresh, finite stationary value both before and
        // after acknowledgement because the actor can re-enter while waiting
        // for the simulated transport confirmation. Unlocking stays available
        // even when speed is unknown.
        if locked {
            guard let speed = state.speedKilometersPerHour,
                  speed.isFinite,
                  speed >= 0,
                  speed < 0.5 else {
                throw ScooterCommandError.commandRejected
            }
        }

        try await acknowledgeLatency(expectedConnectionGeneration: generation)

        if locked {
            guard let speed = state.speedKilometersPerHour,
                  speed.isFinite,
                  speed >= 0,
                  speed < 0.5 else {
                throw ScooterCommandError.commandRejected
            }
        }

        state.isLocked = locked
        publish()
    }
''',
    "SimulatedScooterService.setLocked",
)

replace_once(
    "NembraApp/Features/Home/HomeView.swift",
    '''    private var lockSubtitle: String {
        guard let locked = vehicle.state.isLocked else { return "Unknown" }
        if !locked && isVehicleMoving { return "Stop to lock" }
        return locked ? "Secured" : "Ready"
    }

    private var isVehicleMoving: Bool {
        (vehicle.state.speedKilometersPerHour ?? 0) >= 0.5
    }

    private var canChangeLockState: Bool {
        vehicle.state.isLocked == true || !isVehicleMoving
    }
''',
    '''    private var lockSubtitle: String {
        guard let locked = vehicle.state.isLocked else { return "Unknown" }
        if locked { return "Secured" }
        guard let speed = confirmedVehicleSpeedKilometersPerHour else { return "Speed unavailable" }
        return speed >= 0.5 ? "Stop to lock" : "Ready"
    }

    private var confirmedVehicleSpeedKilometersPerHour: Double? {
        guard let speed = vehicle.state.speedKilometersPerHour,
              speed.isFinite,
              speed >= 0 else {
            return nil
        }
        return speed
    }

    private var isVehicleMoving: Bool {
        confirmedVehicleSpeedKilometersPerHour.map { $0 >= 0.5 } ?? false
    }

    private var canChangeLockState: Bool {
        if vehicle.state.isLocked == true { return true }
        guard let speed = confirmedVehicleSpeedKilometersPerHour else { return false }
        return speed < 0.5
    }
''',
    "Home lock availability",
)

replace_once(
    "NembraApp/Features/Dashboard/DashboardView.swift",
    '''        } else if vehicle.state.connection == .connected {
            Text(isVehicleMoving ? "RIDING" : "READY")
                .font(.caption2.weight(.bold))
                .tracking(2.4)
                .foregroundStyle(.secondary)
        } else {
''',
    '''        } else if vehicle.state.connection == .connected {
            if let speed = confirmedVehicleSpeedKilometersPerHour {
                Text(speed >= 0.5 ? "RIDING" : "READY")
                    .font(.caption2.weight(.bold))
                    .tracking(2.4)
                    .foregroundStyle(.secondary)
            } else {
                Text("SPEED UNAVAILABLE")
                    .font(.caption2.weight(.bold))
                    .tracking(2.2)
                    .foregroundStyle(.secondary)
            }
        } else {
''',
    "Dashboard live-state caption",
)

replace_once(
    "NembraApp/Features/Dashboard/DashboardView.swift",
    '''    private var shouldShowStoppedControls: Bool {
        vehicle.state.connection == .connected && !isVehicleMoving
    }

    private var shouldShowMovingReadout: Bool {
        vehicle.state.connection == .connected && isVehicleMoving
    }

    private var isVehicleMoving: Bool {
        (vehicle.state.speedKilometersPerHour ?? 0) >= 0.5
    }
''',
    '''    private var shouldShowStoppedControls: Bool {
        vehicle.state.connection == .connected && isVehicleConfirmedStopped
    }

    private var shouldShowMovingReadout: Bool {
        vehicle.state.connection == .connected && isVehicleMoving
    }

    private var confirmedVehicleSpeedKilometersPerHour: Double? {
        guard let speed = vehicle.state.speedKilometersPerHour,
              speed.isFinite,
              speed >= 0 else {
            return nil
        }
        return speed
    }

    private var isVehicleMoving: Bool {
        confirmedVehicleSpeedKilometersPerHour.map { $0 >= 0.5 } ?? false
    }

    private var isVehicleConfirmedStopped: Bool {
        confirmedVehicleSpeedKilometersPerHour.map { $0 < 0.5 } ?? false
    }
''',
    "Dashboard stopped/moving classification",
)

replace_once(
    "Packages/NembraCore/Tests/NembraCoreTests/SimulatedScooterServiceTests.swift",
    '''    @Test("locking is rejected while moving")
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
''',
    '''    @Test("locking is rejected while moving")
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
''',
    "lock safety regression tests",
)

print("Phase 9 lock-safety patch applied successfully.")
