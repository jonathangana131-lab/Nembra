import Foundation
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

    @Test("snapshot revalidates current provider state instead of caller's old dequeued live value")
    func snapshotRevalidatesCurrentProviderState() async throws {
        let service = SimulatedScooterService(
            initialState: SimulatedScooterService.state(for: .connectedStopped),
            commandLatencyNanoseconds: 0
        )
        let stream = await service.speedEvidenceUpdates()
        var iterator = stream.makeAsyncIterator()

        let previouslyDequeued = try #require(await iterator.next())
        guard case .live = previouslyDequeued else {
            Issue.record("Expected the initial Simulator state to begin with live speed evidence")
            return
        }

        // The consumer intentionally keeps the old `.live` event in hand while
        // source continuity advances. App authority must be rebuildable from the
        // provider's current state rather than trusting that old local value.
        await service.simulateConnectionDrop()
        await service.simulateReconnected()

        let current = await service.speedEvidenceSnapshot()
        guard case let .retained(sample) = current else {
            Issue.record("Expected current snapshot to remain retained until a fresh post-reconnect observation")
            return
        }
        #expect(sample.source == .simulatorQA)
        #expect(sample.kilometersPerHour == 0)
    }

    @Test("fresh post-reconnect observation is required before snapshot becomes live again")
    func snapshotRequiresFreshObservationAfterReconnect() async throws {
        let service = SimulatedScooterService(
            initialState: SimulatedScooterService.state(for: .connectedStopped),
            commandLatencyNanoseconds: 0
        )

        await service.simulateConnectionDrop()
        await service.simulateReconnected()

        let retained = await service.speedEvidenceSnapshot()
        guard case .retained = retained else {
            Issue.record("Reconnect without a new speed observation must not restore live authority")
            return
        }

        await service.simulateRide(speedKilometersPerHour: 0, elapsedSeconds: 0)

        let live = await service.speedEvidenceSnapshot()
        guard case let .live(sample) = live else {
            Issue.record("Expected a fresh source-attributed post-reconnect observation to restore live authority")
            return
        }
        #expect(sample.source == .simulatorQA)
        #expect(sample.kilometersPerHour == 0)
    }

    @Test("superseded refresh token cannot publish old live authority")
    func supersededConsumerRefreshFailsClosed() throws {
        var authority = SpeedEvidenceConsumerAuthority()
        let staleRefresh = authority.beginRefresh()
        let currentRefresh = authority.beginRefresh()
        let sample = try simulatorSample(uptimeNanoseconds: 10)

        let acceptedStaleRefresh = authority.commit(
            .live(sample),
            connectionIsConnected: true,
            for: staleRefresh
        )
        #expect(!acceptedStaleRefresh)
        #expect(authority.availability == .unavailable)

        let acceptedCurrentRefresh = authority.commit(
            .live(sample),
            connectionIsConnected: true,
            for: currentRefresh
        )
        #expect(acceptedCurrentRefresh)
        #expect(authority.availability == .live(sample))
    }

    @Test("connection invalidation revokes a suspended refresh before it resumes")
    func connectionInvalidationRejectsSuspendedRefresh() throws {
        var authority = SpeedEvidenceConsumerAuthority()
        let suspendedRefresh = authority.beginRefresh()
        let sample = try simulatorSample(uptimeNanoseconds: 20)

        authority.invalidate()

        let acceptedSuspendedRefresh = authority.commit(
            .live(sample),
            connectionIsConnected: true,
            for: suspendedRefresh
        )
        #expect(!acceptedSuspendedRefresh)
        #expect(authority.availability == .unavailable)
    }

    @Test("non-connected service snapshot cannot promote live provider material")
    func disconnectedSnapshotFailsClosed() throws {
        var authority = SpeedEvidenceConsumerAuthority()
        let refresh = authority.beginRefresh()
        let sample = try simulatorSample(uptimeNanoseconds: 30)

        let acceptedDisconnectedSnapshot = authority.commit(
            .live(sample),
            connectionIsConnected: false,
            for: refresh
        )
        #expect(acceptedDisconnectedSnapshot)
        #expect(authority.availability == .unavailable)
    }

    private func simulatorSample(uptimeNanoseconds: UInt64) throws -> SpeedTelemetrySample {
        try SpeedTelemetrySample(
            source: .simulatorQA,
            provenance: .absoluteMeasurement,
            metersPerSecond: 0,
            receivedAtUptimeNanoseconds: uptimeNanoseconds,
            receivedAtDate: Date(timeIntervalSince1970: 0)
        )
    }
}
