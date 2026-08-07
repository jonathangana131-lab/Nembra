import Foundation
import Testing
@testable import NembraCore

@Suite("Acceleration application attempt ownership")
struct AccelerationAttemptOwnerTests {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private func policy(
        source: SpeedTelemetrySource = .scooterBluetooth,
        maximumSpeedAccuracyMetersPerSecond: Double? = nil
    ) throws -> AccelerationEvidenceSessionPolicy {
        let run = try AccelerationRunPolicy(
            targetMetersPerSecond: 10,
            stationaryMaximumMetersPerSecond: 0.25,
            requiredSource: source,
            maximumSpeedAccuracyMetersPerSecond: maximumSpeedAccuracyMetersPerSecond,
            maximumSampleIntervalNanoseconds: 300_000_000
        )
        let telemetry = try SpeedTelemetryQualityPolicy(
            requiredSource: source,
            minimumAcceptedSampleCount: 4,
            maximumRejectedSampleFraction: 0,
            maximumMeanIntervalMilliseconds: 300,
            maximumObservedIntervalMilliseconds: 300,
            maximumJitterStandardDeviationMilliseconds: 300,
            minimumDeliveryLatencySampleFraction: source == .gps ? 1 : nil,
            maximumMeanDeliveryLatencyMilliseconds: source == .gps ? 150 : nil,
            maximumEmpiricalSpeedStepKilometersPerHour: 20
        )
        return try AccelerationEvidenceSessionPolicy(run: run, telemetry: telemetry)
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
            provenance: .absoluteMeasurement,
            metersPerSecond: metersPerSecond,
            receivedAtUptimeNanoseconds: uptimeNanoseconds,
            receivedAtDate: receivedAtDate,
            measurementDate: measurementDate,
            speedAccuracyMetersPerSecond: speedAccuracyMetersPerSecond
        )
    }

    @Test("a mutable attempt must terminate before a replacement can begin")
    func activeAttemptCannotBeSilentlyReplaced() throws {
        var owner = AccelerationAttemptOwner()
        let first = try owner.begin(
            policy: policy(),
            startedAtUptimeNanoseconds: 1_000
        )

        #expect(throws: AccelerationAttemptOwnerError.attemptStillActive(first)) {
            _ = try owner.begin(
                policy: policy(),
                startedAtUptimeNanoseconds: 2_000
            )
        }

        let cancellation = owner.interrupt(.operatorCancelled, for: first)
        #expect(cancellation == .applied(
            runState: .invalidated(.interruption(.operatorCancelled))
        ))

        let second = try owner.begin(
            policy: policy(),
            startedAtUptimeNanoseconds: 3_000
        )
        #expect(second.rawValue == first.rawValue + 1)
        #expect(owner.currentGeneration == second)
    }

    @Test("queued evidence at or before the attempt fence cannot arm a fresh attempt")
    func monotonicStartFenceRejectsAmbiguousSamples() throws {
        var owner = AccelerationAttemptOwner()
        let generation = try owner.begin(
            policy: policy(),
            startedAtUptimeNanoseconds: 1_000
        )

        let queuedBefore = try sample(metersPerSecond: 0, uptimeNanoseconds: 999)
        let beforeResult = owner.record(queuedBefore, for: generation)
        #expect(beforeResult == .ignoredAtOrBeforeAttemptStart(
            startedAt: 1_000,
            sampleAt: 999
        ))

        let ambiguousEquality = try sample(metersPerSecond: 0, uptimeNanoseconds: 1_000)
        let equalityResult = owner.record(ambiguousEquality, for: generation)
        #expect(equalityResult == .ignoredAtOrBeforeAttemptStart(
            startedAt: 1_000,
            sampleAt: 1_000
        ))
        #expect(owner.currentSnapshot?.evidence.runState == .waitingForStandstill)

        let firstInAttempt = try sample(metersPerSecond: 0, uptimeNanoseconds: 1_001)
        let firstResult = owner.record(firstInAttempt, for: generation)
        #expect(firstResult == .session(
            .processed(runState: .armed(source: .scooterBluetooth))
        ))
    }

    @Test("delayed callbacks from an older generation cannot mutate its replacement")
    func staleGenerationCannotCrossAttemptBoundary() throws {
        var owner = AccelerationAttemptOwner()
        let first = try owner.begin(
            policy: policy(),
            startedAtUptimeNanoseconds: 1_000
        )
        _ = owner.interrupt(.operatorCancelled, for: first)
        let second = try owner.begin(
            policy: policy(),
            startedAtUptimeNanoseconds: 2_000
        )

        let delayed = try sample(metersPerSecond: 0, uptimeNanoseconds: 3_000)
        let delayedRecordResult = owner.record(delayed, for: first)
        #expect(delayedRecordResult == .ignoredStaleGeneration(
            expected: second,
            actual: first
        ))

        let delayedInterruptionResult = owner.interrupt(.vehicleConnectionLost, for: first)
        #expect(delayedInterruptionResult == .ignoredStaleGeneration(
            expected: second,
            actual: first
        ))
        #expect(owner.currentSnapshot?.evidence.runState == .waitingForStandstill)
        #expect(owner.currentGeneration == second)
    }

    @Test("attempt start timestamps cannot move backward inside one owner")
    func attemptStartChronologyFailsClosed() throws {
        var owner = AccelerationAttemptOwner()
        let first = try owner.begin(
            policy: policy(),
            startedAtUptimeNanoseconds: 10_000
        )
        _ = owner.interrupt(.operatorCancelled, for: first)

        #expect(throws: AccelerationAttemptOwnerError.nonMonotonicAttemptStart(
            previous: 10_000,
            proposed: 10_000
        )) {
            _ = try owner.begin(
                policy: policy(),
                startedAtUptimeNanoseconds: 10_000
            )
        }
        #expect(throws: AccelerationAttemptOwnerError.nonMonotonicAttemptStart(
            previous: 10_000,
            proposed: 9_999
        )) {
            _ = try owner.begin(
                policy: policy(),
                startedAtUptimeNanoseconds: 9_999
            )
        }
    }

    @Test("the owner preserves same-trace readiness through a completed attempt")
    func completedAttemptSurfacesSessionReadiness() throws {
        var owner = AccelerationAttemptOwner()
        let generation = try owner.begin(
            policy: policy(),
            startedAtUptimeNanoseconds: 900_000_000
        )

        for evidence in try [
            sample(metersPerSecond: 0, uptimeNanoseconds: 1_000_000_000),
            sample(metersPerSecond: 4, uptimeNanoseconds: 1_200_000_000),
            sample(metersPerSecond: 8, uptimeNanoseconds: 1_400_000_000),
            sample(metersPerSecond: 10, uptimeNanoseconds: 1_600_000_000)
        ] {
            _ = owner.record(evidence, for: generation)
        }

        let snapshot = try #require(owner.currentSnapshot)
        let result = try #require(snapshot.readiness.result)
        #expect(snapshot.isTerminal)
        #expect(snapshot.readiness.isReady)
        #expect(result.source == .scooterBluetooth)
        #expect(abs(result.stationaryToTargetObservationElapsedSeconds - 0.6) < 0.000_001)

        let later = try sample(metersPerSecond: 11, uptimeNanoseconds: 1_800_000_000)
        let laterResult = owner.record(later, for: generation)
        #expect(laterResult == .session(.ignoredAfterTerminalEvidence))
        #expect(owner.currentSnapshot == snapshot)
    }

    @Test("a selected-source interruption is terminal even if accuracy rejected the first GPS sample")
    func rejectedGPSObservationStillProtectsContinuity() throws {
        var owner = AccelerationAttemptOwner()
        let first = try owner.begin(
            policy: policy(
                source: .gps,
                maximumSpeedAccuracyMetersPerSecond: 1
            ),
            startedAtUptimeNanoseconds: 1_000_000_000
        )

        let poorAccuracy = try sample(
            source: .gps,
            metersPerSecond: 0,
            uptimeNanoseconds: 1_100_000_000,
            speedAccuracyMetersPerSecond: 5,
            deliveryLatencyMilliseconds: 20
        )
        let recordResult = owner.record(poorAccuracy, for: first)
        #expect(recordResult == .session(
            .processed(runState: .waitingForStandstill)
        ))

        let interruptionResult = owner.interrupt(.vehicleConnectionLost, for: first)
        #expect(interruptionResult == .applied(
            runState: .waitingForStandstill
        ))

        let interrupted = try #require(owner.currentSnapshot)
        #expect(interrupted.isTerminal)
        #expect(interrupted.evidence.continuityWasBroken)
        #expect(interrupted.evidence.knownObservationInterruptionCount == 1)
        #expect(interrupted.readiness.failures.contains(.knownObservationInterruption(count: 1)))

        let second = try owner.begin(
            policy: policy(),
            startedAtUptimeNanoseconds: 1_200_000_000
        )
        #expect(second > first)
    }

    @Test("same-generation lifecycle callbacks cannot rewrite terminal evidence")
    func terminalAttemptIgnoresLateInterruption() throws {
        var owner = AccelerationAttemptOwner()
        let generation = try owner.begin(
            policy: policy(),
            startedAtUptimeNanoseconds: 1_000
        )
        _ = owner.interrupt(.operatorCancelled, for: generation)
        let terminal = try #require(owner.currentSnapshot)

        let lateInterruption = owner.interrupt(.applicationLifecycleInterrupted, for: generation)
        #expect(lateInterruption == .ignoredAfterTerminalEvidence)
        #expect(owner.currentSnapshot == terminal)
    }
}
