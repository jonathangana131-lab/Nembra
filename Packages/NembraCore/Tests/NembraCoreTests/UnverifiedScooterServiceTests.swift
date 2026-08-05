import Testing
@testable import NembraCore

@Suite("Hardware-gated production scooter service")
struct UnverifiedScooterServiceTests {
    @Test("initial state contains no fabricated telemetry")
    func initialStateIsTruthful() {
        let state = UnverifiedScooterService.initialState()
        #expect(state.connection == .disconnected)
        #expect(state.connectionIssue == .unsupportedConfiguration)
        #expect(state.batteryPercent == nil)
        #expect(state.speedKilometersPerHour == nil)
        #expect(state.odometerKilometers == nil)
        #expect(state.rideMode == nil)
    }

    @Test("connect cannot fabricate success before Bluetooth identity is verified")
    func connectStaysBlocked() async {
        let service = UnverifiedScooterService()
        await service.connect()
        let state = await service.snapshot()
        #expect(state.connection == .disconnected)
        #expect(state.connectionIssue == .unsupportedConfiguration)
    }

    @Test("unverified service emits no fake raw speed samples")
    func rawTelemetryCompletesEmpty() async {
        let service = UnverifiedScooterService()
        let stream = await service.speedTelemetryUpdates()
        var iterator = stream.makeAsyncIterator()
        #expect(await iterator.next() == nil)
    }

    @Test("commands remain unavailable while hardware protocol is unverified")
    func commandsStayUnavailable() async {
        let service = UnverifiedScooterService()
        await #expect(throws: ScooterCommandError.disconnected) {
            try await service.setHeadlight(true)
        }
        #expect((await service.snapshot()).isHeadlightOn == nil)
    }
}
