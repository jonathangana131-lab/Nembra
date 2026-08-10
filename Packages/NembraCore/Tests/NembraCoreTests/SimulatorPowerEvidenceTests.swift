import Foundation
import Testing
@testable import NembraCore

@Suite("Simulator power evidence source authority")
struct SimulatorPowerEvidenceTests {
    @Test("connected Simulator fixture exposes immutable source-owned live power")
    func connectedFixtureStartsWithLivePowerEvidence() async {
        let service = SimulatedScooterService(
            initialState: SimulatedScooterService.state(for: .riding),
            commandLatencyNanoseconds: 0
        )

        guard case let .live(sample) = await service.powerEvidenceSnapshot() else {
            Issue.record("Expected connected Simulator fixture to expose live power evidence")
            return
        }

        #expect(sample.source == .simulatorQA)
        #expect(sample.provenance == .absoluteMeasurement)
        #expect(sample.watts == 356)
        #expect(sample.receivedAtUptimeNanoseconds > 0)
    }

    @Test("disconnected cached watts are not promoted to live evidence")
    func disconnectedCachedPowerStartsUnavailable() async {
        let service = SimulatedScooterService(
            initialState: SimulatedScooterService.state(for: .scooterUnavailable),
            commandLatencyNanoseconds: 0
        )

        #expect(await service.powerEvidenceSnapshot() == .unavailable)
    }

    @Test("equal-watt synthetic source events keep distinct receipt clocks")
    func equalWattSourceEventsMintDistinctReceipts() async {
        let service = SimulatedScooterService(
            initialState: SimulatedScooterService.state(for: .riding),
            commandLatencyNanoseconds: 0
        )

        guard case let .live(initial) = await service.powerEvidenceSnapshot() else {
            Issue.record("Expected initial live power evidence")
            return
        }

        await service.simulateRide(speedKilometersPerHour: 18.4, elapsedSeconds: 1)
        guard case let .live(first) = await service.powerEvidenceSnapshot() else {
            Issue.record("Expected first synthetic ride receipt")
            return
        }

        await service.simulateRide(speedKilometersPerHour: 18.4, elapsedSeconds: 1)
        guard case let .live(second) = await service.powerEvidenceSnapshot() else {
            Issue.record("Expected second synthetic ride receipt")
            return
        }

        #expect(initial.watts == first.watts)
        #expect(first.watts == second.watts)
        #expect(first.receivedAtUptimeNanoseconds > initial.receivedAtUptimeNanoseconds)
        #expect(second.receivedAtUptimeNanoseconds > first.receivedAtUptimeNanoseconds)
    }

    @Test("mode-only command cannot refresh a power receipt")
    func rideModeCommandDoesNotMintPowerEvidence() async throws {
        let service = SimulatedScooterService(
            initialState: SimulatedScooterService.state(for: .riding),
            commandLatencyNanoseconds: 0
        )

        guard case let .live(before) = await service.powerEvidenceSnapshot() else {
            Issue.record("Expected initial live power evidence")
            return
        }

        try await service.setRideMode(.eco)

        guard case let .live(after) = await service.powerEvidenceSnapshot() else {
            Issue.record("Mode command must not demote or replace existing source evidence")
            return
        }
        #expect(after == before)
    }

    @Test("disconnect retains exact receipt and reconnect alone does not refresh it")
    func reconnectNeedsANewPowerSourceEvent() async {
        let service = SimulatedScooterService(
            initialState: SimulatedScooterService.state(for: .riding),
            commandLatencyNanoseconds: 0
        )

        guard case let .live(initial) = await service.powerEvidenceSnapshot() else {
            Issue.record("Expected initial live power evidence")
            return
        }

        await service.disconnect()
        #expect(await service.powerEvidenceSnapshot() == .retained(initial))

        await service.simulateReconnected()
        #expect(await service.powerEvidenceSnapshot() == .retained(initial))

        await service.simulateRide(speedKilometersPerHour: 18.4, elapsedSeconds: 1)
        guard case let .live(refreshed) = await service.powerEvidenceSnapshot() else {
            Issue.record("A new Simulator power source event should restore live evidence")
            return
        }
        #expect(refreshed.watts == initial.watts)
        #expect(refreshed.receivedAtUptimeNanoseconds > initial.receivedAtUptimeNanoseconds)
    }

    @Test("late subscriber receives retained state without rewriting receipt identity")
    func lateSubscriberGetsCurrentRetainedReceipt() async {
        let service = SimulatedScooterService(
            initialState: SimulatedScooterService.state(for: .riding),
            commandLatencyNanoseconds: 0
        )

        guard case let .live(initial) = await service.powerEvidenceSnapshot() else {
            Issue.record("Expected initial live power evidence")
            return
        }
        await service.disconnect()

        let stream = await service.powerEvidenceUpdates()
        var iterator = stream.makeAsyncIterator()
        let replay = await iterator.next()
        #expect(replay == .retained(initial))
    }

    @Test("power sample rejects impossible numeric values")
    func powerSampleValidatesNumericDomain() {
        func sample(_ watts: Double) -> PowerTelemetrySample? {
            PowerTelemetrySample(
                source: .simulatorQA,
                provenance: .absoluteMeasurement,
                watts: watts,
                receivedAtUptimeNanoseconds: 1,
                receivedAtDate: .distantPast
            )
        }

        #expect(sample(-1) == nil)
        #expect(sample(.nan) == nil)
        #expect(sample(.infinity) == nil)
        #expect(sample(0)?.watts == 0)
        #expect(sample(356)?.watts == 356)
    }
}
