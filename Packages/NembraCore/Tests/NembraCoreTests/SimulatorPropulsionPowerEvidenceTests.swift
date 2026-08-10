import Testing
@testable import NembraCore

@Suite("Simulator source-owned propulsion power evidence")
struct SimulatorPropulsionPowerEvidenceTests {
    @Test("connected fixture replays a source-owned live power receipt")
    func connectedFixtureStartsLive() async throws {
        let service = SimulatedScooterService(
            initialState: SimulatedScooterService.state(for: .riding),
            commandLatencyNanoseconds: 0
        )

        let availability = await service.simulatorPropulsionPowerEvidenceSnapshot()
        guard case let .live(sample) = availability else {
            Issue.record("Expected connected Simulator fixture to expose live power evidence")
            return
        }

        #expect(sample.watts == 356)
        #expect(sample.receiptSequenceNumber == 1)
        #expect(sample.continuityGeneration == 1)
        #expect(sample.receivedAtUptimeNanoseconds > 0)
    }

    @Test("physical and deferred profiles cannot borrow synthetic power authority")
    func nonSimulatorProfilesRemainUnavailable() async {
        for profile in [VehicleProfile.aovoproES80, .maxshotV1SPro] {
            let service = SimulatedScooterService(
                profile: profile,
                initialState: SimulatedScooterService.state(for: .riding),
                commandLatencyNanoseconds: 0
            )
            #expect(await service.simulatorPropulsionPowerEvidenceSnapshot() == .unavailable)
        }
    }

    @Test("same numeric watts still produce distinct source receipts")
    func constantPowerObservationsAdvanceReceiptIdentity() async throws {
        let service = SimulatedScooterService(
            initialState: SimulatedScooterService.state(for: .connectedStopped),
            commandLatencyNanoseconds: 0
        )

        let first = try liveSample(await service.simulatorPropulsionPowerEvidenceSnapshot())
        #expect(first.watts == 0)

        await service.simulateRide(speedKilometersPerHour: 0, elapsedSeconds: 0)
        let second = try liveSample(await service.simulatorPropulsionPowerEvidenceSnapshot())
        await service.simulateRide(speedKilometersPerHour: 0, elapsedSeconds: 0)
        let third = try liveSample(await service.simulatorPropulsionPowerEvidenceSnapshot())

        #expect(second.watts == first.watts)
        #expect(third.watts == second.watts)
        #expect(second.continuityGeneration == first.continuityGeneration)
        #expect(third.continuityGeneration == second.continuityGeneration)
        #expect(second.receiptSequenceNumber == first.receiptSequenceNumber + 1)
        #expect(third.receiptSequenceNumber == second.receiptSequenceNumber + 1)
        #expect(second.receivedAtUptimeNanoseconds > first.receivedAtUptimeNanoseconds)
        #expect(third.receivedAtUptimeNanoseconds > second.receivedAtUptimeNanoseconds)
    }

    @Test("disconnect retains the last power receipt without manufacturing zero")
    func disconnectDemotesToRetained() async throws {
        let service = SimulatedScooterService(
            initialState: SimulatedScooterService.state(for: .riding),
            commandLatencyNanoseconds: 0
        )
        let live = try liveSample(await service.simulatorPropulsionPowerEvidenceSnapshot())

        await service.disconnect()

        guard case let .retained(retained) = await service.simulatorPropulsionPowerEvidenceSnapshot() else {
            Issue.record("Disconnect must demote the last legitimate power receipt to retained")
            return
        }
        #expect(retained == live)
        #expect(retained.watts == 356)
        #expect((await service.snapshot()).powerWatts == 356)
    }

