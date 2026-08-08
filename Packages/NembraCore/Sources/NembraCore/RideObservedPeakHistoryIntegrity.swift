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
                  Self.populationMomentsArePossible(
                    count: intervalCount,
                    mean: mean,
                    minimum: minimum,
                    maximum: maximum,
                    standardDeviation: jitter
                  ) else {
                throw RideObservedPeakHistoryEvidenceError.invalidBenchmark
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
                  Self.populationMomentsArePossible(
                    count: deliveryLatencySampleCount,
                    mean: mean,
                    minimum: minimum,
                    maximum: maximum,
                    standardDeviation: deviation
                  ) else {
                throw RideObservedPeakHistoryEvidenceError.invalidBenchmark
            }
        }
    }

    /// JSON round-trips and mathematically equivalent online reductions can differ
    /// by a few floating-point ulps. The tolerance is deliberately tiny relative to
    /// the value (1e-9) with a 1e-9 absolute floor: enough for representation noise,
    /// far too small to turn a policy-failing durable statistic into a passing one.
    private static func approximatelyEqual(_ lhs: Double, _ rhs: Double) -> Bool {
        guard lhs.isFinite, rhs.isFinite else { return false }
        return abs(lhs - rhs) <= tolerance(lhs, rhs)
    }

    private static func tolerance(_ values: Double...) -> Double {
        let scale = values.reduce(1.0) { max($0, abs($1)) }
        return max(1e-9, scale * 1e-9)
    }

    /// Validates population moments using facts guaranteed by `RunningMoments`:
    /// `minimum` and `maximum` are actual attained extrema, `mean` is the population
    /// mean, and `standardDeviation` is the population SD.
    ///
    /// Upper bound: Bhatia-Davis gives variance <= (max-mean)(mean-min), which is
    /// at least as strong as Popoviciu's range^2/4 bound and uses the retained mean.
    ///
    /// Lower bound: because both extrema were actually observed, fix one sample at
    /// min and one at max. For n>2 the remaining samples minimize variance when
    /// they are all equal to the mean required by the retained total. If that
    /// remaining value would lie outside [min,max], the moments are impossible.
    /// For n=2 this collapses to the exact identities mean=(min+max)/2 and
    /// populationSD=(max-min)/2.
    private static func populationMomentsArePossible(
        count: Int,
        mean: Double,
        minimum: Double,
        maximum: Double,
        standardDeviation: Double
    ) -> Bool {
        guard count > 0,
              mean.isFinite,
              minimum.isFinite,
              maximum.isFinite,
              standardDeviation.isFinite,
              standardDeviation >= 0,
              minimum <= mean,
              mean <= maximum else {
            return false
        }

        if count == 1 {
            return approximatelyEqual(minimum, mean)
                && approximatelyEqual(maximum, mean)
                && approximatelyEqual(standardDeviation, 0)
        }

        let belowMean = mean - minimum
        let aboveMean = maximum - mean
        guard belowMean.isFinite, aboveMean.isFinite else { return false }

        if count == 2 {
            guard approximatelyEqual(belowMean, aboveMean) else { return false }
            let expectedDeviation = (maximum - minimum) / 2
            return expectedDeviation.isFinite
                && approximatelyEqual(standardDeviation, expectedDeviation)
        }

        let remainingCount = Double(count - 2)
        let remainingDelta = (belowMean - aboveMean) / remainingCount
        guard remainingDelta.isFinite else { return false }

        let feasibilityTolerance = tolerance(belowMean, aboveMean, remainingDelta)
        guard remainingDelta >= -belowMean - feasibilityTolerance,
              remainingDelta <= aboveMean + feasibilityTolerance else {
            return false
        }

        let minimumVarianceNumerator =
            belowMean * belowMean
            + aboveMean * aboveMean
            + remainingCount * remainingDelta * remainingDelta
        let minimumVariance = minimumVarianceNumerator / Double(count)
        let maximumVariance = belowMean * aboveMean
        guard minimumVariance.isFinite,
              maximumVariance.isFinite,
              minimumVariance >= 0,
              maximumVariance >= 0 else {
            return false
        }

        let minimumDeviation = sqrt(minimumVariance)
        let maximumDeviation = sqrt(maximumVariance)
        guard minimumDeviation.isFinite, maximumDeviation.isFinite else { return false }

        let deviationTolerance = tolerance(
            standardDeviation,
            minimumDeviation,
            maximumDeviation
        )
        return standardDeviation >= minimumDeviation - deviationTolerance
            && standardDeviation <= maximumDeviation + deviationTolerance
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
