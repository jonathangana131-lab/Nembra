import Foundation
import Testing
@testable import NembraCore

@Suite("Acceleration same-attempt evidence session")
struct AccelerationEvidenceSessionTests {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private func runPolicy(
        source: SpeedTelemetrySource? = .scooterBluetooth,
        maximumSampleIntervalNanoseconds: UInt64? = 300_000_000,
        maximumSpeedAccuracyMetersPerSecond: Double? = nil
    ) throws -> AccelerationRunPolicy {
        try AccelerationRunPolicy(
            targetMetersPerSecond: 10,
            stationaryMaximumMetersPerSecond: 0.25,
            requiredSource: source,
            maximumSpeedAccuracyMetersPerSecond: maximumSpeedAccuracyMetersPerSecond,
            maximumSampleIntervalNanoseconds: maximumSampleIntervalNanoseconds
        )
    }

    private func telemetryPolicy(
        source: SpeedTelemetrySource? = .scooterBluetooth,
        minimumAcceptedSampleCount: Int = 4,
        maximumRejectedSampleFraction: Double? = 0,
        maximumMeanIntervalMilliseconds: Double? = 300,
        maximumObservedIntervalMilliseconds: Double? = 300,
        maximumJitterStandardDeviationMilliseconds: Double? = 300,
        minimumDeliveryLatencySampleFraction: Double? = nil,
        maximumMeanDeliveryLatencyMilliseconds: Double? = nil,
        maximumEmpiricalSpeedStepKilometersPerHour: Double? = 20
    ) throws -> SpeedTelemetryQualityPolicy {
        try SpeedTelemetryQualityPolicy(
            requiredSource: source,
            minimumAcceptedSampleCount: minimumAcceptedSampleCount,
            maximumRejectedSampleFraction: maximumRejectedSampleFraction,
            maximumMeanIntervalMilliseconds: maximumMeanIntervalMilliseconds,
            maximumObservedIntervalMilliseconds: maximumObservedIntervalMilliseconds,
            maximumJitterStandardDeviationMilliseconds: maximumJitterStandardDeviationMilliseconds,
            minimumDeliveryLatencySampleFraction: minimumDeliveryLatencySampleFraction,
            maximumMeanDeliveryLatencyMilliseconds: maximumMeanDeliveryLatencyMilliseconds,
            maximumEmpiricalSpeedStepKilometersPerHour: maximumEmpiricalSpeedStepKilometersPerHour
        )
    }

    private func policy(
        source: SpeedTelemetrySource = .scooterBluetooth,
        maximumSampleIntervalNanoseconds: UInt64 = 300_000_000,
        maximumSpeedAccuracyMetersPerSecond: Double? = nil
    ) throws -> AccelerationEvidenceSessionPolicy {
        let telemetry: SpeedTelemetryQualityPolicy
        if source == .gps {
            telemetry = try telemetryPolicy(
                source: .gps,
                minimumDeliveryLatencySampleFraction: 1,
                maximumMeanDeliveryLatencyMilliseconds: 150
            )
        } else {
            telemetry = try telemetryPolicy(source: source)
        }

        return try AccelerationEvidenceSessionPolicy(
            run: runPolicy(
                source: source,
                maximumSampleIntervalNanoseconds: maximumSampleIntervalNanoseconds,
                maximumSpeedAccuracyMetersPerSecond: maximumSpeedAccuracyMetersPerSecond
            ),
            telemetry: telemetry
        )
    }

    private func sample(
        source: SpeedTelemetrySource = .scooterBluetooth,
        metersPerSecond: Double,
        uptimeNanoseconds: UInt64,
        speedAccuracyMetersPerSecond: Double? = nil,
        deliveryLatencyMilliseconds: Double? = nil
    ) throws -> SpeedTelemetrySample {
        let receivedAtDate = epoch.addingTimeInterval(Double(uptimeNanoseconds) / 1_000_000_000)
        let measurementDate = deliveryLatencyMilliseconds.map {
            receivedAtDate.addingTimeInterval(-$0 / 1_000)
        }

        return try SpeedTelemetrySample(
            source: source,
            provenance: source == .motionAssist ? .shortHorizonEstimate : .absoluteMeasurement,
            metersPerSecond: metersPerSecond,
            receivedAtUptimeNanoseconds: uptimeNanoseconds,
            receivedAtDate: receivedAtDate,
            measurementDate: measurementDate,
            speedAccuracyMetersPerSecond: speedAccuracyMetersPerSecond
        )
    }

    @Test("qualification requires one explicit source on both policies")
    func explicitSourceRequired() throws {
        let telemetry = try telemetryPolicy()
        #expect(throws: AccelerationEvidenceSessionPolicyError.runSourceRequired) {
            _ = try AccelerationEvidenceSessionPolicy(
                run: runPolicy(source: nil),
                telemetry: telemetry
            )
        }

