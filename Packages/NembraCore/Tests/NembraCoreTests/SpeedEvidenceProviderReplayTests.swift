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

    @Test("source-current snapshot supersedes an already delivered obsolete live value")
    func currentSnapshotSupersedesAlreadyDeliveredLiveValue() async throws {
        let service = SimulatedScooterService(
            initialState: SimulatedScooterService.state(for: .connectedStopped),
            commandLatencyNanoseconds: 0
        )
        let stream = await service.speedEvidenceUpdates()
        var iterator = stream.makeAsyncIterator()

        // This value has already crossed the AsyncStream boundary, so newest-only
        // buffering cannot revoke the caller's copy after a later source change.
        let delivered = try #require(await iterator.next())
        guard case let .live(deliveredSample) = delivered else {
            Issue.record("Expected the connected Simulator fixture to begin live")
            return
        }
        #expect(deliveredSample.kilometersPerHour == 0)

        await service.simulateConnectionDrop()
        await service.simulateReconnected()

        // A fresh source snapshot is the authority when a consumer combines
        // independent transport/evidence streams. The already-delivered `.live`
        // value above must not become current merely because the vehicle later
        // reports connected again.
        let current = await service.speedEvidenceSnapshot()
        guard case let .retained(retainedSample) = current else {
            Issue.record("Expected reconnect without a fresh observation to remain retained")
            return
        }
        #expect(retainedSample == deliveredSample)

        await service.simulateRide(speedKilometersPerHour: 4, elapsedSeconds: 1)
        let refreshed = await service.speedEvidenceSnapshot()
        guard case let .live(refreshedSample) = refreshed else {
            Issue.record("Expected a new source observation to restore live currentness")
            return
        }
        #expect(refreshedSample.source == .simulatorQA)
        #expect(refreshedSample.kilometersPerHour == 4)
    }
}
