import Foundation

public enum RideAverageSpeedStatisticsPresentationError: Error, Equatable, Sendable {
    case invalidSummary
}

/// Product-facing disclosure state for elapsed completed-ride average-speed statistics.
///
/// A partial state may carry a real weighted average over the selected rides with complete paired
/// distance + monotonic-duration evidence. It must never be presented as the average for every ride
/// in the selected period while other selected rides are excluded.
public enum RideAverageSpeedStatisticsPresentationState: String, Codable, Equatable, Sendable {
    /// The selected period contains no completed rides.
    case noCompletedRides
    /// Completed rides exist, but none has complete paired distance + elapsed-duration evidence.
    case averageUnavailable
    /// A real elapsed-ride average exists for a trustworthy subset of the selected rides.
    case partialPairedEvidence
    /// Every selected ride contributes complete paired distance + elapsed-duration evidence.
    case completePairedEvidence
}

/// Stable UI/accessibility projection of `RideAverageSpeedStatisticsSummary`.
///
/// This projection deliberately names the value an **elapsed-ride average**. It does not imply moving
/// speed, mean telemetry-sample speed, uninterrupted scooter connectivity, or physical top speed.
public struct RideAverageSpeedStatisticsPresentation: Equatable, Sendable {
    public let period: RideStatisticsPeriod
    public let state: RideAverageSpeedStatisticsPresentationState

    public let rideCount: Int
    public let ridesSupportingAverage: Int
    public let ridesExcludedForDistanceEvidence: Int
    public let ridesExcludedForDurationEvidence: Int
    public let ridesExcludedForZeroDuration: Int
    public let ridesExcludedForMultipleEvidenceReasons: Int

    /// Weighted elapsed-ride average over exactly the supporting rides.
    ///
    /// In `.partialPairedEvidence`, this number remains legitimate but describes only the trustworthy
    /// subset and therefore requires explicit incomplete-evidence disclosure.
    public let averageElapsedRideSpeedMetersPerSecond: Double?
    /// Reconciled distance represented by exactly the rides supporting the numeric average.
    public let supportingDistanceMeters: Double?
    /// Complete monotonic elapsed duration represented by exactly the rides supporting the numeric average.
    public let supportingObservedDurationNanoseconds: UInt64?

    /// True only when every selected ride supports the numeric elapsed-ride average.
    public let permitsCompletePeriodAverageWording: Bool
    /// True only when a real numeric average is exposed for an incomplete selected-period subset.
    public let requiresIncompleteEvidenceDisclosure: Bool

    fileprivate init(
        period: RideStatisticsPeriod,
        state: RideAverageSpeedStatisticsPresentationState,
        rideCount: Int,
        ridesSupportingAverage: Int,
        ridesExcludedForDistanceEvidence: Int,
        ridesExcludedForDurationEvidence: Int,
        ridesExcludedForZeroDuration: Int,
        ridesExcludedForMultipleEvidenceReasons: Int,
        averageElapsedRideSpeedMetersPerSecond: Double?,
        supportingDistanceMeters: Double?,
        supportingObservedDurationNanoseconds: UInt64?,
        permitsCompletePeriodAverageWording: Bool,
        requiresIncompleteEvidenceDisclosure: Bool
    ) {
        self.period = period
        self.state = state
        self.rideCount = rideCount
        self.ridesSupportingAverage = ridesSupportingAverage
        self.ridesExcludedForDistanceEvidence = ridesExcludedForDistanceEvidence
        self.ridesExcludedForDurationEvidence = ridesExcludedForDurationEvidence
        self.ridesExcludedForZeroDuration = ridesExcludedForZeroDuration
        self.ridesExcludedForMultipleEvidenceReasons = ridesExcludedForMultipleEvidenceReasons
        self.averageElapsedRideSpeedMetersPerSecond = averageElapsedRideSpeedMetersPerSecond
        self.supportingDistanceMeters = supportingDistanceMeters
        self.supportingObservedDurationNanoseconds = supportingObservedDurationNanoseconds
        self.permitsCompletePeriodAverageWording = permitsCompletePeriodAverageWording
        self.requiresIncompleteEvidenceDisclosure = requiresIncompleteEvidenceDisclosure
    }
}

