import Foundation

extension RideObservedPeakHistoryRejections {
    /// Foreign callbacks are rejected before selected-source peak-quality policy.
    package var foreignRejectedSampleCount: Int {
        nonAuthoritativeSampleCount + sourceMismatchSampleCount
    }

    /// Matches `PeakSpeedEvidence.qualityRejectedSampleCount` exactly.
    package var selectedSourceQualityRejectedSampleCount: Int {
        nonIncreasingTimestampCount
            + nonFiniteDerivedSpeedCount
            + speedAccuracyUnavailableCount
            + speedAccuracyExceededCount
    }

    /// Matches the raw telemetry benchmark's rejection categories exactly.
    package var benchmarkRejectedSampleCount: Int {
        foreignRejectedSampleCount
            + nonIncreasingTimestampCount
            + nonFiniteDerivedSpeedCount
    }

    /// Peak-only GPS/source-accuracy gating happens after raw benchmark admission.
    package var peakAccuracyRejectedSampleCount: Int {
        speedAccuracyUnavailableCount + speedAccuracyExceededCount
    }
}

extension RideObservedPeakHistoryBenchmark {
    /// Revalidates algebra/topology that `TelemetryBenchmarkCollector` guarantees
    /// but the stored aggregate cannot express through type shape alone.
    package func validateDurableIntegrity() throws {
        if acceptedSampleCount > 0 {
            let precedingSegments = observationSegmentCount - 1
            guard knownObservationInterruptionCount == precedingSegments
                    || knownObservationInterruptionCount == observationSegmentCount else {
                throw RideObservedPeakHistoryEvidenceError.invalidBenchmark
            }
        }

        if intervalCount > 0 {
            guard let rate = effectiveSampleRateHertz,
                  let mean = meanIntervalMilliseconds,
                  let minimum = minimumIntervalMilliseconds,
                  let maximum = maximumIntervalMilliseconds,
                  let jitter = intervalJitterStandardDeviationMilliseconds else {
                throw RideObservedPeakHistoryEvidenceError.invalidBenchmark
            }

            let expectedMeanMilliseconds =
                observedDurationSeconds * 1_000 / Double(intervalCount)
            let expectedRateHertz = Double(intervalCount) / observedDurationSeconds
            guard Self.approximatelyEqual(mean, expectedMeanMilliseconds),
                  Self.approximatelyEqual(rate, expectedRateHertz),
                  Self.standardDeviationIsPossible(
                    jitter,
                    minimum: minimum,
                    maximum: maximum
                  ) else {
                throw RideObservedPeakHistoryEvidenceError.invalidBenchmark
            }

            if intervalCount == 1 {
                guard Self.approximatelyEqual(minimum, mean),
                      Self.approximatelyEqual(maximum, mean),
                      Self.approximatelyEqual(jitter, 0) else {
                    throw RideObservedPeakHistoryEvidenceError.invalidBenchmark
                }
            }
        }

        let everyIntervalIsDuplicate = duplicateSpeedValueCount == intervalCount
        guard (empiricalMinimumNonzeroSpeedStepKilometersPerHour == nil)
                == everyIntervalIsDuplicate else {
            throw RideObservedPeakHistoryEvidenceError.invalidBenchmark
        }

        if deliveryLatencySampleCount > 0 {
            guard let mean = meanDeliveryLatencyMilliseconds,
                  let minimum = minimumDeliveryLatencyMilliseconds,
                  let maximum = maximumDeliveryLatencyMilliseconds,
                  let deviation = deliveryLatencyStandardDeviationMilliseconds,
                  Self.standardDeviationIsPossible(
                    deviation,
                    minimum: minimum,
                    maximum: maximum
                  ) else {
                throw RideObservedPeakHistoryEvidenceError.invalidBenchmark
            }

            if deliveryLatencySampleCount == 1 {
                guard Self.approximatelyEqual(minimum, mean),
                      Self.approximatelyEqual(maximum, mean),
                      Self.approximatelyEqual(deviation, 0) else {
                    throw RideObservedPeakHistoryEvidenceError.invalidBenchmark
                }
            }
        }
    }

