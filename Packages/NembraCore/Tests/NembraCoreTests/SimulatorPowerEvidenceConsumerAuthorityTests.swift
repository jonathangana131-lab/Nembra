import Testing
@testable import NembraCore

@Suite("Simulator power app-session custody")
struct SimulatorPowerEvidenceConsumerAuthorityTests {
    @Test("transport veto demotes exact live receipt to retained")
    func transportVetoKeepsExactLastKnownReceipt() async {
        let service = SimulatedScooterService(
            initialState: SimulatedScooterService.state(for: .riding),
            commandLatencyNanoseconds: 0
        )
        let source = await service.simulatorPowerEvidenceSnapshot()
        #expect(source.currentness == .live)
        guard let sourceObservation = source.observation else {
            Issue.record("Expected source-issued live power receipt")
            return
        }

        var authority = SimulatorPowerEvidenceConsumerAuthority()
        authority.applySource(source, connectionIsConnected: true)
        #expect(authority.projection.currentness == .live)
        #expect(authority.projection.observation == sourceObservation)

        authority.transportBecameUnavailable()
        #expect(authority.projection.currentness == .retained)
        #expect(authority.projection.observation == sourceObservation)
    }

    @Test("disconnected transport cannot expose sealed source live as app live")
    func disconnectedTransportDemotesSourceLive() async {
        let service = SimulatedScooterService(
            initialState: SimulatedScooterService.state(for: .riding),
            commandLatencyNanoseconds: 0
        )
        let source = await service.simulatorPowerEvidenceSnapshot()
        guard let sourceObservation = source.observation else {
            Issue.record("Expected source-issued live power receipt")
            return
        }

        var authority = SimulatorPowerEvidenceConsumerAuthority()
        authority.applySource(source, connectionIsConnected: false)

        #expect(authority.projection.currentness == .retained)
        #expect(authority.projection.observation == sourceObservation)
    }

    @Test("reconnect keeps retained until a new source receipt exists")
    func reconnectCannotPromoteRetainedPower() async {
        let service = SimulatedScooterService(
            initialState: SimulatedScooterService.state(for: .riding),
            commandLatencyNanoseconds: 0
        )
        let initial = await service.simulatorPowerEvidenceSnapshot()
        guard let initialObservation = initial.observation else {
            Issue.record("Expected initial source receipt")
            return
        }

        await service.disconnect()
        await service.connect()
        let reconnected = await service.simulatorPowerEvidenceSnapshot()
        #expect(reconnected.currentness == .retained)
        #expect(reconnected.observation == initialObservation)

        var authority = SimulatorPowerEvidenceConsumerAuthority()
        authority.applySource(reconnected, connectionIsConnected: true)
        #expect(authority.projection.currentness == .retained)
        #expect(authority.projection.observation == initialObservation)

        await service.simulateRide(speedKilometersPerHour: 18.4, elapsedSeconds: 0)
        let refreshed = await service.simulatorPowerEvidenceSnapshot()
        #expect(refreshed.currentness == .live)
        guard let refreshedObservation = refreshed.observation else {
            Issue.record("Expected fresh source live receipt")
            return
        }
        #expect(refreshedObservation.watts == initialObservation.watts)
        #expect(refreshedObservation.receiptSequenceNumber > initialObservation.receiptSequenceNumber)
        #expect(refreshedObservation.continuityGeneration > initialObservation.continuityGeneration)

        authority.applySource(refreshed, connectionIsConnected: true)
        #expect(authority.projection.currentness == .live)
        #expect(authority.projection.observation == refreshedObservation)
    }

    @Test("source retained remains byte-identical through app projection")
    func sourceRetainedIdentityIsPreserved() async {
        let service = SimulatedScooterService(
            initialState: SimulatedScooterService.state(for: .riding),
            commandLatencyNanoseconds: 0
        )
        let live = await service.simulatorPowerEvidenceSnapshot()
        guard let liveObservation = live.observation else {
            Issue.record("Expected initial source receipt")
            return
        }
        await service.disconnect()
        let retained = await service.simulatorPowerEvidenceSnapshot()
        #expect(retained.currentness == .retained)
        #expect(retained.observation == liveObservation)

        var authority = SimulatorPowerEvidenceConsumerAuthority()
        authority.applySource(retained, connectionIsConnected: false)
        #expect(authority.projection.currentness == .retained)
        #expect(authority.projection.observation == liveObservation)
    }

    @Test("source termination fails completely closed")
    func sourceTerminationIsUnavailable() async {
        let service = SimulatedScooterService(
            initialState: SimulatedScooterService.state(for: .riding),
            commandLatencyNanoseconds: 0
        )
        let source = await service.simulatorPowerEvidenceSnapshot()

        var authority = SimulatorPowerEvidenceConsumerAuthority()
        authority.applySource(source, connectionIsConnected: true)
        #expect(authority.projection.currentness == .live)

        authority.sourceBecameUnavailable()
        #expect(authority.projection == .unavailable)
    }

    @Test("unavailable source can never produce positive app authority")
    func unavailableSourceStaysUnavailable() {
        var authority = SimulatorPowerEvidenceConsumerAuthority()
        authority.applySource(.unavailable, connectionIsConnected: true)
        #expect(authority.projection == .unavailable)
        authority.applySource(.unavailable, connectionIsConnected: false)
        #expect(authority.projection == .unavailable)
    }
}
