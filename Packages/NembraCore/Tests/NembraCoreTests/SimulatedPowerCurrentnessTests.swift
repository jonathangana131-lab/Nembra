import Testing
@testable import NembraCore

@Suite("Simulated source-owned power currentness")
struct SimulatedPowerCurrentnessTests {
    @Test("connected Simulator fixture replays source-owned live power")
    func connectedFixtureStartsLive() async throws {
        let service = SimulatedScooterService(
            initialState: SimulatedScooterService.state(for: .riding),
            commandLatencyNanoseconds: 0
        )
        let stream = await service.simulatorPowerEvidenceUpdates()
        var iterator = stream.makeAsyncIterator()
        let availability = try #require(await iterator.next())

        guard case let .live(sample) = availability else {
            Issue.record("Expected connected Simulator fixture to replay live power evidence")
            return
        }
        #expect(sample.watts == 356)
        #expect(sample.receivedAtUptimeNanoseconds > 0)
    }

    @Test("drop and reconnect cannot revive cached power without a new power receipt")
    func reconnectRequiresFreshPowerObservation() async throws {
        let service = SimulatedScooterService(
            initialState: SimulatedScooterService.state(for: .connectedStopped),
            commandLatencyNanoseconds: 0
        )
        let stream = await service.simulatorPowerEvidenceUpdates()
        var iterator = stream.makeAsyncIterator()

        let initialAvailability = try #require(await iterator.next())
        guard case let .live(initial) = initialAvailability else {
            Issue.record("Expected initial live power evidence")
            return
        }
        #expect(initial.watts == 0)

        await service.simulateConnectionDrop()
        let droppedAvailability = try #require(await iterator.next())
        guard case let .retained(dropped) = droppedAvailability else {
            Issue.record("Connection loss must demote power evidence")
            return
        }
        #expect(dropped == initial)

        await service.simulateReconnected()
        let afterReconnect = await service.simulatorPowerEvidenceSnapshot()
        guard case let .retained(reconnected) = afterReconnect else {
            Issue.record("Reconnect without a new power observation must remain retained")
            return
        }
        #expect(reconnected == initial)
        #expect((await service.snapshot()).connection == .connected)
        #expect((await service.snapshot()).powerWatts == 0)

        // A genuine source observation may have the same numeric value. Receipt
        // identity and the power-owned monotonic clock, not value inequality,
        // distinguish it from cached pre-gap power.
        await service.simulateRide(speedKilometersPerHour: 0, elapsedSeconds: 0)
        let refreshedAvailability = try #require(await iterator.next())
        guard case let .live(refreshed) = refreshedAvailability else {
            Issue.record("Fresh same-valued power observation should restore live evidence")
            return
        }
        #expect(refreshed.watts == initial.watts)
        #expect(refreshed.receiptID != initial.receiptID)
        #expect(refreshed.receivedAtUptimeNanoseconds > initial.receivedAtUptimeNanoseconds)
    }

    @Test("power gap is independent from speed currentness")
    func powerGapDoesNotBorrowOrDemoteSpeed() async throws {
        let service = SimulatedScooterService(
            initialState: SimulatedScooterService.state(for: .riding),
            commandLatencyNanoseconds: 0
        )

        guard case .live = await service.speedEvidenceSnapshot() else {
            Issue.record("Expected initial live speed evidence")
            return
        }
        guard case .live = await service.simulatorPowerEvidenceSnapshot() else {
            Issue.record("Expected initial live power evidence")
            return
        }

        await service.simulatePowerEvidenceGap()

        guard case .retained = await service.simulatorPowerEvidenceSnapshot() else {
            Issue.record("Explicit power gap must demote power evidence")
            return
        }
        guard case .live = await service.speedEvidenceSnapshot() else {
            Issue.record("Power gap must not use or alter speed currentness")
            return
        }
    }

    @Test("physical and deferred profiles cannot borrow synthetic power authority")
    func physicalProfilesCannotBorrowSimulatorPowerAuthority() async {
        for profile in [VehicleProfile.aovoproES80, .maxshotV1SPro] {
            let service = SimulatedScooterService(
                profile: profile,
                initialState: SimulatedScooterService.state(for: .riding),
                commandLatencyNanoseconds: 0
            )

            #expect(await service.simulatorPowerEvidenceSnapshot() == .unavailable)
            await service.simulateRide(speedKilometersPerHour: 12, elapsedSeconds: 1)
            #expect(await service.simulatorPowerEvidenceSnapshot() == .unavailable)
        }
    }

    @Test("unrelated command publication cannot mint a new power receipt")
    func commandStateChangesDoNotRefreshPowerCurrentness() async throws {
        let service = SimulatedScooterService(
            initialState: SimulatedScooterService.state(for: .connectedStopped),
            commandLatencyNanoseconds: 0
        )

        let beforeAvailability = await service.simulatorPowerEvidenceSnapshot()
        guard case let .live(before) = beforeAvailability else {
            Issue.record("Expected initial live power evidence")
            return
        }

        try await service.setHeadlight(true)

        let afterAvailability = await service.simulatorPowerEvidenceSnapshot()
        guard case let .live(after) = afterAvailability else {
            Issue.record("Unrelated command should not remove current power evidence")
            return
        }
        #expect(after == before)
        #expect((await service.snapshot()).isHeadlightOn == true)
    }
}