    /// JSON round-trips and the two mathematically equivalent online reductions
    /// can differ by a few floating-point ulps. This tolerance is deliberately
    /// tiny relative to the value (1e-9) with a 1e-9 absolute floor; it is large
    /// enough for representation noise and far too small to turn a policy-failing
    /// interval/rate into a policy-passing one.
    private static func approximatelyEqual(_ lhs: Double, _ rhs: Double) -> Bool {
        guard lhs.isFinite, rhs.isFinite else { return false }
        let scale = max(max(abs(lhs), abs(rhs)), 1)
        return abs(lhs - rhs) <= max(1e-9, scale * 1e-9)
    }

    private static func standardDeviationIsPossible(
        _ deviation: Double,
        minimum: Double,
        maximum: Double
    ) -> Bool {
        let range = maximum - minimum
        guard range.isFinite, range >= 0 else { return false }
        return deviation <= range + max(1e-9, max(abs(range), 1) * 1e-9)
    }
}

package enum RideObservedPeakHistoryIntegrity {
    package static func validate(
        beganAfterKnownObservationGap: Bool,
        knownSelectedSourceInterruptionCount: Int,
        foreignSourceCallbackCount: Int,
        peakRejections: RideObservedPeakHistoryRejections,
        completedPeak: CompletedRidePeakSpeedEvidence?,
        telemetryBenchmark: RideObservedPeakHistoryBenchmark
    ) throws {
        try telemetryBenchmark.validateDurableIntegrity()

        guard foreignSourceCallbackCount == peakRejections.foreignRejectedSampleCount,
              telemetryBenchmark.rejectedSampleCount == peakRejections.benchmarkRejectedSampleCount else {
            throw RideObservedPeakHistoryEvidenceError.evidenceMismatch
        }

        guard knownSelectedSourceInterruptionCount >= telemetryBenchmark.knownObservationInterruptionCount else {
            throw RideObservedPeakHistoryEvidenceError.evidenceMismatch
        }
        let preBenchmarkInterruptionCount =
            knownSelectedSourceInterruptionCount - telemetryBenchmark.knownObservationInterruptionCount
        guard preBenchmarkInterruptionCount <= 1,
              !beganAfterKnownObservationGap || preBenchmarkInterruptionCount == 1 else {
            throw RideObservedPeakHistoryEvidenceError.evidenceMismatch
        }

        let accuracyRejectedCount = peakRejections.peakAccuracyRejectedSampleCount
        if let completedPeak {
            guard completedPeak.qualityRejectedSampleCount
                    == peakRejections.selectedSourceQualityRejectedSampleCount else {
                throw RideObservedPeakHistoryEvidenceError.evidenceMismatch
            }

            if completedPeak.maximumAllowedSpeedAccuracyMetersPerSecond == nil,
               accuracyRejectedCount != 0 {
                throw RideObservedPeakHistoryEvidenceError.evidenceMismatch
            }

            let expectedBenchmarkAccepted = try sum(
                completedPeak.acceptedSampleCount,
                accuracyRejectedCount
            )
            guard telemetryBenchmark.acceptedSampleCount == expectedBenchmarkAccepted else {
                throw RideObservedPeakHistoryEvidenceError.evidenceMismatch
            }
        } else {
            // Any selected-source sample admitted by the peak accumulator would
            // establish a peak. With no completed peak, every raw benchmark
            // acceptance must therefore be explained by the stricter accuracy gate.
            guard telemetryBenchmark.acceptedSampleCount == accuracyRejectedCount else {
                throw RideObservedPeakHistoryEvidenceError.evidenceMismatch
            }
        }
    }

    private static func sum(_ lhs: Int, _ rhs: Int) throws -> Int {
        let result = lhs.addingReportingOverflow(rhs)
        guard !result.overflow else {
            throw RideObservedPeakHistoryEvidenceError.invalidCount
        }
        return result.partialValue
    }
}
