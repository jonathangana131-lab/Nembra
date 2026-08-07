import Foundation
import Testing

@testable import NembraCore

@Suite("Ride speed evidence interruption deduplication")
struct RideSpeedEvidenceSessionInterruptionDeduplicationTests {
    private let sessionID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let epoch = Date(timeIntervalSinceReferenceDate: 10_000)

    private func sample(
        source: SpeedTelemetrySource = .scooterBluetooth,
        metersPerSecond: Double = 5,
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

    @Test("repeated notifications during one outage count as one logical gap")
    func repeatedPendingInterruptionsAreIdempotent() throws {
        var session = RideSpeedEvidenceSessionAccumulator(
            sessionID: sessionID,
            peakPolicy: try PeakSpeedPolicy(source: .scooterBluetooth)
        )

        _ = session.record(try sample(uptime: 100))
        _ = session.record(try sample(metersPerSecond: 6, uptime: 200))

        session.recordInterruption(.selectedSourceUnavailable)
        session.recordInterruption(.selectedSourceUnavailable)
        session.recordInterruption(.applicationLifecycleInterrupted)

        let pending = session.snapshot
        #expect(pending.peakEvidence?.peakEvidence.knownInterruptionCount == 1)
        #expect(pending.telemetryBenchmark.knownObservationInterruptionCount == 1)
        #expect(pending.peakEvidence?.peakEvidence.continuity == .partialSelectedSourceEvidence)

        _ = session.record(try sample(metersPerSecond: 7, uptime: 300))
        session.recordInterruption(.selectedSourceUnavailable)
        session.recordInterruption(.selectedSourceUnavailable)

        let secondGap = session.snapshot
        #expect(secondGap.peakEvidence?.peakEvidence.knownInterruptionCount == 2)
        #expect(secondGap.telemetryBenchmark.knownObservationInterruptionCount == 2)
    }

    @Test("initial recovery gap stays one gap until first accepted source evidence")
    func initialGapIsNotDoubleCountedBeforeFirstEvidence() throws {
        var session = RideSpeedEvidenceSessionAccumulator(
            sessionID: sessionID,
            peakPolicy: try PeakSpeedPolicy(source: .scooterBluetooth),
            beginsAfterKnownObservationGap: true
        )

        session.recordInterruption(.applicationLifecycleInterrupted)
        session.recordInterruption(.selectedSourceUnavailable)
        _ = session.record(try sample(uptime: 100))

        let resumed = session.snapshot
        #expect(resumed.peakEvidence?.beganAfterKnownObservationGap == true)
        #expect(resumed.peakEvidence?.peakEvidence.knownInterruptionCount == 1)
        #expect(resumed.telemetryBenchmark.knownObservationInterruptionCount == 0)

        session.recordInterruption(.selectedSourceUnavailable)
        let laterGap = session.snapshot
        #expect(laterGap.peakEvidence?.peakEvidence.knownInterruptionCount == 2)
        #expect(laterGap.telemetryBenchmark.knownObservationInterruptionCount == 1)
    }

    @Test("rejected selected-source evidence does not rearm the same pending gap")
    func rejectedSelectedSourceEvidenceDoesNotEndPendingGap() throws {
        var session = RideSpeedEvidenceSessionAccumulator(
            sessionID: sessionID,
            peakPolicy: try PeakSpeedPolicy(source: .scooterBluetooth)
        )

        _ = session.record(try sample(uptime: 100))
        session.recordInterruption(.selectedSourceUnavailable)

        let overflowing = try sample(
            metersPerSecond: Double.greatestFiniteMagnitude / 2,
            uptime: 300
        )
        let result = session.record(overflowing)
        #expect(result.benchmark == .rejected(.nonFiniteDerivedSpeed))
        #expect(result.peak == .rejected(.nonFiniteDerivedSpeed))

        session.recordInterruption(.selectedSourceUnavailable)
        let stillSameGap = session.snapshot
        #expect(stillSameGap.peakEvidence?.peakEvidence.knownInterruptionCount == 1)
        #expect(stillSameGap.telemetryBenchmark.knownObservationInterruptionCount == 1)

        _ = session.record(try sample(metersPerSecond: 7, uptime: 400))
        session.recordInterruption(.selectedSourceUnavailable)
        let newGap = session.snapshot
        #expect(newGap.peakEvidence?.peakEvidence.knownInterruptionCount == 2)
        #expect(newGap.telemetryBenchmark.knownObservationInterruptionCount == 2)
    }

    @Test("raw GPS resumption rearms gaps even when peak-specific accuracy rejects it")
    func rawSourceResumptionIsIndependentOfPeakAccuracyGate() throws {
        var session = RideSpeedEvidenceSessionAccumulator(
            sessionID: sessionID,
            peakPolicy: try PeakSpeedPolicy(
                source: .gps,
                maximumSpeedAccuracyMetersPerSecond: 0.5
            )
        )

        _ = session.record(try sample(
            source: .gps,
            uptime: 100,
            accuracy: 0.4
        ))
        session.recordInterruption(.selectedSourceUnavailable)

        let resumedRawSource = session.record(try sample(
            source: .gps,
            metersPerSecond: 6,
            uptime: 200,
            accuracy: 0.8
        ))
        #expect(resumedRawSource.benchmark == .accepted)
        #expect(
            resumedRawSource.peak == .rejected(
                .speedAccuracyExceeded(maximum: 0.5, actual: 0.8)
            )
        )

        session.recordInterruption(.selectedSourceUnavailable)
        let snapshot = session.snapshot
        #expect(snapshot.peakEvidence?.peakEvidence.knownInterruptionCount == 2)
        #expect(snapshot.telemetryBenchmark.knownObservationInterruptionCount == 2)
        #expect(snapshot.peakEvidence?.peakEvidence.qualityRejectedSampleCount == 1)
    }
}
