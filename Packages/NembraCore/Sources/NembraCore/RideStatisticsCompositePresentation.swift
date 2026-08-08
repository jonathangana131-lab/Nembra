import Foundation

/// Fail-closed composition errors for a multi-metric completed-ride statistics snapshot.
public enum RideStatisticsCompositePresentationError: Error, Equatable, Sendable {
    /// The independently prepared distance, duration, and power inputs do not select the exact same
    /// completed-ride identities under the requested calendar period.
    case selectedRideScopeMismatch
    /// A future aggregator changed its selected-ride semantics without updating this composition
    /// boundary. Failing closed is safer than attaching a metric to the wrong product population.
    case selectedRideProjectionMismatch
}

/// One disclosure-safe product snapshot for completed-ride distance, observed duration, and accepted
/// propulsion-power statistics.
///
/// The component projections deliberately remain separate. A complete distance projection does not
/// upgrade partial duration or power evidence, and vice versa. This type's additional guarantee is
/// population identity: every component was produced for the exact same selected session IDs *and*
/// exact same calendar-attribution dates.
public struct RideStatisticsCompositePresentation: Equatable, Sendable {
    public let period: RideStatisticsPeriod
    public let rideCount: Int
    public let distance: RideStatisticsPresentation
    public let observedDuration: RideDurationStatisticsPresentation
    public let observedPower: RidePowerStatisticsPresentation

    fileprivate init(
        period: RideStatisticsPeriod,
        rideCount: Int,
        distance: RideStatisticsPresentation,
        observedDuration: RideDurationStatisticsPresentation,
        observedPower: RidePowerStatisticsPresentation
    ) {
        self.period = period
        self.rideCount = rideCount
        self.distance = distance
        self.observedDuration = observedDuration
        self.observedPower = observedPower
    }
}

/// Produces a unified completed-ride statistics snapshot without weakening any metric's own evidence
/// contract.
///
/// Passing three already-built summaries would be insufficient: equal period/count values do not prove
/// that the summaries describe the same rides. This producer therefore accepts the prepared per-metric
/// ride inputs, lets each authoritative aggregator perform its own validation/deduplication, then proves
/// that all three selected populations share exact `(sessionID, attributedDate)` identities before
/// exposing them together.
public enum RideStatisticsCompositePresenter {
    public static func present(
        period: RideStatisticsPeriod,
        distanceRides: [RideStatisticsRide],
        durationRides: [RideDurationStatisticsRide],
        powerRides: [RidePowerStatisticsRide],
        referenceDate: Date,
        calendar: Calendar
    ) throws -> RideStatisticsCompositePresentation {
        let distanceSummary = try RideStatisticsAggregator.summarize(
            period: period,
            rides: distanceRides,
            referenceDate: referenceDate,
            calendar: calendar
        )
        let durationSummary = try RideDurationStatisticsAggregator.summarize(
            period: period,
            rides: durationRides,
            referenceDate: referenceDate,
            calendar: calendar
        )
        let powerSummary = try RidePowerStatisticsAggregator.summarize(
            period: period,
            rides: powerRides,
            referenceDate: referenceDate,
            calendar: calendar
        )

        let distancePresentation = try RideStatisticsPresenter.present(distanceSummary)
        let durationPresentation = try RideDurationStatisticsPresenter.present(durationSummary)
        let powerPresentation = try RidePowerStatisticsPresenter.present(powerSummary)

        let distanceScope = try selectedScope(
            period: period,
            referenceDate: referenceDate,
            calendar: calendar,
            rides: distanceRides,
            sessionID: { $0.sessionID },
            attributedDate: { $0.attributedDate }
        )
        let durationScope = try selectedScope(
            period: period,
            referenceDate: referenceDate,
            calendar: calendar,
            rides: durationRides,
            sessionID: { $0.sessionID },
            attributedDate: { $0.attributedDate }
        )
        let powerScope = try selectedScope(
            period: period,
            referenceDate: referenceDate,
            calendar: calendar,
            rides: powerRides,
            sessionID: { $0.sessionID },
            attributedDate: { $0.attributedDate }
        )

        guard distanceScope == durationScope,
              distanceScope == powerScope else {
            throw RideStatisticsCompositePresentationError.selectedRideScopeMismatch
        }

        let selectedRideCount = distanceScope.count
        guard distancePresentation.period == period,
              durationPresentation.period == period,
              powerPresentation.period == period,
              distancePresentation.rideCount == selectedRideCount,
              durationPresentation.rideCount == selectedRideCount,
              powerPresentation.rideCount == selectedRideCount else {
            throw RideStatisticsCompositePresentationError.selectedRideProjectionMismatch
        }

        return RideStatisticsCompositePresentation(
            period: period,
            rideCount: selectedRideCount,
            distance: distancePresentation,
            observedDuration: durationPresentation,
            observedPower: powerPresentation
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

    /// Reconstructs only the population identity needed for cross-metric composition. Metric evidence,
    /// duplicates, malformed rides, and source-specific truth remain owned by the three aggregators above.
    /// If their future selection semantics diverge from this bounded-period projection, the final count
    /// reconciliation fails closed rather than silently composing different populations.
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

        var selected: Set<SelectedRideIdentity> = []
        selected.reserveCapacity(rides.count)

        for ride in rides {
            let date = attributedDate(ride)
            guard window.contains(date) else { continue }
            selected.insert(SelectedRideIdentity(
                sessionID: sessionID(ride),
                attributedDate: date
            ))
        }

        return selected
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
                throw RideStatisticsCompositePresentationError.selectedRideProjectionMismatch
            }
            return PeriodWindow(interval: interval)
        case .yesterday:
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: referenceDate),
                  let interval = calendar.dateInterval(of: .day, for: yesterday) else {
                throw RideStatisticsCompositePresentationError.selectedRideProjectionMismatch
            }
            return PeriodWindow(interval: interval)
        case .week:
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: referenceDate) else {
                throw RideStatisticsCompositePresentationError.selectedRideProjectionMismatch
            }
            return PeriodWindow(interval: interval)
        case .month:
            guard let interval = calendar.dateInterval(of: .month, for: referenceDate) else {
                throw RideStatisticsCompositePresentationError.selectedRideProjectionMismatch
            }
            return PeriodWindow(interval: interval)
        case .year:
            guard let interval = calendar.dateInterval(of: .year, for: referenceDate) else {
                throw RideStatisticsCompositePresentationError.selectedRideProjectionMismatch
            }
            return PeriodWindow(interval: interval)
        }
    }
}
