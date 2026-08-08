import Foundation
import Testing

@testable import NembraCore

@Suite("Ride speed evidence selected-source chronology")
struct RideSpeedEvidenceSessionSelectedSourceChronologyTests {
    private let sessionID = UUID(uuidString: "13572468-2468-1357-2468-135724681357")!
    private let epoch = Date(timeIntervalSinceReferenceDate: 20_000)

    private func sample(
        metersPerSecond: Double,
        uptime: UInt64
    ) throws -> SpeedTelemetrySample {
        try SpeedTelemetrySample(
            source: .scooterBluetooth,
            provenance: .absoluteMeasurement,
            metersPerSecond: metersPerSecond,
            receivedAtUptimeNanoseconds: uptime,
            receivedAtDate: epoch
        )
    }

    @Test("rejected newer callback closes delayed replay in both ride-owned evidence pipelines")
    func rejectedNewerCallbackClosesDelayedReplay() throws {
        var session = RideSpeedEvidenceSessionAccumulator(
            sessionID: sessionID,
            peakPolicy: try PeakSpeedPolicy(source: .scooterBluetooth)
        )

        let first = session.record(try sample(
            metersPerSecond: 5,
            uptime: 100_000_000
        ))
        #expect(first.benchmark == .accepted)
        let firstPeakWasUpdated: Bool
        if case .peakUpdated = first.peak {
            firstPeakWasUpdated = true
        } else {
            firstPeakWasUpdated = false
        }
        #expect(firstPeakWasUpdated)

        // Finite SI speed whose required km/h representation overflows. The
        // callback is unusable as benchmark/peak evidence, but its receive
        // chronology is still observed by both selected-source pipelines.
        let rejectedNewer = session.record(try sample(
            metersPerSecond: Double.greatestFiniteMagnitude / 2,
            uptime: 300_000_000
        ))
        #expect(rejectedNewer.benchmark == .rejected(.nonFiniteDerivedSpeed))
        #expect(rejectedNewer.peak == .rejected(.nonFiniteDerivedSpeed))

        // This value is numerically valid but arrived after the @300 callback and
        // therefore cannot become fresh evidence merely because @300 was rejected.
        let delayedReplay = session.record(try sample(
            metersPerSecond: 20,
            uptime: 200_000_000
        ))
        #expect(delayedReplay.benchmark == .rejected(.nonMonotonicTimestamp))
        #expect(delayedReplay.peak == .rejected(.nonIncreasingTimestamp))

        let fresh = session.record(try sample(
            metersPerSecond: 6,
            uptime: 400_000_000
        ))
        #expect(fresh.benchmark == .accepted)
        let freshPeakWasUpdated: Bool
        if case .peakUpdated = fresh.peak {
            freshPeakWasUpdated = true
        } else {
            freshPeakWasUpdated = false
        }
        #expect(freshPeakWasUpdated)

        let snapshot = session.snapshot
        let peak = try #require(snapshot.peakEvidence)

        #expect(snapshot.telemetryBenchmark.acceptedSampleCount == 2)
        #expect(snapshot.telemetryBenchmark.rejectedSampleCount == 2)
        #expect(snapshot.telemetryBenchmark.intervalCount == 1)
        #expect(snapshot.peakRejections.nonFiniteDerivedSpeedCount == 1)
        #expect(snapshot.peakRejections.nonIncreasingTimestampCount == 1)
        #expect(snapshot.peakRejections.totalRejectedSampleCount == 2)
        #expect(peak.peakEvidence.acceptedSampleCount == 2)
        #expect(peak.peakEvidence.qualityRejectedSampleCount == 2)
        #expect(peak.peakEvidence.peak.metersPerSecond == 6)
    }
}