    @Test("reconnect alone cannot revive cached power; same-watt fresh receipt can")
    func reconnectRequiresFreshPowerReceiptEvenWhenValueIsUnchanged() async throws {
        let service = SimulatedScooterService(
            initialState: SimulatedScooterService.state(for: .riding),
            commandLatencyNanoseconds: 0
        )
        let beforeDrop = try liveSample(await service.simulatorPropulsionPowerEvidenceSnapshot())
        #expect(beforeDrop.watts == 356)

        await service.simulateConnectionDrop()
        guard case let .retained(dropped) = await service.simulatorPropulsionPowerEvidenceSnapshot() else {
            Issue.record("Connection loss must retire live propulsion evidence")
            return
        }
        #expect(dropped == beforeDrop)

        await service.simulateReconnected()
        guard case let .retained(reconnected) = await service.simulatorPropulsionPowerEvidenceSnapshot() else {
            Issue.record("Reconnect transport alone must not promote cached watts")
            return
        }
        #expect(reconnected == beforeDrop)
        #expect((await service.snapshot()).connection == .connected)
        #expect((await service.snapshot()).powerWatts == 356)

        await service.simulateRide(speedKilometersPerHour: 18.4, elapsedSeconds: 0)
        let refreshed = try liveSample(await service.simulatorPropulsionPowerEvidenceSnapshot())
        #expect(refreshed.watts == beforeDrop.watts)
        #expect(refreshed.receiptSequenceNumber > beforeDrop.receiptSequenceNumber)
        #expect(refreshed.receivedAtUptimeNanoseconds > beforeDrop.receivedAtUptimeNanoseconds)
        #expect(refreshed.continuityGeneration > beforeDrop.continuityGeneration)
    }

    @Test("speed-only evidence gap leaves propulsion evidence independently live")
    func speedGapDoesNotMintOrDemotePowerEvidence() async throws {
        let service = SimulatedScooterService(
            initialState: SimulatedScooterService.state(for: .connectedStopped),
            commandLatencyNanoseconds: 0
        )
        let before = try liveSample(await service.simulatorPropulsionPowerEvidenceSnapshot())

        await service.simulateSpeedEvidenceGap()

        let after = try liveSample(await service.simulatorPropulsionPowerEvidenceSnapshot())
        #expect(after == before)
        guard case .retained = await service.speedEvidenceSnapshot() else {
            Issue.record("Fixture should prove speed currentness can retire independently of power")
            return
        }
    }

    @Test("unrelated command state changes never mint a power receipt")
    func modeCommandDoesNotMintPowerReceipt() async throws {
        let service = SimulatedScooterService(
            initialState: SimulatedScooterService.state(for: .connectedStopped),
            commandLatencyNanoseconds: 0
        )
        let before = try liveSample(await service.simulatorPropulsionPowerEvidenceSnapshot())

        try await service.setRideMode(.drive)

        let after = try liveSample(await service.simulatorPropulsionPowerEvidenceSnapshot())
        #expect(after == before)
        #expect((await service.snapshot()).rideMode == .drive)
    }

    @Test("availability stream atomically replays current state and then demotion")
    func availabilityStreamTracksSourceCurrentness() async throws {
        let service = SimulatedScooterService(
            initialState: SimulatedScooterService.state(for: .riding),
            commandLatencyNanoseconds: 0
        )
        let stream = await service.simulatorPropulsionPowerEvidenceUpdates()
        var iterator = stream.makeAsyncIterator()

        guard case .live = try #require(await iterator.next()) else {
            Issue.record("Initial stream replay must expose current live power evidence")
            return
        }

        await service.simulateConnectionDrop()
        guard case let .retained(sample) = try #require(await iterator.next()) else {
            Issue.record("Source stream must publish retained evidence after connection loss")
            return
        }
        #expect(sample.watts == 356)
    }

    private func liveSample(
        _ availability: SimulatorPropulsionPowerAvailability
    ) throws -> SimulatorPropulsionPowerSample {
        guard case let .live(sample) = availability else {
            Issue.record("Expected live Simulator propulsion power evidence")
            throw TestFailure.expectedLivePower
        }
        return sample
    }

    private enum TestFailure: Error {
        case expectedLivePower
    }
}
