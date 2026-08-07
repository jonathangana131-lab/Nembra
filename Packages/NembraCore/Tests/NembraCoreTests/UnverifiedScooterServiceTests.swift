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

    @Test("connect preserves the existing unavailable state timestamp")
    func connectStaysBlocked() async {
        let service = UnverifiedScooterService()
        let before = await service.snapshot()

        await service.connect()

        let after = await service.snapshot()
        #expect(after == before)
        #expect(after.connection == .disconnected)
        #expect(after.connectionIssue == .unsupportedConfiguration)
    }

    @Test("disconnect preserves the existing unavailable state timestamp")
    func disconnectPreservesState() async {
        let service = UnverifiedScooterService()
        let before = await service.snapshot()

        await service.disconnect()

        #expect(await service.snapshot() == before)
    }

    @Test("unverified service emits no fake raw speed samples")
    func rawTelemetryCompletesEmpty() async {
        let service = UnverifiedScooterService()
        let stream = await service.speedTelemetryUpdates()
        var iterator = stream.makeAsyncIterator()
        #expect(await iterator.next() == nil)
    }

    @Test("commands report unverified configuration without mutating vehicle state")
    func commandsStayUnavailableForTruthfulReason() async {
        let service = UnverifiedScooterService()
        let before = await service.snapshot()

        await #expect(throws: ScooterCommandError.unverifiedConfiguration) {
            try await service.setHeadlight(true)
        }
        await #expect(throws: ScooterCommandError.unverifiedConfiguration) {
            try await service.setLocked(true)
        }
        await #expect(throws: ScooterCommandError.unverifiedConfiguration) {
            try await service.setCruise(true)
        }
        await #expect(throws: ScooterCommandError.unverifiedConfiguration) {
            try await service.setRideMode(.sport)
        }
        await #expect(throws: ScooterCommandError.unverifiedConfiguration) {
            try await service.setStartMode(.zeroStart)
        }
        await #expect(throws: ScooterCommandError.unverifiedConfiguration) {
            try await service.setSpeedLimit(kilometersPerHour: 20, slot: .limit1)
        }

        #expect(await service.snapshot() == before)
    }
}