public enum RideAverageSpeedStatisticsPresenter {
    /// Converts paired average-speed statistics into a disclosure-safe product projection.
    ///
    /// The domain aggregator already produces internally consistent summaries, but this boundary
    /// deliberately revalidates cross-field invariants before any UI can attach confident wording.
    public static func present(
        _ summary: RideAverageSpeedStatisticsSummary
    ) throws -> RideAverageSpeedStatisticsPresentation {
        guard summary.rideCount >= 0,
              summary.includedRideCount >= 0,
              summary.excludedDistanceRideCount >= 0,
              summary.excludedDurationRideCount >= 0,
              summary.excludedZeroDurationRideCount >= 0,
              summary.excludedMultipleEvidenceRideCount >= 0 else {
            throw RideAverageSpeedStatisticsPresentationError.invalidSummary
        }

        let firstExcluded = summary.excludedDistanceRideCount.addingReportingOverflow(
            summary.excludedDurationRideCount
        )
        let secondExcluded = firstExcluded.partialValue.addingReportingOverflow(
            summary.excludedZeroDurationRideCount
        )
        let excluded = secondExcluded.partialValue.addingReportingOverflow(
            summary.excludedMultipleEvidenceRideCount
        )
        let reconciledRideCount = summary.includedRideCount.addingReportingOverflow(
            excluded.partialValue
        )

        guard !firstExcluded.overflow,
              !secondExcluded.overflow,
              !excluded.overflow,
              !reconciledRideCount.overflow,
              reconciledRideCount.partialValue == summary.rideCount else {
            throw RideAverageSpeedStatisticsPresentationError.invalidSummary
        }

        let hasAverage = summary.averageElapsedRideSpeedMetersPerSecond != nil
        let hasDistance = summary.supportingDistanceMeters != nil
        let hasDuration = summary.supportingObservedDurationNanoseconds != nil
        guard hasAverage == hasDistance,
              hasAverage == hasDuration,
              hasAverage == (summary.includedRideCount > 0) else {
            throw RideAverageSpeedStatisticsPresentationError.invalidSummary
        }

        if let average = summary.averageElapsedRideSpeedMetersPerSecond,
           let distance = summary.supportingDistanceMeters,
           let duration = summary.supportingObservedDurationNanoseconds {
            guard average.isFinite,
                  average >= 0,
                  distance.isFinite,
                  distance >= 0,
                  duration > 0 else {
                throw RideAverageSpeedStatisticsPresentationError.invalidSummary
            }

            let seconds = Double(duration) / 1_000_000_000
            let expectedAverage = distance / seconds
            guard seconds.isFinite,
                  seconds > 0,
                  expectedAverage.isFinite,
                  expectedAverage >= 0,
                  expectedAverage == average else {
                throw RideAverageSpeedStatisticsPresentationError.invalidSummary
            }
        }

        let state: RideAverageSpeedStatisticsPresentationState
        switch summary.availability {
        case .noRides:
            guard summary.rideCount == 0,
                  summary.includedRideCount == 0,
                  excluded.partialValue == 0,
                  !hasAverage else {
                throw RideAverageSpeedStatisticsPresentationError.invalidSummary
            }
            state = .noCompletedRides

        case .unavailable:
            guard summary.rideCount > 0,
                  summary.includedRideCount == 0,
                  excluded.partialValue == summary.rideCount,
                  !hasAverage else {
                throw RideAverageSpeedStatisticsPresentationError.invalidSummary
            }
            state = .averageUnavailable

        case .partial:
            guard summary.rideCount > 0,
                  summary.includedRideCount > 0,
                  summary.includedRideCount < summary.rideCount,
                  excluded.partialValue > 0,
                  hasAverage else {
                throw RideAverageSpeedStatisticsPresentationError.invalidSummary
            }
            state = .partialPairedEvidence

        case .complete:
            guard summary.rideCount > 0,
                  summary.includedRideCount == summary.rideCount,
                  excluded.partialValue == 0,
                  hasAverage else {
                throw RideAverageSpeedStatisticsPresentationError.invalidSummary
            }
            state = .completePairedEvidence
        }

        let permitsCompleteWording = state == .completePairedEvidence
        let requiresIncompleteDisclosure = state == .partialPairedEvidence
        guard summary.permitsCompletePeriodAverageWording == permitsCompleteWording,
              summary.requiresIncompleteEvidenceDisclosure == requiresIncompleteDisclosure else {
            throw RideAverageSpeedStatisticsPresentationError.invalidSummary
        }

        return RideAverageSpeedStatisticsPresentation(
            period: summary.period,
            state: state,
            rideCount: summary.rideCount,
            ridesSupportingAverage: summary.includedRideCount,
            ridesExcludedForDistanceEvidence: summary.excludedDistanceRideCount,
            ridesExcludedForDurationEvidence: summary.excludedDurationRideCount,
            ridesExcludedForZeroDuration: summary.excludedZeroDurationRideCount,
            ridesExcludedForMultipleEvidenceReasons: summary.excludedMultipleEvidenceRideCount,
            averageElapsedRideSpeedMetersPerSecond: summary.averageElapsedRideSpeedMetersPerSecond,
            supportingDistanceMeters: summary.supportingDistanceMeters,
            supportingObservedDurationNanoseconds: summary.supportingObservedDurationNanoseconds,
            permitsCompletePeriodAverageWording: permitsCompleteWording,
            requiresIncompleteEvidenceDisclosure: requiresIncompleteDisclosure
        )
    }
}
