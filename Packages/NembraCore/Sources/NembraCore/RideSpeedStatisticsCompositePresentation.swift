import Foundation

/// Fail-closed composition errors for completed-ride speed statistics that are intended to appear
/// together in one product surface.
public enum RideSpeedStatisticsCompositePresentationError: Error, Equatable, Sendable {
    /// The independently prepared elapsed-average and observed-maximum inputs do not select the exact
    /// same completed-ride identities under the requested calendar period.
    case selectedRideScopeMismatch
    /// A component aggregator/presenter selected a different number of rides than the exact population
    /// reconstructed at this composition boundary.
    case selectedRideProjectionMismatch
}

/// One disclosure-safe product snapshot for elapsed completed-ride average speed and quality-qualified
/// observed maximum speed.
///
/// The component projections deliberately retain their independent evidence states. A complete
/// elapsed-average projection does not upgrade an unavailable or partial observed maximum, and vice
/// versa. This type adds one guarantee only: both components were produced for the exact same selected
/// `(sessionID, attributedDate)` population.
public struct RideSpeedStatisticsCompositePresentation: Equatable, Sendable {
    public let period: RideStatisticsPeriod
    public let rideCount: Int
    public let elapsedAverage: RideAverageSpeedStatisticsPresentation
    public let observedMaximum: RideObservedMaxSpeedStatisticsPresentation

    fileprivate init(
        period: RideStatisticsPeriod,
        rideCount: Int,
        elapsedAverage: RideAverageSpeedStatisticsPresentation,
        observedMaximum: RideObservedMaxSpeedStatisticsPresentation
    ) {
        self.period = period
        self.rideCount = rideCount
        self.elapsedAverage = elapsedAverage
        self.observedMaximum = observedMaximum
    }
}

/// Composes the two user-facing speed statistics without allowing equal period labels or equal counts
/// to masquerade as proof that they describe the same rides.
///
/// Passing already-built summaries would be insufficient: one caller could accidentally provide an
/// average from rides A+B and an observed maximum from rides C+D while both summaries still report the
/// same period and ride count. This producer therefore accepts each metric's prepared ride inputs,
/// delegates evidence validation/deduplication to the authoritative component aggregators, then verifies
/// exact selected population identity before exposing the projections together.
public enum RideSpeedStatisticsCompositePresenter {
    public static func present(
        period: RideStatisticsPeriod,
        averageSpeedRides: [RideAverageSpeedStatisticsRide],
        observedMaximumRides: [RideObservedMaxSpeedStatisticsRide],
        referenceDate: Date,
        calendar: Calendar
    ) throws -> RideSpeedStatisticsCompositePresentation {
        let averageSummary = try RideAverageSpeedStatisticsAggregator.summarize(
            period: period,
            rides: averageSpeedRides,
            referenceDate: referenceDate,
            calendar: calendar
        )
        let maximumSummary = try RideObservedMaxSpeedStatisticsAggregator.summarize(
            period: period,
            rides: observedMaximumRides,
            referenceDate: referenceDate,
            calendar: calendar
        )

        let averagePresentation = try RideAverageSpeedStatisticsPresenter.present(averageSummary)
        let maximumPresentation = try RideObservedMaxSpeedStatisticsPresenter.present(maximumSummary)

        let averageScope = try selectedScope(
            period: period,
            referenceDate: referenceDate,
            calendar: calendar,
            rides: averageSpeedRides,
            sessionID: { $0.sessionID },
            attributedDate: { $0.attributedDate }
        )
        let maximumScope = try selectedScope(
            period: period,
            referenceDate: referenceDate,
            calendar: calendar,
            rides: observedMaximumRides,
            sessionID: { $0.sessionID },
            attributedDate: { $0.attributedDate }
        )

        guard averageScope == maximumScope else {
            throw RideSpeedStatisticsCompositePresentationError.selectedRideScopeMismatch
        }

        let selectedRideCount = averageScope.count
        guard averagePresentation.period == period,
              maximumPresentation.period == period,
              averagePresentation.rideCount == selectedRideCount,
              maximumPresentation.rideCount == selectedRideCount else {
            throw RideSpeedStatisticsCompositePresentationError.selectedRideProjectionMismatch
        }

        return RideSpeedStatisticsCompositePresentation(
            period: period,
            rideCount: selectedRideCount,
            elapsedAverage: averagePresentation,
            observedMaximum: maximumPresentation
        )
    }

    private struct SelectedRideIdentity: Hashable {
        let sessionID: UUID
        let attributedDate: Date
    }

    private struct PeriodWindow {
        let interval: DateInterval?

        func contains(_ date: Date) -> Bool {
            guard let interval else { return true }
            return date >= interval.start && date < interval.end
        }
    }

    /// Reconstructs only the cross-metric population identity. Evidence eligibility, duplicate
    /// conflicts, continuity, quality policy, and numeric truth stay owned by the component producers.
    /// Final count reconciliation makes this helper fail closed if their future selection semantics
    /// diverge from this bounded-period projection.
    private static func selectedScope<R>(
        period: RideStatisticsPeriod,
        referenceDate: Date,
        calendar: Calendar,
        rides: [R],
        sessionID: (R) -> UUID,
        attributedDate: (R) -> Date
    ) throws -> Set<SelectedRideIdentity> {
        let window = try periodWindow(
            for: period,
            referenceDate: referenceDate,
            calendar: calendar
        )

        return Set(rides.lazy.compactMap { ride in
            let date = attributedDate(ride)
            guard window.contains(date) else { return nil }
            return SelectedRideIdentity(
                sessionID: sessionID(ride),
                attributedDate: date
            )
        })
    }

    private static func periodWindow(
        for period: RideStatisticsPeriod,
        referenceDate: Date,
        calendar: Calendar
    ) throws -> PeriodWindow {
        switch period {
        case .allTime:
            return PeriodWindow(interval: nil)
        case .today:
            guard let interval = calendar.dateInterval(of: .day, for: referenceDate) else {
                throw RideSpeedStatisticsCompositePresentationError.selectedRideProjectionMismatch
            }
            return PeriodWindow(interval: interval)
        case .yesterday:
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: referenceDate),
                  let interval = calendar.dateInterval(of: .day, for: yesterday) else {
                throw RideSpeedStatisticsCompositePresentationError.selectedRideProjectionMismatch
            }
            return PeriodWindow(interval: interval)
        case .week:
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: referenceDate) else {
                throw RideSpeedStatisticsCompositePresentationError.selectedRideProjectionMismatch
            }
            return PeriodWindow(interval: interval)
        case .month:
            guard let interval = calendar.dateInterval(of: .month, for: referenceDate) else {
                throw RideSpeedStatisticsCompositePresentationError.selectedRideProjectionMismatch
            }
            return PeriodWindow(interval: interval)
        case .year:
            guard let interval = calendar.dateInterval(of: .year, for: referenceDate) else {
                throw RideSpeedStatisticsCompositePresentationError.selectedRideProjectionMismatch
            }
            return PeriodWindow(interval: interval)
        }
    }
}
