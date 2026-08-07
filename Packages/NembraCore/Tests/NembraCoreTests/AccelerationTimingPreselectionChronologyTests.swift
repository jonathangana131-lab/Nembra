import Foundation
import Testing
@testable import NembraCore

@Suite("Acceleration preselection chronology")
struct AccelerationTimingPreselectionChronologyTests {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)
    /// Synthetic software fixture only. This is deliberately not a production
    /// AOVOPRO ES80 stationary threshold.
    private let fixtureStationaryMaximumMetersPerSecond = 0.5

    private func policy() throws -> AccelerationRunPolicy {
        try AccelerationRunPolicy(
            targetMetersPerSecond: 5,
            stationaryMaximumMetersPerSecond: fixtureStationaryMaximumMetersPerSecond,
            maximumSpeedAccuracyMetersPerSecond: 1
        )
    }

    private func sample(
        source: SpeedTelemetrySource,
        uptimeNanoseconds: UInt64,
        accuracy: Double
    ) throws -> SpeedTelemetrySample {
        try SpeedTelemetrySample(
            source: source,
            provenance: .absoluteMeasurement,
            metersPerSecond: 0,
            receivedAtUptimeNanoseconds: uptimeNanoseconds,
            receivedAtDate: epoch,
            speedAccuracyMetersPerSecond: accuracy
        )
    }

    @Test("rejected same-source callback protects preselection chronology")
    func rejectedSameSourceProtectsChronology() throws {
        var evaluator = AccelerationRunEvaluator(policy: try policy())

        evaluator.accept(try sample(
            source: .gps,
            uptimeNanoseconds: 3_000_000_000,
            accuracy: 2
        ))
        #expect(evaluator.state == .waitingForStandstill)

        evaluator.accept(try sample(
            source: .gps,
            uptimeNanoseconds: 2_000_000_000,
            accuracy: 0.5
        ))
        #expect(evaluator.state == .waitingForStandstill)

        evaluator.accept(try sample(
            source: .gps,
            uptimeNanoseconds: 4_000_000_000,
            accuracy: 0.5
        ))
        #expect(evaluator.state == .armed(source: .gps))
    }

    @Test("rejected unrelated provider does not poison source selection")
    func rejectedOtherSourceDoesNotPoisonSelection() throws {
        var evaluator = AccelerationRunEvaluator(policy: try policy())

        evaluator.accept(try sample(
            source: .gps,
            uptimeNanoseconds: 3_000_000_000,
            accuracy: 2
        ))
        #expect(evaluator.state == .waitingForStandstill)

        evaluator.accept(try sample(
            source: .scooterBluetooth,
            uptimeNanoseconds: 2_000_000_000,
            accuracy: 0.5
        ))
        #expect(evaluator.state == .armed(source: .scooterBluetooth))
    }

    @Test("equal same-source callback cannot become first usable evidence")
    func equalSameSourceTimestampCannotSelect() throws {
        var evaluator = AccelerationRunEvaluator(policy: try policy())

        evaluator.accept(try sample(
            source: .gps,
            uptimeNanoseconds: 3_000_000_000,
            accuracy: 2
        ))
        evaluator.accept(try sample(
            source: .gps,
            uptimeNanoseconds: 3_000_000_000,
            accuracy: 0.5
        ))
        #expect(evaluator.state == .waitingForStandstill)

        evaluator.accept(try sample(
            source: .gps,
            uptimeNanoseconds: 3_000_000_001,
            accuracy: 0.5
        ))
        #expect(evaluator.state == .armed(source: .gps))
    }

    @Test("reset discards preselection chronology from the cancelled attempt")
    func resetDiscardsPreselectionChronology() throws {
        var evaluator = AccelerationRunEvaluator(policy: try policy())

        evaluator.accept(try sample(
            source: .gps,
            uptimeNanoseconds: 3_000_000_000,
            accuracy: 2
        ))
        evaluator.interrupt(.operatorCancelled)
        #expect(evaluator.state == .invalidated(.interruption(.operatorCancelled)))

        evaluator.reset()
        evaluator.accept(try sample(
            source: .gps,
            uptimeNanoseconds: 2_000_000_000,
            accuracy: 0.5
        ))
        #expect(evaluator.state == .armed(source: .gps))
    }
}
