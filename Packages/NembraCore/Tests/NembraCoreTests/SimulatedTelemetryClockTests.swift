import Dispatch
import Testing
@testable import NembraCore

@Suite("Simulated raw telemetry clock")
struct SimulatedTelemetryClockTests {
    @Test("speed samples use the process monotonic packet-arrival clock")
    func speedSampleUsesProcessUptimeDomain() async throws {
        let service = SimulatedScooterService(
            initialState: SimulatedScooterService.state(for: .connectedStopped),
            commandLatencyNanoseconds: 0
        )
        let stream = await service.speedTelemetryUpdates()
        var iterator = stream.makeAsyncIterator()

        let before = DispatchTime.now().uptimeNanoseconds
        // Zero simulated ride duration is intentional: elapsed ride evidence must
        // not define the raw packet-arrival timestamp used by the Dashboard.
        await service.simulateRide(speedKilometersPerHour: 12, elapsedSeconds: 0)
        let received = await iterator.next()
        let after = DispatchTime.now().uptimeNanoseconds

        let sample = try #require(received)
        #expect(sample.receivedAtUptimeNanoseconds >= before)
        #expect(sample.receivedAtUptimeNanoseconds <= after)
    }
}
