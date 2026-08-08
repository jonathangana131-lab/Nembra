/// Fail-closed product projection errors for completed-ride duration statistics.
public enum RideDurationStatisticsPresentationError: Error, Equatable, Sendable {
    case invalidSummary
}

/// Product-facing disclosure state for observed completed-ride duration statistics.
///
/// A partial state carries only the monotonic elapsed time Nembra actually observed.
/// Missing observation intervals are never converted into zero time and calendar dates
/// are never subtracted to fill gaps.
public enum RideDurationStatisticsPresentationState: String, Equatable, Sendable {
    /// The selected period contains no completed rides.
    case noCompletedRides
    /// Completed rides exist, but none has accepted monotonic duration evidence.
    case durationUnavailable
    /// A real observed-duration subtotal exists, but at least one selected ride is
    /// unavailable or has only partial observation coverage.
    case partialObservedDuration
    /// Every selected ride has complete accepted monotonic duration coverage.
    case completeObservedDuration
}

/// Stable UI/accessibility projection of `RideDurationStatisticsSummary`.
///
/// The projection intentionally exposes an observed subtotal rather than generic
/// "ride time". Even complete duration coverage is elapsed session duration, not an
/// assertion of moving time, motor-on time, or physical scooter telemetry.
public struct RideDurationStatisticsPresentation: Equatable, Sendable {
    public let period: RideStatisticsPeriod
    public let state: RideDurationStatisticsPresentationState

    public let rideCount: Int
    public let ridesWithObservedDuration: Int
    public let ridesWithCompleteDurationCoverage: Int
    public let ridesWithPartialDurationCoverage: Int
    public let ridesWithoutObservedDuration: Int

    /// Sum of accepted monotonic duration observations represented by the selected
    /// rides. In `.partialObservedDuration` this is a known subtotal only.
    ///
    /// Legitimate zero remains zero; absence of evidence is represented by nil.
    public let totalObservedDurationNanoseconds: UInt64?

    /// True only when every selected ride has complete accepted duration coverage.
    /// A consumer may then describe the value as complete *observed duration* for
    /// the selected completed rides, never as moving time or an inferred wall-clock total.
    public let permitsCompletePeriodObservedDurationWording: Bool

    /// True only when a numeric observed subtotal is present but incomplete. The UI
    /// must qualify that subtotal rather than presenting it as total period ride time.
    /// `.durationUnavailable` has no numeric subtotal and is already explicit through
    /// its state, so this flag intentionally remains false there.
    public let requiresIncompleteDurationDisclosure: Bool

    fileprivate init(
        period: RideStatisticsPeriod,
        state: RideDurationStatisticsPresentationState,
        rideCount: Int,
        ridesWithObservedDuration: Int,
        ridesWithCompleteDurationCoverage: Int,
        ridesWithPartialDurationCoverage: Int,
        ridesWithoutObservedDuration: Int,
        totalObservedDurationNanoseconds: UInt64?,
        permitsCompletePeriodObservedDurationWording: Bool,
        requiresIncompleteDurationDisclosure: Bool
    ) {
        self.period = period
        self.state = state
        self.rideCount = rideCount
        self.ridesWithObservedDuration = ridesWithObservedDuration
        self.ridesWithCompleteDurationCoverage = ridesWithCompleteDurationCoverage
        self.ridesWithPartialDurationCoverage = ridesWithPartialDurationCoverage
        self.ridesWithoutObservedDuration = ridesWithoutObservedDuration
        self.totalObservedDurationNanoseconds = totalObservedDurationNanoseconds
        self.permitsCompletePeriodObservedDurationWording = permitsCompletePeriodObservedDurationWording
        self.requiresIncompleteDurationDisclosure = requiresIncompleteDurationDisclosure
    }
}

public enum RideDurationStatisticsPresenter {
    /// Converts duration statistics into a disclosure-safe product projection.
    ///
    /// `RideDurationStatisticsAggregator` already emits internally consistent summaries,
    /// but this boundary deliberately revalidates the cross-field invariants so a future
    /// persistence or app adapter cannot turn malformed counts/availability into confident UI.
    public static func present(
        _ summary: RideDurationStatisticsSummary
    ) throws -> RideDurationStatisticsPresentation {
        guard summary.rideCount >= 0,
              summary.completeCoverageRideCount >= 0,
              summary.partialCoverageRideCount >= 0,
              summary.unavailableDurationRideCount >= 0 else {
            throw RideDurationStatisticsPresentationError.invalidSummary
        }

        let observedCount = summary.completeCoverageRideCount.addingReportingOverflow(
            summary.partialCoverageRideCount
        )
        guard !observedCount.overflow else {
            throw RideDurationStatisticsPresentationError.invalidSummary
        }

        let reconciledRideCount = observedCount.partialValue.addingReportingOverflow(
            summary.unavailableDurationRideCount
        )
        guard !reconciledRideCount.overflow,
              reconciledRideCount.partialValue == summary.rideCount else {
            throw RideDurationStatisticsPresentationError.invalidSummary
        }

        let hasObservedSubtotal = summary.totalObservedDurationNanoseconds != nil
        guard hasObservedSubtotal == (observedCount.partialValue > 0) else {
            throw RideDurationStatisticsPresentationError.invalidSummary
        }

        let state: RideDurationStatisticsPresentationState
        switch summary.durationAvailability {
        case .noRides:
            guard summary.rideCount == 0,
                  summary.completeCoverageRideCount == 0,
                  summary.partialCoverageRideCount == 0,
                  summary.unavailableDurationRideCount == 0,
                  !hasObservedSubtotal else {
                throw RideDurationStatisticsPresentationError.invalidSummary
            }
            state = .noCompletedRides

        case .unavailable:
            guard summary.rideCount > 0,
                  observedCount.partialValue == 0,
                  summary.unavailableDurationRideCount == summary.rideCount,
                  !hasObservedSubtotal else {
                throw RideDurationStatisticsPresentationError.invalidSummary
            }
            state = .durationUnavailable

        case .partial:
            guard summary.rideCount > 0,
                  observedCount.partialValue > 0,
                  summary.completeCoverageRideCount < summary.rideCount,
                  hasObservedSubtotal else {
                throw RideDurationStatisticsPresentationError.invalidSummary
            }
            state = .partialObservedDuration

        case .complete:
            guard summary.rideCount > 0,
                  summary.completeCoverageRideCount == summary.rideCount,
                  summary.partialCoverageRideCount == 0,
                  summary.unavailableDurationRideCount == 0,
                  hasObservedSubtotal else {
                throw RideDurationStatisticsPresentationError.invalidSummary
            }
            state = .completeObservedDuration
        }

        return RideDurationStatisticsPresentation(
            period: summary.period,
            state: state,
            rideCount: summary.rideCount,
            ridesWithObservedDuration: observedCount.partialValue,
            ridesWithCompleteDurationCoverage: summary.completeCoverageRideCount,
            ridesWithPartialDurationCoverage: summary.partialCoverageRideCount,
            ridesWithoutObservedDuration: summary.unavailableDurationRideCount,
            totalObservedDurationNanoseconds: summary.totalObservedDurationNanoseconds,
            permitsCompletePeriodObservedDurationWording: state == .completeObservedDuration,
            requiresIncompleteDurationDisclosure: state == .partialObservedDuration
        )
    }
}