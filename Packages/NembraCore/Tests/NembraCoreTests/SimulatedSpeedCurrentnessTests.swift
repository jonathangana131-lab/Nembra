import Testing
@testable import NembraCore

@Suite("Simulated source-owned speed currentness")
struct SimulatedSpeedCurrentnessTests {
    @Test("connected fixture replays qualified synthetic live speed")
    func connectedFixtureStartsLive() async throws {
        let service = SimulatedScooterService(
            initialState: SimulatedScooterService.state(for: .connectedStopped),
            commandLatencyNanoseconds: 0
        )
        let stream = await service.speedEvidenceUpdates()
        var iterator = stream.makeAsyncIterator()
        let availability = try #require(await iterator.next())

        guard case let .live(sample) = availability else {
            Issue.record("Expected connected Simulator fixture to replay live speed evidence")
            return
        }
        #expect(sample.source == .simulatorQA)
        #expect(sample.provenance == .absoluteMeasurement)
        #expect(sample.kilometersPerHour == 0)
    }

    @Test("late subscriber after connection drop replays retained evidence")
    func lateSubscriberSeesCurrentRetainedState() async throws {
        let service = SimulatedScooterService(
            initialState: SimulatedScooterService.state(for: .connectedStopped),
            commandLatencyNanoseconds: 0
        )

        await service.simulateConnectionDrop()

        let stream = await service.speedEvidenceUpdates()
        var iterator = stream.makeAsyncIterator()
        let availability = try #require(await iterator.next())
        guard case let .retained(sample) = availability else {
            Issue.record("Expected atomic subscription replay to expose retained evidence")
            return
        }
        #expect(sample.source == .simulatorQA)
        #expect(sample.kilometersPerHour == 0)
    }

    @Test("reconnect does not revive cached stopped speed authority")
    func reconnectRequiresFreshObservation() async throws {
        var initial = SimulatedScooterService.state(for: .connectedStopped)
        initial.isLocked = false
        let service = SimulatedScooterService(
            initialState: initial,
            commandLatencyNanoseconds: 0
        )
        let stream = await service.speedEvidenceUpdates()
        var iterator = stream.makeAsyncIterator()

        guard case .live = try #require(await iterator.next()) else {
            Issue.record("Expected initial live evidence")
            return
        }

        await service.simulateConnectionDrop()
        guard case .retained = try #require(await iterator.next()) else {
            Issue.record("Connection loss must demote speed evidence")
            return
        }

        await service.simulateReconnected()
        guard case .retained = try #require(await iterator.next()) else {
            Issue.record("Reconnect without a new speed observation must stay retained")
            return
        }
        #expect((await service.snapshot()).connection == .connected)

        await #expect(throws: ScooterCommandError.commandRejected) {
            try await service.setLocked(true)
        }
        #expect((await service.snapshot()).isLocked == false)

        await service.simulateRide(speedKilometersPerHour: 0, elapsedSeconds: 0)
        let refreshed = try #require(await iterator.next())
        guard case let .live(sample) = refreshed else {
            Issue.record("Fresh post-reconnect synthetic observation should restore live evidence")
            return
        }
        #expect(sample.source == .simulatorQA)
        #expect(sample.kilometersPerHour == 0)

        try await service.setLocked(true)
        #expect((await service.snapshot()).isLocked == true)
    }

    @Test("ordinary connect keeps cached speed retained until explicit source observation")
    func ordinaryConnectDoesNotRelabelCachedSpeed() async throws {
        var initial = SimulatedScooterService.state(for: .connectedStopped)
        initial.isLocked = false
        let service = SimulatedScooterService(
            initialState: initial,
            commandLatencyNanoseconds: 0
        )
        let stream = await service.speedEvidenceUpdates()
        var iterator = stream.makeAsyncIterator()

        guard case .live = try #require(await iterator.next()) else {
            Issue.record("Expected initial live Simulator fixture evidence")
            return
        }

        await service.disconnect()
        guard case .retained = try #require(await iterator.next()) else {
            Issue.record("Disconnect must demote speed evidence")
            return
        }

        await service.connect()
        guard case let .retained(sample) = try #require(await iterator.next()) else {
            Issue.record("Transport reconnect must not relabel cached speed as fresh")
            return
        }
        #expect(sample.source == .simulatorQA)
        #expect(sample.kilometersPerHour == 0)
        #expect((await service.snapshot()).connection == .connected)

        await #expect(throws: ScooterCommandError.commandRejected) {
            try await service.setLocked(true)
        }
        #expect((await service.snapshot()).isLocked == false)

        await service.simulateRide(speedKilometersPerHour: 0, elapsedSeconds: 0)
        guard case .live = try #require(await iterator.next()) else {
            Issue.record("Only a fresh source-side observation may restore live speed")
            return
        }

        try await service.setLocked(true)
        #expect((await service.snapshot()).isLocked == true)
    }

    @Test("explicit evidence gap retires stopped authority until next sample")
    func explicitGapFailsClosed() async throws {
        var initial = SimulatedScooterService.state(for: .connectedStopped)
        initial.isLocked = false
        let service = SimulatedScooterService(
            initialState: initial,
            commandLatencyNanoseconds: 0
        )
        let stream = await service.speedEvidenceUpdates()
        var iterator = stream.makeAsyncIterator()
        _ = try #require(await iterator.next())

        await service.simulateSpeedEvidenceGap()
        guard case .retained = try #require(await iterator.next()) else {
            Issue.record("Explicit speed observation gap must retain, not keep live authority")
            return
        }

        await #expect(throws: ScooterCommandError.commandRejected) {
            try await service.setLocked(true)
        }

        await service.simulateRide(speedKilometersPerHour: 0, elapsedSeconds: 0)
        guard case .live = try #require(await iterator.next()) else {
            Issue.record("New synthetic sample after a gap should restore currentness")
            return
        }
        try await service.setLocked(true)
        #expect((await service.snapshot()).isLocked == true)
    }

    @Test("synthetic stopped evidence cannot authorize physical or deferred profiles")
    func physicalProfilesCannotBorrowSimulatorStoppedAuthority() async {
        for profile in [VehicleProfile.aovoproES80, .maxshotV1SPro] {
            var initial = SimulatedScooterService.state(for: .connectedStopped)
            initial.isLocked = false
            let service = SimulatedScooterService(
                profile: profile,
                initialState: initial,
                commandLatencyNanoseconds: 0
            )

            await #expect(throws: ScooterCommandError.commandRejected) {
                try await service.setLocked(true)
            }
            #expect((await service.snapshot()).isLocked == false)
        }
    }

    @Test("raw Simulator ride packets use synthetic source identity")
    func rawRideSampleIsNeverBluetoothEvidence() async throws {
        let service = SimulatedScooterService(
            initialState: SimulatedScooterService.state(for: .connectedStopped),
            commandLatencyNanoseconds: 0
        )
        let stream = await service.speedTelemetryUpdates()
        var iterator = stream.makeAsyncIterator()

        await service.simulateRide(speedKilometersPerHour: 12, elapsedSeconds: 1)

        let sample = try #require(await iterator.next())
        #expect(sample.source == .simulatorQA)
        #expect(sample.source != .scooterBluetooth)
        #expect(sample.provenance == .absoluteMeasurement)
        #expect(abs(sample.kilometersPerHour - 12) < 1e-9)
    }
}