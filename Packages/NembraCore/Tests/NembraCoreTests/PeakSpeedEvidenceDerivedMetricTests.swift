import Foundation
import Testing
@testable import NembraCore

@Suite("Observed peak-speed derived metrics")
struct PeakSpeedEvidenceDerivedMetricTests {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private func sample(
        metersPerSecond: Double,
        uptime: UInt64 = 100
    ) throws -> SpeedTelemetrySample {
        try SpeedTelemetrySample(
            source: .scooterBluetooth,
            provenance: .absoluteMeasurement,
            metersPerSecond: metersPerSecond,
            receivedAtUptimeNanoseconds: uptime,
            receivedAtDate: epoch
        )
    }

    @Test("finite raw speed whose km/h conversion overflows is rejected without poisoning peak")
    func derivedKilometersPerHourOverflowFailsClosed() throws {
        var accumulator = PeakSpeedEvidenceAccumulator(
            policy: try PeakSpeedPolicy(source: .scooterBluetooth)
        )
        let rawSpeed = Double.greatestFiniteMagnitude / 2
        #expect(rawSpeed.isFinite)

        #expect(
            accumulator.record(try sample(
                metersPerSecond: rawSpeed,
                uptime: 200
            )) == .rejected(.nonFiniteDerivedSpeed)
        )
        #expect(accumulator.evidence == nil)

        // The rejected callback remains real ordering evidence, so an older
        // callback cannot become fresh merely because the huge value was unusable.
        #expect(
            accumulator.record(try sample(
                metersPerSecond: 1,
                uptime: 100
            )) == .rejected(.nonIncreasingTimestamp)
        )

        let validResult = accumulator.record(try sample(
            metersPerSecond: 2,
            uptime: 300
        ))
        guard case let .peakUpdated(measurement) = validResult else {
            Issue.record("Expected later valid speed to establish the observed peak")
            return
        }
        #expect(measurement.kilometersPerHour == 7.2)

        let evidence = try #require(accumulator.evidence)
        #expect(evidence.peak.metersPerSecond == 2)
        #expect(evidence.acceptedSampleCount == 1)
        #expect(evidence.qualityRejectedSampleCount == 2)
        #expect(evidence.continuity == .partialSelectedSourceEvidence)
    }

    @Test("large but representable km/h conversion remains accepted")
    func representableKilometersPerHourConversionSurvives() throws {
        var accumulator = PeakSpeedEvidenceAccumulator(
            policy: try PeakSpeedPolicy(source: .scooterBluetooth)
        )
        let rawSpeed = Double.greatestFiniteMagnitude / 4

        let result = accumulator.record(try sample(metersPerSecond: rawSpeed))
        guard case let .peakUpdated(measurement) = result else {
            Issue.record("Expected representable derived speed to remain valid peak evidence")
            return
        }
        #expect(measurement.kilometersPerHour.isFinite)
        #expect(measurement.kilometersPerHour == rawSpeed * 3.6)
    }

    @Test("ordinary observed peak exposes exact derived km/h value")
    func ordinaryConversionRemainsExact() throws {
        var accumulator = PeakSpeedEvidenceAccumulator(
            policy: try PeakSpeedPolicy(source: .scooterBluetooth)
        )

        _ = accumulator.record(try sample(metersPerSecond: 5))

        #expect(accumulator.evidence?.peak.kilometersPerHour == 18)
    }
}