        let run = try runPolicy()
        #expect(throws: AccelerationEvidenceSessionPolicyError.telemetrySourceRequired) {
            _ = try AccelerationEvidenceSessionPolicy(
                run: run,
                telemetry: telemetryPolicy(source: nil)
            )
        }
    }

    @Test("run and benchmark source must be identical")
    func sourceMismatchRejected() throws {
        #expect(throws: AccelerationEvidenceSessionPolicyError.sourceMismatch(
            run: .scooterBluetooth,
            telemetry: .gps
        )) {
            _ = try AccelerationEvidenceSessionPolicy(
                run: runPolicy(source: .scooterBluetooth),
                telemetry: telemetryPolicy(source: .gps)
            )
        }
    }

    @Test("weak-cadence protection cannot be omitted from the run")
    func maximumSampleIntervalRequired() throws {
        #expect(throws: AccelerationEvidenceSessionPolicyError.runMaximumSampleIntervalRequired) {
            _ = try AccelerationEvidenceSessionPolicy(
                run: runPolicy(maximumSampleIntervalNanoseconds: nil),
                telemetry: telemetryPolicy()
            )
        }
    }

    @Test("GPS qualification requires speed accuracy and delivery latency evidence")
    func gpsRequirementsAreExplicit() throws {
        let completeGPSQuality = try telemetryPolicy(
            source: .gps,
            minimumDeliveryLatencySampleFraction: 1,
            maximumMeanDeliveryLatencyMilliseconds: 150
        )
        #expect(throws: AccelerationEvidenceSessionPolicyError.gpsSpeedAccuracyRequirementRequired) {
            _ = try AccelerationEvidenceSessionPolicy(
                run: runPolicy(source: .gps),
                telemetry: completeGPSQuality
            )
        }

        let gpsRun = try runPolicy(
            source: .gps,
            maximumSpeedAccuracyMetersPerSecond: 1
        )
        #expect(throws: AccelerationEvidenceSessionPolicyError.gpsLatencyCoverageRequirementRequired) {
            _ = try AccelerationEvidenceSessionPolicy(
                run: gpsRun,
                telemetry: telemetryPolicy(source: .gps)
            )
        }
        #expect(throws: AccelerationEvidenceSessionPolicyError.gpsLatencyRequirementRequired) {
            _ = try AccelerationEvidenceSessionPolicy(
                run: gpsRun,
                telemetry: telemetryPolicy(
                    source: .gps,
                    minimumDeliveryLatencySampleFraction: 1
                )
            )
        }
    }

    @Test("quality policy must contain meaningful jitter and resolution evidence")
    func qualityShapeCannotBeTriviallyGreen() throws {
        let run = try runPolicy()
        #expect(throws: AccelerationEvidenceSessionPolicyError.minimumAcceptedSampleCountInsufficientForJitter(
            required: 3,
            actual: 2
        )) {
            _ = try AccelerationEvidenceSessionPolicy(
                run: run,
                telemetry: telemetryPolicy(minimumAcceptedSampleCount: 2)
            )
        }
        #expect(throws: AccelerationEvidenceSessionPolicyError.jitterRequirementRequired) {
            _ = try AccelerationEvidenceSessionPolicy(
                run: run,
                telemetry: telemetryPolicy(maximumJitterStandardDeviationMilliseconds: nil)
            )
        }
        #expect(throws: AccelerationEvidenceSessionPolicyError.speedResolutionRequirementRequired) {
            _ = try AccelerationEvidenceSessionPolicy(
                run: run,
                telemetry: telemetryPolicy(maximumEmpiricalSpeedStepKilometersPerHour: nil)
            )
        }
    }

    @Test("one selected-source stream can complete and qualify without inventing crossing time")
    func completeRunQualifiesFromSameCallbacks() throws {
        var session = AccelerationEvidenceSession(policy: try policy())
        let samples = try [
            sample(metersPerSecond: 0, uptimeNanoseconds: 1_000_000_000),
            sample(metersPerSecond: 4, uptimeNanoseconds: 1_200_000_000),
            sample(metersPerSecond: 8, uptimeNanoseconds: 1_400_000_000),
            sample(metersPerSecond: 10, uptimeNanoseconds: 1_600_000_000)
        ]

        for evidence in samples {
            _ = session.record(evidence)
        }

        let snapshot = session.snapshot
        let readiness = snapshot.readiness()
        let result = try #require(readiness.result)

        #expect(readiness.isReady)
        #expect(readiness.failures.isEmpty)
        #expect(readiness.telemetryQuality.isQualified)
        #expect(snapshot.telemetryBenchmark.acceptedSampleCount == 4)
        #expect(snapshot.telemetryBenchmark.intervalCount == 3)
        #expect(snapshot.selectedSourceBenchmarkRejectionCount == 0)
        #expect(result.source == .scooterBluetooth)
        #expect(result.timingBasis == .receiveObservationUptime)
        #expect(abs(result.stationaryToTargetObservationElapsedSeconds - 0.6) < 0.000_001)
        #expect(result.timingEvidenceSampleCount == 4)
    }

    @Test("foreign providers coexist without contaminating the selected-source benchmark")
    func foreignSourceIsIgnoredBeforeBothEvidenceConsumers() throws {
        var session = AccelerationEvidenceSession(policy: try policy())
        let foreign = try sample(
            source: .gps,
            metersPerSecond: 3,
            uptimeNanoseconds: 900_000_000,
            speedAccuracyMetersPerSecond: 0.5,
            deliveryLatencyMilliseconds: 20
        )

        #expect(session.record(foreign) == .ignoredForeignSource(
            expected: .scooterBluetooth,
            actual: .gps
        ))
        #expect(session.snapshot.ignoredForeignSourceCallbackCount == 1)
        #expect(session.snapshot.telemetryBenchmark.acceptedSampleCount == 0)
        #expect(session.snapshot.telemetryBenchmark.rejectedSampleCount == 0)
        #expect(session.state == .waitingForStandstill)
    }

    @Test("post-completion packets cannot improve a completed attempt's quality")
    func completedSessionFreezesEvidence() throws {
        var session = AccelerationEvidenceSession(policy: try policy())
        for evidence in try [
            sample(metersPerSecond: 0, uptimeNanoseconds: 1_000_000_000),
            sample(metersPerSecond: 4, uptimeNanoseconds: 1_200_000_000),
            sample(metersPerSecond: 8, uptimeNanoseconds: 1_400_000_000),
            sample(metersPerSecond: 10, uptimeNanoseconds: 1_600_000_000)
        ] {
            _ = session.record(evidence)
        }

        let frozen = session.snapshot
        #expect(session.record(try sample(
            metersPerSecond: 12,
            uptimeNanoseconds: 1_800_000_000
        )) == .ignoredAfterTerminalEvidence)
        #expect(session.snapshot == frozen)
    }

    @Test("known observation gaps freeze the attempt instead of stitching across missing evidence")
    func interruptionIsTerminalEvidence() throws {
        var session = AccelerationEvidenceSession(policy: try policy())
        _ = session.record(try sample(
            metersPerSecond: 0,
            uptimeNanoseconds: 1_000_000_000
        ))
        _ = session.record(try sample(
            metersPerSecond: 4,
            uptimeNanoseconds: 1_200_000_000
        ))

        session.interrupt(.vehicleConnectionLost)
        let snapshot = session.snapshot
        let readiness = snapshot.readiness()

        #expect(snapshot.continuityWasBroken)
        #expect(snapshot.knownObservationInterruptionCount == 1)
        #expect(readiness.failures.contains(.knownObservationInterruption(count: 1)))
        #expect(readiness.failures.contains(.runInvalidated(
            .interruption(.vehicleConnectionLost)
        )))
        #expect(session.record(try sample(
            metersPerSecond: 8,
            uptimeNanoseconds: 1_400_000_000
        )) == .ignoredAfterTerminalEvidence)
    }

    @Test("accepted timing evidence cannot bridge a configured cadence gap")
    func weakCadenceInvalidatesRun() throws {
        var session = AccelerationEvidenceSession(policy: try policy(
            maximumSampleIntervalNanoseconds: 250_000_000
        ))
        _ = session.record(try sample(
            metersPerSecond: 0,
            uptimeNanoseconds: 1_000_000_000
        ))
        _ = session.record(try sample(
            metersPerSecond: 4,
            uptimeNanoseconds: 1_400_000_000
        ))

        let readiness = session.snapshot.readiness()
        #expect(!readiness.isReady)
        #expect(readiness.result == nil)
        #expect(readiness.failures.contains(.runInvalidated(.measurementGapExceeded)))
    }

    @Test("a benchmark-rejected selected sample can never become reportable run evidence")
    func benchmarkRejectionBlocksReadiness() throws {
        var session = AccelerationEvidenceSession(policy: try policy())
        _ = session.record(try sample(
            metersPerSecond: 0,
            uptimeNanoseconds: 1_000_000_000
        ))
        let overflowKPH = Double.greatestFiniteMagnitude / 2
        let record = session.record(try sample(
            metersPerSecond: overflowKPH,
            uptimeNanoseconds: 1_200_000_000
        ))

        guard case .processed(.rejected(.nonFiniteDerivedSpeed), .completed) = record else {
            Issue.record("Expected the timing evaluator to complete while the benchmark rejects its derived km/h evidence")
            return
        }

        let readiness = session.snapshot.readiness()
        #expect(!readiness.isReady)
        #expect(readiness.result != nil)
        #expect(readiness.failures.contains(.selectedSourceBenchmarkRejectedSamples(count: 1)))
    }

    @Test("operator cancellation is terminal even before the first sample")
    func cancellationCannotBeResetInsideOneSession() throws {
        var session = AccelerationEvidenceSession(policy: try policy())
        session.interrupt(.operatorCancelled)

        #expect(session.state == .invalidated(.interruption(.operatorCancelled)))
        #expect(session.record(try sample(
            metersPerSecond: 0,
            uptimeNanoseconds: 1_000_000_000
        )) == .ignoredAfterTerminalEvidence)
        #expect(session.snapshot.telemetryBenchmark.acceptedSampleCount == 0)
    }
}
