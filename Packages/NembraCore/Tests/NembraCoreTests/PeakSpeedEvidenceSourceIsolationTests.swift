import Foundation
import Testing
@testable import NembraCore

@Suite("Observed peak-speed source isolation")
struct PeakSpeedEvidenceSourceIsolationTests {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private func sample(
        source: SpeedTelemetrySource,
        metersPerSecond: Double,
        uptime: UInt64,
        accuracy: Double? = nil
    ) throws -> SpeedTelemetrySample {
        try SpeedTelemetrySample(
            source: source,
            provenance: .absoluteMeasurement,
            metersPerSecond: metersPerSecond,
            receivedAtUptimeNanoseconds: uptime,
            receivedAtDate: epoch,
            speedAccuracyMetersPerSecond: accuracy
        )
    }

    @Test("newer foreign-source traffic cannot poison selected-source ordering")
    func foreignSourceDoesNotAdvanceSelectedSourceClock() throws {
        var accumulator = PeakSpeedEvidenceAccumulator(
            policy: try PeakSpeedPolicy(source: .scooterBluetooth)
        )

        #expect(
            accumulator.record(try sample(
                source: .gps,
                metersPerSecond: 20,
                uptime: 500,
                accuracy: 0.2
            )) == .rejected(.sourceMismatch)
        )

        let selectedResult = accumulator.record(try sample(
            source: .scooterBluetooth,
            metersPerSecond: 4,
            uptime: 100
        ))

        guard case let .peakUpdated(measurement) = selectedResult else {
            Issue.record("Expected selected-source evidence to remain fresh after foreign traffic")
            return
        }
        #expect(measurement.source == .scooterBluetooth)
        #expect(measurement.receivedAtUptimeNanoseconds == 100)

        let evidence = try #require(accumulator.evidence)
        #expect(evidence.peak.metersPerSecond == 4)
        #expect(evidence.acceptedSampleCount == 1)
        #expect(evidence.qualityRejectedSampleCount == 0)
        #expect(evidence.continuity == .noRecordedSelectedSourceEvidenceLoss)
    }

    @Test("known gap before first accepted peak remains visible in later evidence")
    func interruptionBeforePeakMarksLaterCoveragePartial() throws {
        var accumulator = PeakSpeedEvidenceAccumulator(
            policy: try PeakSpeedPolicy(source: .scooterBluetooth)
        )

        accumulator.recordInterruption(.applicationLifecycleInterrupted)
        #expect(accumulator.evidence == nil)

        _ = accumulator.record(try sample(
            source: .scooterBluetooth,
            metersPerSecond: 5,
            uptime: 100
        ))

        let evidence = try #require(accumulator.evidence)
        #expect(evidence.peak.metersPerSecond == 5)
        #expect(evidence.knownInterruptionCount == 1)
        #expect(evidence.continuity == .partialSelectedSourceEvidence)
    }
}
