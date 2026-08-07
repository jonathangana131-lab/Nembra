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

    @Test("commands report unverified configuration rather than a fake disconnect")
    func commandsStayUnavailableForTruthfulReason() async {
        let service = UnverifiedScooterService()

        await #expect(throws: ScooterCommandError.unsupportedConfiguration) {
            try await service.setHeadlight(true)
        }
        await #expect(throws: ScooterCommandError.unsupportedConfiguration) {
            try await service.setLocked(true)
        }
        await #expect(throws: ScooterCommandError.unsupportedConfiguration) {
            try await service.setCruise(true)
        }
        await #expect(throws: ScooterCommandError.unsupportedConfiguration) {
            try await service.setRideMode(.sport)
        }
        await #expect(throws: ScooterCommandError.unsupportedConfiguration) {
            try await service.setStartMode(.zeroStart)
        }
        await #expect(throws: ScooterCommandError.unsupportedConfiguration) {
            try await service.setSpeedLimit(kilometersPerHour: 20, slot: .limit1)
        }

        let state = await service.snapshot()
        #expect(state.isHeadlightOn == nil)
        #expect(state.isLocked == nil)
        #expect(state.isCruiseEnabled == nil)
        #expect(state.rideMode == nil)
        #expect(state.startMode == nil)
        #expect(state.speedLimitsKilometersPerHour.isEmpty)
    }
}
