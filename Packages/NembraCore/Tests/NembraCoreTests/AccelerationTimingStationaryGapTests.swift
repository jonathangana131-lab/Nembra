import Testing
@testable import NembraCore

@Suite("Acceleration stationary-gap semantics")
struct AccelerationTimingStationaryGapTests {
    private func sample(
        metersPerSecond: Double,
        seconds: Double
    ) throws -> SpeedTelemetrySample {
        try SpeedTelemetrySample(
            source: .scooterBluetooth,
            provenance: .absoluteMeasurement,
            metersPerSecond: metersPerSecond,
            receivedAtUptimeNanoseconds: UInt64(seconds * 1_000_000_000),
            receivedAtDate: .distantPast
        )
    }

    @Test("long stationary idle refreshes launch anchor instead of failing cadence")
    func longStationaryIdleCanRearmLaunchTiming() throws {
        let policy = try AccelerationRunPolicy(
            targetMetersPerSecond: 5,
            maximumSampleIntervalNanoseconds: 1_500_000_000
        )
        var evaluator = AccelerationRunEvaluator(policy: policy)

        evaluator.accept(try sample(metersPerSecond: 0, seconds: 1))
        evaluator.accept(try sample(metersPerSecond: 0.1, seconds: 10))
        #expect(evaluator.state == .armed(source: .scooterBluetooth))

        evaluator.accept(try sample(metersPerSecond: 2, seconds: 11))
        evaluator.accept(try sample(metersPerSecond: 6, seconds: 12))

        guard case let .completed(result) = evaluator.state else {
            Issue.record("Expected a completed run after the fresh stationary anchor")
            return
        }
        #expect(result.launchObservationWindow == AccelerationTimingWindow(
            earliestUptimeNanoseconds: 10_000_000_000,
            latestUptimeNanoseconds: 11_000_000_000
        ))
        #expect(result.timingEvidenceSampleCount == 3)
    }

    @Test("launch still fails when movement arrives too long after the newest stationary anchor")
    func launchGapUsesNewestStationaryAnchor() throws {
        let policy = try AccelerationRunPolicy(
            targetMetersPerSecond: 5,
            maximumSampleIntervalNanoseconds: 1_500_000_000
        )
        var evaluator = AccelerationRunEvaluator(policy: policy)

        evaluator.accept(try sample(metersPerSecond: 0, seconds: 1))
        evaluator.accept(try sample(metersPerSecond: 0.1, seconds: 10))
        evaluator.accept(try sample(metersPerSecond: 2, seconds: 12))

        #expect(evaluator.state == .invalidated(.measurementGapExceeded))
    }
}
