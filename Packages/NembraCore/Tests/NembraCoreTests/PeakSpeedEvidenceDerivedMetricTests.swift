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

    @Test("finite raw peak remains evidence when km/h convenience conversion overflows")
    func derivedKilometersPerHourOverflowFailsClosed() throws {
        var accumulator = PeakSpeedEvidenceAccumulator(
            policy: try PeakSpeedPolicy(source: .scooterBluetooth)
        )
        let rawSpeed = Double.greatestFiniteMagnitude / 2
        #expect(rawSpeed.isFinite)

        _ = accumulator.record(try sample(metersPerSecond: rawSpeed))

        let evidence = try #require(accumulator.evidence)
        #expect(evidence.peak.metersPerSecond == rawSpeed)
        #expect(evidence.peak.kilometersPerHour == nil)
    }

    @Test("large but representable km/h conversion remains available")
    func representableKilometersPerHourConversionSurvives() throws {
        var accumulator = PeakSpeedEvidenceAccumulator(
            policy: try PeakSpeedPolicy(source: .scooterBluetooth)
        )
        let rawSpeed = Double.greatestFiniteMagnitude / 4

        _ = accumulator.record(try sample(metersPerSecond: rawSpeed))

        let evidence = try #require(accumulator.evidence)
        let converted = try #require(evidence.peak.kilometersPerHour)
        #expect(converted.isFinite)
        #expect(converted == rawSpeed * 3.6)
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
