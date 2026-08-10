import Testing
@testable import NembraCore

@Suite("Simulator source-owned propulsion power currentness")
struct SimulatorPowerEvidenceTests {
    @Test("connected riding fixture starts with live source-owned power")
    func connectedRidingFixtureStartsLive() async throws {
        let service = SimulatedScooterService(
            initialState: SimulatedScooterService.state(for: .riding),
            commandLatencyNanoseconds: 0
        )

        let availability = await service.simulatorPowerEvidenceSnapshot()
        guard case let .live(observation) = availability else {
            Issue.record("Expected connected Simulator riding fixture to expose live power evidence")
            return
        }
        #expect(observation.watts == 356)
        #expect(observation.receiptSequenceNumber == 1)
        #expect(observation.receivedAtUptimeNanoseconds > 0)
        #expect(observation.continuityGeneration > 0)
    }

    @Test("disconnect and normal reconnect cannot revive cached watts")
    func reconnectRequiresFreshPowerObservation() async throws {
        let service = SimulatedScooterService(
            initialState: SimulatedScooterService.state(for: .riding),
            commandLatencyNanoseconds: 0
        )

        guard case let .live(initial) = await service.simulatorPowerEvidenceSnapshot() else {
            Issue.record("Expected initial live power evidence")
            return
        }

        await service.disconnect()
        guard case let .retained(retained) = await service.simulatorPowerEvidenceSnapshot() else {
            Issue.record("Disconnect must demote power evidence to retained")
            return
        }
        #expect(retained == initial)

        await service.connect()
        #expect((await service.snapshot()).connection == .connected)
        #expect((await service.snapshot()).powerWatts == 356)
        guard case let .retained(afterReconnect) = await service.simulatorPowerEvidenceSnapshot() else {
            Issue.record("Reconnect and fresh speed evidence must not revive cached propulsion power")
            return
        }
        #expect(afterReconnect == initial)

        await service.simulateRide(speedKilometersPerHour: 18.4, elapsedSeconds: 0)
        guard case let .live(refreshed) = await service.simulatorPowerEvidenceSnapshot() else {
            Issue.record("A genuine Simulator ride observation must restore live power evidence")
            return
        }
        #expect(refreshed.watts == 356)
        #expect(refreshed.receiptSequenceNumber > initial.receiptSequenceNumber)
        #expect(refreshed.receivedAtUptimeNanoseconds > initial.receivedAtUptimeNanoseconds)
        #expect(refreshed.continuityGeneration > initial.continuityGeneration)
    }

    @Test("repeated equal watts remain distinct source observations")
    func repeatedEqualWattsAdvanceSourceReceipt() async throws {
        var initialState = SimulatedScooterService.state(for: .connectedStopped)
        initialState.isLocked = false
        let service = SimulatedScooterService(
            initialState: initialState,
            commandLatencyNanoseconds: 0
        )

        guard case let .live(initial) = await service.simulatorPowerEvidenceSnapshot() else {
            Issue.record("Expected initial live zero-watt Simulator evidence")
            return
        }

        await service.simulateRide(speedKilometersPerHour: 0, elapsedSeconds: 0)
        guard case let .live(second) = await service.simulatorPowerEvidenceSnapshot() else {
            Issue.record("Expected first repeated zero-watt observation to remain live")
            return
        }
        await service.simulateRide(speedKilometersPerHour: 0, elapsedSeconds: 0)
        guard case let .live(third) = await service.simulatorPowerEvidenceSnapshot() else {
            Issue.record("Expected second repeated zero-watt observation to remain live")
            return
        }

        #expect(initial.watts == 0)
        #expect(second.watts == 0)
        #expect(third.watts == 0)
        #expect(second.receiptSequenceNumber == initial.receiptSequenceNumber + 1)
        #expect(third.receiptSequenceNumber == second.receiptSequenceNumber + 1)
        #expect(initial.receivedAtUptimeNanoseconds > 0)
        #expect(second.receivedAtUptimeNanoseconds > initial.receivedAtUptimeNanoseconds)
        #expect(third.receivedAtUptimeNanoseconds > second.receivedAtUptimeNanoseconds)
    }

    @Test("unrelated commands cannot mint a propulsion receipt")
    func unrelatedCommandsDoNotAdvancePowerReceipt() async throws {
        let service = SimulatedScooterService(
            initialState: SimulatedScooterService.state(for: .connectedStopped),
            commandLatencyNanoseconds: 0
        )

        guard case let .live(before) = await service.simulatorPowerEvidenceSnapshot() else {
            Issue.record("Expected initial live Simulator power")
            return
        }

        try await service.setRideMode(.drive)
        try await service.setHeadlight(true)
        try await service.setCruise(true)

        guard case let .live(after) = await service.simulatorPowerEvidenceSnapshot() else {
            Issue.record("Unrelated commands must not remove existing live source evidence")
            return
        }
        #expect(after == before)
    }

    @Test("late subscriber replays retained receipt without rewriting identity")
    func lateSubscriberGetsExactRetainedReceipt() async throws {
        let service = SimulatedScooterService(
            initialState: SimulatedScooterService.state(for: .riding),
            commandLatencyNanoseconds: 0
        )

        guard case let .live(initial) = await service.simulatorPowerEvidenceSnapshot() else {
            Issue.record("Expected initial live Simulator power")
            return
        }
        await service.disconnect()

        let stream = await service.simulatorPowerEvidenceUpdates()
        var iterator = stream.makeAsyncIterator()
        #expect(await iterator.next() == .retained(initial))
    }

    @Test("invalid ride inputs cannot mint a propulsion receipt")
    func invalidRideInputsCannotAdvanceSourceReceipt() async throws {
        var initialState = SimulatedScooterService.state(for: .connectedStopped)
        initialState.isLocked = false
        let service = SimulatedScooterService(
            initialState: initialState,
            commandLatencyNanoseconds: 0
        )

        guard case let .live(initial) = await service.simulatorPowerEvidenceSnapshot() else {
            Issue.record("Expected initial live Simulator power")
            return
        }

        let invalidInputs: [(Double, Double)] = [
            (-1, 0),
            (.nan, 0),
            (.infinity, 0),
            (0, -1),
            (0, .nan),
            (0, .infinity)
        ]
        for (speed, elapsed) in invalidInputs {
            await service.simulateRide(speedKilometersPerHour: speed, elapsedSeconds: elapsed)
            #expect(await service.simulatorPowerEvidenceSnapshot() == .live(initial))
        }
    }

    @Test("non-Simulator profile cannot expose synthetic power authority")
    func physicalProfileFailsClosed() async throws {
        let service = SimulatedScooterService(
            profile: .aovoproES80,
            initialState: SimulatedScooterService.state(for: .riding),
            commandLatencyNanoseconds: 0
        )

        #expect(await service.simulatorPowerEvidenceSnapshot() == .unavailable)
        await service.simulateRide(speedKilometersPerHour: 18.4, elapsedSeconds: 0)
        #expect(await service.simulatorPowerEvidenceSnapshot() == .unavailable)
    }
}
