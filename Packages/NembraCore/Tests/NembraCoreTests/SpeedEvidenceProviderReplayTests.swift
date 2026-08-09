import Testing
@testable import NembraCore

@Suite("Speed evidence provider replay")
struct SpeedEvidenceProviderReplayTests {
    @Test("slow subscriber receives newest retained state instead of obsolete live backlog")
    func slowSubscriberCoalescesObsoleteLiveState() async throws {
        let service = SimulatedScooterService(
            initialState: SimulatedScooterService.state(for: .connectedStopped),
            commandLatencyNanoseconds: 0
        )
        let stream = await service.speedEvidenceUpdates()
        var iterator = stream.makeAsyncIterator()

        // Do not consume the initial replay yet. A state-style availability
        // stream must replace that obsolete queued `.live` value when source
        // continuity is lost before this slow consumer catches up.
        await service.simulateConnectionDrop()
        await service.simulateReconnected()

        let availability = try #require(await iterator.next())
        guard case let .retained(sample) = availability else {
            Issue.record("Expected newest-only availability buffering to suppress obsolete live backlog")
            return
        }
        #expect(sample.source == .simulatorQA)
        #expect(sample.kilometersPerHour == 0)
    }

    @Test("coherent snapshot cannot pair reconnected transport with obsolete live speed")
    func coherentSnapshotCoalescesCrossStreamResurrection() async throws {
        let service = SimulatedScooterService(
            initialState: SimulatedScooterService.state(for: .connectedStopped),
            commandLatencyNanoseconds: 0
        )
        let stream = await service.vehicleSpeedEvidenceUpdates()
        var iterator = stream.makeAsyncIterator()

        // Leave the initial connected/live pair queued, then advance the source
        // through a connection gap and reconnect with no new speed observation.
        // One newest-only coherent stream must replace the old pair as a unit;
        // there is no independent state task that can race ahead of currentness.
        await service.simulateConnectionDrop()
        await service.simulateReconnected()

        let snapshot = try #require(await iterator.next())
        #expect(snapshot.state.connection == .connected)
        guard case let .retained(sample) = snapshot.speedEvidenceAvailability else {
            Issue.record("Reconnect without a fresh source observation must be connected + retained as one pair")
            return
        }
        #expect(sample.source == .simulatorQA)
        #expect(sample.kilometersPerHour == 0)
    }

    @Test("coherent snapshot advances state and live speed together on fresh observation")
    func coherentSnapshotRestoresLiveOnlyWithFreshObservation() async throws {
        let service = SimulatedScooterService(
            initialState: SimulatedScooterService.state(for: .connectedStopped),
            commandLatencyNanoseconds: 0
        )
        let stream = await service.vehicleSpeedEvidenceUpdates()
        var iterator = stream.makeAsyncIterator()

        let initial = try #require(await iterator.next())
        #expect(initial.state.connection == .connected)
        guard case .live = initial.speedEvidenceAvailability else {
            Issue.record("Expected initial coherent connected/live Simulator fixture")
            return
        }

        await service.simulateConnectionDrop()
        let dropped = try #require(await iterator.next())
        #expect(dropped.state.connection == .reconnecting)
        guard case .retained = dropped.speedEvidenceAvailability else {
            Issue.record("Connection drop must publish a coherent retained pair")
            return
        }

        await service.simulateReconnected()
        let reconnected = try #require(await iterator.next())
        #expect(reconnected.state.connection == .connected)
        guard case .retained = reconnected.speedEvidenceAvailability else {
            Issue.record("Reconnect alone must remain coherent retained state")
            return
        }

        await service.simulateRide(speedKilometersPerHour: 7, elapsedSeconds: 0)
        let refreshed = try #require(await iterator.next())
        #expect(refreshed.state.connection == .connected)
        #expect(refreshed.state.speedKilometersPerHour == 7)
        guard case let .live(sample) = refreshed.speedEvidenceAvailability else {
            Issue.record("Fresh source event should advance the coherent pair to live")
            return
        }
        #expect(abs(sample.kilometersPerHour - 7) < 1e-9)
    }
}