import Foundation
import Testing
@testable import NembraCore

@Suite("Truthful acceleration timing")
struct AccelerationTimingTests {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)
    /// Synthetic software fixture only. This is deliberately not a production
    /// AOVOPRO ES80 stationary threshold.
    private let fixtureStationaryMaximumMetersPerSecond = 0.5

    private func policy(
        targetMetersPerSecond: Double,
        requiredSource: SpeedTelemetrySource? = nil,
        maximumSpeedAccuracyMetersPerSecond: Double? = nil,
        maximumSampleIntervalNanoseconds: UInt64? = nil
    ) throws -> AccelerationRunPolicy {
        try AccelerationRunPolicy(
            targetMetersPerSecond: targetMetersPerSecond,
            stationaryMaximumMetersPerSecond: fixtureStationaryMaximumMetersPerSecond,
            requiredSource: requiredSource,
            maximumSpeedAccuracyMetersPerSecond: maximumSpeedAccuracyMetersPerSecond,
            maximumSampleIntervalNanoseconds: maximumSampleIntervalNanoseconds
        )
    }

    private func sample(
        source: SpeedTelemetrySource = .scooterBluetooth,
        provenance: SpeedTelemetryProvenance = .absoluteMeasurement,
        metersPerSecond: Double,
        seconds: Double,
        accuracy: Double? = nil,
        receivedAtDate: Date? = nil,
        measurementDate: Date? = nil
    ) throws -> SpeedTelemetrySample {
        try SpeedTelemetrySample(
            source: source,
            provenance: provenance,
            metersPerSecond: metersPerSecond,
            receivedAtUptimeNanoseconds: UInt64(seconds * 1_000_000_000),
            receivedAtDate: receivedAtDate ?? epoch,
            measurementDate: measurementDate,
            speedAccuracyMetersPerSecond: accuracy
        )
    }

    @Test("rolling start is rejected before a standstill anchor exists")
    func rollingStartRejected() throws {
        var evaluator = AccelerationRunEvaluator(policy: try policy(targetMetersPerSecond: 5))
        evaluator.accept(try sample(metersPerSecond: 1.5, seconds: 1))
        #expect(evaluator.state == .invalidated(.rollingStart))
    }

    @Test("completed run reports only receive-clock observation interval")
    func reportsReceiveClockObservationInterval() throws {
        var evaluator = AccelerationRunEvaluator(policy: try policy(targetMetersPerSecond: 5))
        evaluator.accept(try sample(metersPerSecond: 0, seconds: 1))
        evaluator.accept(try sample(metersPerSecond: 2, seconds: 2))
        evaluator.accept(try sample(metersPerSecond: 4, seconds: 3))
        evaluator.accept(try sample(metersPerSecond: 6, seconds: 4))

        guard case let .completed(result) = evaluator.state else {
            Issue.record("Expected completed run")
            return
        }
        #expect(result.timingBasis == .receiveObservationUptime)
        #expect(result.launchObservationWindow == AccelerationTimingWindow(
            earliestUptimeNanoseconds: 1_000_000_000,
            latestUptimeNanoseconds: 2_000_000_000
        ))
        #expect(result.targetTransitionObservationWindow == AccelerationTimingWindow(
            earliestUptimeNanoseconds: 3_000_000_000,
            latestUptimeNanoseconds: 4_000_000_000
        ))
        #expect(result.stationaryToTargetObservationElapsedSeconds == 3)
        #expect(result.timingEvidenceSampleCount == 4)
    }

    @Test("below-target samples do not become a first-reach timing claim")
    func earlierUnsampledTargetExcursionRemainsPossible() throws {
        var evaluator = AccelerationRunEvaluator(policy: try policy(targetMetersPerSecond: 10))
        evaluator.accept(try sample(metersPerSecond: 0, seconds: 0))
        evaluator.accept(try sample(metersPerSecond: 2, seconds: 1))
        evaluator.accept(try sample(metersPerSecond: 9, seconds: 2))
        evaluator.accept(try sample(metersPerSecond: 8, seconds: 3))
        evaluator.accept(try sample(metersPerSecond: 10, seconds: 4))

        guard case let .completed(result) = evaluator.state else {
            Issue.record("Expected completed run")
            return
        }

        #expect(result.timingBasis == .receiveObservationUptime)
        #expect(result.launchObservationWindow == AccelerationTimingWindow(
            earliestUptimeNanoseconds: 0,
            latestUptimeNanoseconds: 1_000_000_000
        ))
        #expect(result.targetTransitionObservationWindow == AccelerationTimingWindow(
            earliestUptimeNanoseconds: 3_000_000_000,
            latestUptimeNanoseconds: 4_000_000_000
        ))
        #expect(result.stationaryToTargetObservationElapsedSeconds == 4)
    }

    @Test("measurement dates and delivery latency do not silently become the timing basis")
    func receiveUptimeRemainsExplicitTimingBasis() throws {
        var evaluator = AccelerationRunEvaluator(policy: try policy(targetMetersPerSecond: 5))

        evaluator.accept(try sample(
            metersPerSecond: 0,
            seconds: 1,
            receivedAtDate: epoch.addingTimeInterval(1.5),
            measurementDate: epoch.addingTimeInterval(1.0)
        ))
        evaluator.accept(try sample(
            metersPerSecond: 2,
            seconds: 2,
            receivedAtDate: epoch.addingTimeInterval(2.4),
            measurementDate: epoch.addingTimeInterval(1.2)
        ))
        evaluator.accept(try sample(
            metersPerSecond: 6,
            seconds: 3,
            receivedAtDate: epoch.addingTimeInterval(3.1),
            measurementDate: epoch.addingTimeInterval(2.5)
        ))

        guard case let .completed(result) = evaluator.state else {
            Issue.record("Expected completed run")
            return
        }

        #expect(result.timingBasis == .receiveObservationUptime)
        #expect(result.launchObservationWindow == AccelerationTimingWindow(
            earliestUptimeNanoseconds: 1_000_000_000,
            latestUptimeNanoseconds: 2_000_000_000
        ))
        #expect(result.targetTransitionObservationWindow == AccelerationTimingWindow(
            earliestUptimeNanoseconds: 2_000_000_000,
            latestUptimeNanoseconds: 3_000_000_000
        ))
        #expect(result.stationaryToTargetObservationElapsedSeconds == 2)
    }

    @Test("timing evidence count excludes superseded stationary anchors")
    func timingEvidenceCountReflectsRetainedTrace() throws {
        var evaluator = AccelerationRunEvaluator(policy: try policy(targetMetersPerSecond: 5))
        evaluator.accept(try sample(metersPerSecond: 0, seconds: 1))
        evaluator.accept(try sample(metersPerSecond: 0.1, seconds: 2))
        evaluator.accept(try sample(metersPerSecond: 2, seconds: 3))
        evaluator.accept(try sample(metersPerSecond: 6, seconds: 4))

        guard case let .completed(result) = evaluator.state else {
            Issue.record("Expected completed run")
            return
        }
        #expect(result.launchObservationWindow == AccelerationTimingWindow(
            earliestUptimeNanoseconds: 2_000_000_000,
            latestUptimeNanoseconds: 3_000_000_000
        ))
        #expect(result.timingEvidenceSampleCount == 3)
    }

    @Test("a sparse sample that already reaches target remains observation-bounded")
    func sparseImmediateTargetObservation() throws {
        var evaluator = AccelerationRunEvaluator(policy: try policy(targetMetersPerSecond: 5))
        evaluator.accept(try sample(metersPerSecond: 0, seconds: 10))
        evaluator.accept(try sample(metersPerSecond: 6, seconds: 10.4))

        guard case let .completed(result) = evaluator.state else {
            Issue.record("Expected completed run")
            return
        }
        #expect(abs(result.stationaryToTargetObservationElapsedSeconds - 0.4) < 0.000_001)
        #expect(result.timingEvidenceSampleCount == 2)
    }

    @Test("motion-assisted display estimate cannot arm or advance a run")
    func motionEstimateIgnored() throws {
        var evaluator = AccelerationRunEvaluator(policy: try policy(targetMetersPerSecond: 5))
        evaluator.accept(try sample(
            source: .motionAssist,
            provenance: .shortHorizonEstimate,
            metersPerSecond: 0,
            seconds: 1
        ))
        #expect(evaluator.state == .waitingForStandstill)
        evaluator.accept(try sample(metersPerSecond: 0, seconds: 2))
        #expect(evaluator.state == .armed(source: .scooterBluetooth))
    }

    @Test("decoded impossible motion-assist provenance cannot become authoritative timing evidence")
    func malformedDecodedMotionAssistIsIgnored() throws {
        let valid = try sample(metersPerSecond: 0, seconds: 1)
        let encoded = try JSONEncoder().encode(valid)
        let validJSON = try #require(String(data: encoded, encoding: .utf8))
        let malformedJSON = validJSON.replacingOccurrences(
            of: "\"scooterBluetooth\"",
            with: "\"motionAssist\""
        )
        #expect(malformedJSON != validJSON)

        let malformed = try JSONDecoder().decode(
            SpeedTelemetrySample.self,
            from: try #require(malformedJSON.data(using: .utf8))
        )
        #expect(malformed.source == .motionAssist)
        #expect(malformed.isAuthoritativeMeasurement)

        var evaluator = AccelerationRunEvaluator(policy: try policy(targetMetersPerSecond: 5))
        evaluator.accept(malformed)
        #expect(evaluator.state == .waitingForStandstill)
    }

    @Test("a source change invalidates an in-progress timing trace")
    func sourceChangeInvalidates() throws {
        var evaluator = AccelerationRunEvaluator(policy: try policy(targetMetersPerSecond: 5))
        evaluator.accept(try sample(metersPerSecond: 0, seconds: 1))
        evaluator.accept(try sample(metersPerSecond: 2, seconds: 2))
        evaluator.accept(try sample(source: .gps, metersPerSecond: 3, seconds: 3, accuracy: 0.5))
        #expect(evaluator.state == .invalidated(.measurementSourceChanged))
    }

    @Test("required source ignores other authoritative providers before they can affect timing")
    func requiredSourceIgnoresOthers() throws {
        var evaluator = AccelerationRunEvaluator(policy: try policy(
            targetMetersPerSecond: 5,
            requiredSource: .gps,
            maximumSpeedAccuracyMetersPerSecond: 1
        ))
        evaluator.accept(try sample(metersPerSecond: 0, seconds: 1))
        #expect(evaluator.state == .waitingForStandstill)
        evaluator.accept(try sample(source: .gps, metersPerSecond: 0, seconds: 2, accuracy: 2))
        #expect(evaluator.state == .waitingForStandstill)
        evaluator.accept(try sample(source: .gps, metersPerSecond: 0, seconds: 3, accuracy: 0.5))
        #expect(evaluator.state == .armed(source: .gps))
    }

    @Test("quality-rejected locked-source observation still protects monotonic ordering")
    func rejectedQualityObservationPreventsOlderMeasurementFromBecomingFresh() throws {
        var evaluator = AccelerationRunEvaluator(policy: try policy(
            targetMetersPerSecond: 5,
            requiredSource: .gps,
            maximumSpeedAccuracyMetersPerSecond: 1
        ))
        evaluator.accept(try sample(
            source: .gps,
            metersPerSecond: 0,
            seconds: 1,
            accuracy: 0.4
        ))
        #expect(evaluator.state == .armed(source: .gps))

        evaluator.accept(try sample(
            source: .gps,
            metersPerSecond: 3,
            seconds: 3,
            accuracy: 2
        ))
        #expect(evaluator.state == .armed(source: .gps))

        evaluator.accept(try sample(
            source: .gps,
            metersPerSecond: 2,
            seconds: 2,
            accuracy: 0.4
        ))
        #expect(evaluator.state == .invalidated(.nonMonotonicMeasurement))
    }

    @Test("nonmonotonic authoritative measurement invalidates timing evidence")
    func nonMonotonicInvalidates() throws {
        var evaluator = AccelerationRunEvaluator(policy: try policy(targetMetersPerSecond: 5))
        evaluator.accept(try sample(metersPerSecond: 0, seconds: 2))
        evaluator.accept(try sample(metersPerSecond: 2, seconds: 3))
        evaluator.accept(try sample(metersPerSecond: 3, seconds: 2.5))
        #expect(evaluator.state == .invalidated(.nonMonotonicMeasurement))
    }

    @Test("configured sample interval ceiling rejects weak timing evidence")
    func longMeasurementGapInvalidates() throws {
        var evaluator = AccelerationRunEvaluator(policy: try policy(
            targetMetersPerSecond: 5,
            maximumSampleIntervalNanoseconds: 1_500_000_000
        ))
        evaluator.accept(try sample(metersPerSecond: 0, seconds: 1))
        evaluator.accept(try sample(metersPerSecond: 2, seconds: 2))
        evaluator.accept(try sample(metersPerSecond: 6, seconds: 4))
        #expect(evaluator.state == .invalidated(.measurementGapExceeded))
    }

    @Test("sample-gap ceiling measures usable timing evidence rather than rejected callbacks")
    func rejectedQualityCallbackDoesNotHideAcceptedMeasurementGap() throws {
        var evaluator = AccelerationRunEvaluator(policy: try policy(
            targetMetersPerSecond: 5,
            requiredSource: .gps,
            maximumSpeedAccuracyMetersPerSecond: 1,
            maximumSampleIntervalNanoseconds: 1_500_000_000
        ))
        evaluator.accept(try sample(
            source: .gps,
            metersPerSecond: 0,
            seconds: 1,
            accuracy: 0.4
        ))
        evaluator.accept(try sample(
            source: .gps,
            metersPerSecond: 2,
            seconds: 2,
            accuracy: 2
        ))
        evaluator.accept(try sample(
            source: .gps,
            metersPerSecond: 3,
            seconds: 3,
            accuracy: 0.4
        ))
        #expect(evaluator.state == .invalidated(.measurementGapExceeded))
    }

    @Test("connection interruption invalidates armed or running evidence")
    func interruptionInvalidates() throws {
        var evaluator = AccelerationRunEvaluator(policy: try policy(targetMetersPerSecond: 5))
        evaluator.accept(try sample(metersPerSecond: 0, seconds: 1))
        evaluator.accept(try sample(metersPerSecond: 2, seconds: 2))
        evaluator.interrupt(.vehicleConnectionLost)
        #expect(evaluator.state == .invalidated(.interruption(.vehicleConnectionLost)))
    }

    @Test("operator cancellation is terminal even while waiting for standstill")
    func operatorCancellationStopsWaitingAttemptUntilReset() throws {
        var evaluator = AccelerationRunEvaluator(policy: try policy(targetMetersPerSecond: 5))
        evaluator.interrupt(.operatorCancelled)
        #expect(evaluator.state == .invalidated(.interruption(.operatorCancelled)))

        evaluator.accept(try sample(metersPerSecond: 0, seconds: 1))
        #expect(evaluator.state == .invalidated(.interruption(.operatorCancelled)))

        evaluator.reset()
        evaluator.accept(try sample(metersPerSecond: 0, seconds: 2))
        #expect(evaluator.state == .armed(source: .scooterBluetooth))
    }

    @Test("returning to stationary after launch invalidates rather than silently restarting")
    func returnedToStationaryInvalidates() throws {
        var evaluator = AccelerationRunEvaluator(policy: try policy(targetMetersPerSecond: 5))
        evaluator.accept(try sample(metersPerSecond: 0, seconds: 1))
        evaluator.accept(try sample(metersPerSecond: 2, seconds: 2))
        evaluator.accept(try sample(metersPerSecond: 0.2, seconds: 3))
        #expect(evaluator.state == .invalidated(.returnedToStationary))
    }

    @Test("reset discards prior invalid evidence and requires a fresh standstill")
    func resetRequiresFreshStandstill() throws {
        var evaluator = AccelerationRunEvaluator(policy: try policy(targetMetersPerSecond: 5))
        evaluator.accept(try sample(metersPerSecond: 2, seconds: 1))
        #expect(evaluator.state == .invalidated(.rollingStart))
        evaluator.reset()
        #expect(evaluator.state == .waitingForStandstill)
        evaluator.accept(try sample(metersPerSecond: 0, seconds: 2))
        #expect(evaluator.state == .armed(source: .scooterBluetooth))
    }

    @Test("policy validation rejects impossible timing configurations")
    func policyValidation() {
        #expect(throws: AccelerationRunPolicyError.invalidTargetSpeed) {
            try AccelerationRunPolicy(
                targetMetersPerSecond: 0,
                stationaryMaximumMetersPerSecond: 0.5
            )
        }
        #expect(throws: AccelerationRunPolicyError.invalidStationaryThreshold) {
            try AccelerationRunPolicy(
                targetMetersPerSecond: 5,
                stationaryMaximumMetersPerSecond: 5
            )
        }
        #expect(throws: AccelerationRunPolicyError.invalidMaximumSpeedAccuracy) {
            try AccelerationRunPolicy(
                targetMetersPerSecond: 5,
                stationaryMaximumMetersPerSecond: 0.5,
                maximumSpeedAccuracyMetersPerSecond: .infinity
            )
        }
        #expect(throws: AccelerationRunPolicyError.invalidMaximumSampleInterval) {
            try AccelerationRunPolicy(
                targetMetersPerSecond: 5,
                stationaryMaximumMetersPerSecond: 0.5,
                maximumSampleIntervalNanoseconds: 0
            )
        }
        #expect(throws: AccelerationRunPolicyError.invalidRequiredSource) {
            try AccelerationRunPolicy(
                targetMetersPerSecond: 5,
                stationaryMaximumMetersPerSecond: 0.5,
                requiredSource: .motionAssist
            )
        }
    }
}
