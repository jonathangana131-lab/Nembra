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
}
