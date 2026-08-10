import Testing
@testable import NembraCore

@Suite("Simulator power consumer connection veto")
struct SimulatorPowerEvidenceConsumerAuthorityTests {
    @Test("non-connected transport revokes live before retained source replay")
    func disconnectRevokesLiveThenAcceptsExactRetainedSourceValue() async {
        let service = SimulatedScooterService(
            initialState: SimulatedScooterService.state(for: .riding),
            commandLatencyNanoseconds: 0
        )
        let live = await service.simulatorPowerEvidenceSnapshot()
        #expect(live.currentness == .live)
        #expect(live.observation != nil)

        var authority = SimulatorPowerEvidenceConsumerAuthority()
        #expect(authority.commit(live, connectionIsConnected: true))
        #expect(authority.availability == live)

        // This is the synchronous Store-side action that must happen before a
        // disconnected/reconnecting aggregate VehicleState is published.
        authority.revokeLiveForNonConnectedTransport()
        #expect(authority.availability == .unavailable)

        await service.disconnect()
        let retained = await service.simulatorPowerEvidenceSnapshot()
        #expect(retained.currentness == .retained)
        #expect(retained.observation == live.observation)
        #expect(authority.commit(retained, connectionIsConnected: false))
        #expect(authority.availability == retained)
    }

    @Test("stale live provider value cannot survive disconnected aggregate state")
    func disconnectedTransportRejectsStaleLiveCandidate() async {
        let service = SimulatedScooterService(
            initialState: SimulatedScooterService.state(for: .riding),
            commandLatencyNanoseconds: 0
        )
        let live = await service.simulatorPowerEvidenceSnapshot()
        #expect(live.currentness == .live)

        var authority = SimulatorPowerEvidenceConsumerAuthority()
        #expect(authority.commit(live, connectionIsConnected: false) == false)
        #expect(authority.availability == .unavailable)
    }

    @Test("reconnect cannot promote retained watts without a new source receipt")
    func reconnectKeepsRetainedUntilFreshSourceObservation() async {
        let service = SimulatedScooterService(
            initialState: SimulatedScooterService.state(for: .riding),
            commandLatencyNanoseconds: 0
        )
        let initialLive = await service.simulatorPowerEvidenceSnapshot()
        guard let initialReceipt = initialLive.observation else {
            Issue.record("Expected initial Simulator power receipt")
            return
        }

        await service.disconnect()
        await service.connect()
        let afterReconnect = await service.simulatorPowerEvidenceSnapshot()
        #expect(afterReconnect.currentness == .retained)
        #expect(afterReconnect.observation == initialReceipt)

        var authority = SimulatorPowerEvidenceConsumerAuthority()
        #expect(authority.commit(afterReconnect, connectionIsConnected: true))
        #expect(authority.availability.currentness == .retained)
        #expect(authority.availability.observation == initialReceipt)

        await service.simulateRide(speedKilometersPerHour: 18.4, elapsedSeconds: 0)
        let refreshed = await service.simulatorPowerEvidenceSnapshot()
        #expect(refreshed.currentness == .live)
        #expect(refreshed.observation?.receiptSequenceNumber != initialReceipt.receiptSequenceNumber)
        #expect(authority.commit(refreshed, connectionIsConnected: true))
        #expect(authority.availability == refreshed)
    }

    @Test("invalidation never manufactures retained or live authority")
    func invalidationIsNegativeOnly() async {
        let service = SimulatedScooterService(
            initialState: SimulatedScooterService.state(for: .riding),
            commandLatencyNanoseconds: 0
        )
        let live = await service.simulatorPowerEvidenceSnapshot()

        var authority = SimulatorPowerEvidenceConsumerAuthority()
        #expect(authority.commit(live, connectionIsConnected: true))
        authority.invalidate()
        #expect(authority.availability == .unavailable)
    }
}
