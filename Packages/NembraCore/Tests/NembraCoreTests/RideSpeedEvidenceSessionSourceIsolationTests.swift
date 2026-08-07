import Foundation
import Testing

@testable import NembraCore

@Suite("Ride speed evidence source isolation")
struct RideSpeedEvidenceSessionSourceIsolationTests {
    private let sessionID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let epoch = Date(timeIntervalSinceReferenceDate: 10_000)

    private func sample(
        source: SpeedTelemetrySource,
        metersPerSecond: Double,
        uptime: UInt64
    ) throws -> SpeedTelemetrySample {
        try SpeedTelemetrySample(
            source: source,
            provenance: .absoluteMeasurement,
            metersPerSecond: metersPerSecond,
            receivedAtUptimeNanoseconds: uptime,
            receivedAtDate: epoch
        )
    }

    @Test("foreign source blocks peak even when generic rejection policy would allow it")
    func permissiveRejectionPolicyCannotHideForeignSource() throws {
        var session = RideSpeedEvidenceSessionAccumulator(
            sessionID: sessionID,
            peakPolicy: try PeakSpeedPolicy(source: .scooterBluetooth)
        )

        _ = session.record(try sample(
            source: .gps,
            metersPerSecond: 20,
            uptime: 50_000_000
        ))
        _ = session.record(try sample(
            source: .scooterBluetooth,
            metersPerSecond: 1,
            uptime: 100_000_000
        ))
        _ = session.record(try sample(
            source: .scooterBluetooth,
            metersPerSecond: 2,
            uptime: 200_000_000
        ))
        _ = session.record(try sample(
            source: .scooterBluetooth,
            metersPerSecond: 3,
            uptime: 300_000_000
        ))

        let permissiveTelemetry = try SpeedTelemetryQualityPolicy(
            requiredSource: .scooterBluetooth,
            minimumAcceptedSampleCount: 3,
            maximumRejectedSampleFraction: 0.5,
            maximumMeanIntervalMilliseconds: 150,
            maximumObservedIntervalMilliseconds: 200,
            maximumJitterStandardDeviationMilliseconds: 50,
            maximumEmpiricalSpeedStepKilometersPerHour: 10
        )
        let policy = try RideObservedPeakQualityPolicy(telemetry: permissiveTelemetry)
        let readiness = session.snapshot.observedPeakReadiness(using: policy)

        #expect(readiness.telemetryQuality.isQualified)
        #expect(session.snapshot.foreignSourceCallbackCount == 1)
        #expect(session.snapshot.peakEvidence?.peakEvidence.continuity == .noRecordedSelectedSourceEvidenceLoss)
        #expect(!readiness.isReady)
        #expect(readiness.failures == [.foreignSourceTraffic(callbackCount: 1)])
    }

    @Test("multiple foreign callbacks remain explicit instead of collapsing to a boolean")
    func foreignSourceCallbackCountIsStableEvidence() throws {
        var session = RideSpeedEvidenceSessionAccumulator(
            sessionID: sessionID,
            peakPolicy: try PeakSpeedPolicy(source: .scooterBluetooth)
        )

        _ = session.record(try sample(source: .gps, metersPerSecond: 10, uptime: 10))
        _ = session.record(try sample(source: .gps, metersPerSecond: 11, uptime: 20))

        #expect(session.snapshot.foreignSourceCallbackCount == 2)
        #expect(session.snapshot.telemetryBenchmark.rejectedSampleCount == 2)
        #expect(session.snapshot.peakEvidence == nil)
    }
}
