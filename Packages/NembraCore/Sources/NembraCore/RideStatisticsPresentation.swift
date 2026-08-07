import Foundation

public enum RideStatisticsPresentationError: Error, Equatable, Sendable {
    case invalidSummary
}

/// Product-facing disclosure state for completed-ride distance statistics.
///
/// A partial numeric distance is still useful accepted evidence, but it is only a known subtotal.
/// It must never be promoted into the complete selected period's total or longest-ride claim.
public enum RideStatisticsPresentationState: String, Codable, Equatable, Sendable {
    /// The selected period contains no completed rides.
    case noCompletedRides
    /// Completed rides exist, but none has distance evidence trustworthy enough to aggregate.
    case distanceUnavailable
    /// Some selected rides have trustworthy distance and some do not.
    case partialTrustworthyDistance
    /// Every selected ride has trustworthy distance evidence.
    case completeTrustworthyDistance
}

/// Stable product/accessibility projection of `RideStatisticsSummary`.
///
/// The projection deliberately renames ambiguous aggregate fields. When distance coverage is partial,
/// `knownDistanceSubtotalMeters` remains a real sum of trustworthy rides and
/// `longestTrustworthyRideDistanceMeters` remains a real accepted ride distance, but neither may be
/// described as the complete period total or complete period longest ride.
public struct RideStatisticsPresentation: Equatable, Sendable {
    public let period: RideStatisticsPeriod
    public let state: RideStatisticsPresentationState

    public let rideCount: Int
    public let ridingDayCount: Int
    public let ridesWithTrustworthyDistance: Int
    public let ridesWithoutTrustworthyDistance: Int

    /// Sum of trustworthy selected-ride distance evidence.
    ///
    /// Nil means no trustworthy distance exists. In `.partialTrustworthyDistance`, this is a known
    /// subtotal only, not the complete selected period's distance.
    public let knownDistanceSubtotalMeters: Double?

    /// Longest trustworthy ride distance among selected rides that have trustworthy distance.
    ///
    /// In `.partialTrustworthyDistance`, another selected ride with unavailable distance may have
    /// travelled farther, so callers must not label this as the selected period's longest ride.
    public let longestTrustworthyRideDistanceMeters: Double?
    public let longestTrustworthyRideSessionID: UUID?

    /// These calendar statistics describe the supplied completed-ride identities and do not depend on
    /// distance availability.
    public let longestRecordedRidingDayStreakDays: Int

    /// True only when every selected ride contributes trustworthy distance, so the numeric subtotal is
    /// also the complete selected period total.
    public let permitsCompletePeriodDistanceTotalWording: Bool

    /// True only when every selected ride contributes trustworthy distance, so the longest trustworthy
    /// ride is also the longest ride by known distance across the complete selected ride set.
    public let permitsCompletePeriodLongestRideWording: Bool

    /// True when a real trustworthy distance subtotal exists but one or more selected rides lack
    /// trustworthy distance. Product UI must disclose that incompleteness instead of presenting the
    /// number as a complete period total.
    public let requiresKnownDistanceSubtotalDisclosure: Bool

    fileprivate init(
        period: RideStatisticsPeriod,
        state: RideStatisticsPresentationState,
        rideCount: Int,
        ridingDayCount: Int,
        ridesWithTrustworthyDistance: Int,
        ridesWithoutTrustworthyDistance: Int,
        knownDistanceSubtotalMeters: Double?,
        longestTrustworthyRideDistanceMeters: Double?,
        longestTrustworthyRideSessionID: UUID?,
        longestRecordedRidingDayStreakDays: Int,
        permitsCompletePeriodDistanceTotalWording: Bool,
        permitsCompletePeriodLongestRideWording: Bool,
        requiresKnownDistanceSubtotalDisclosure: Bool
    ) {
        self.period = period
        self.state = state
        self.rideCount = rideCount
        self.ridingDayCount = ridingDayCount
        self.ridesWithTrustworthyDistance = ridesWithTrustworthyDistance
        self.ridesWithoutTrustworthyDistance = ridesWithoutTrustworthyDistance
        self.knownDistanceSubtotalMeters = knownDistanceSubtotalMeters
        self.longestTrustworthyRideDistanceMeters = longestTrustworthyRideDistanceMeters
        self.longestTrustworthyRideSessionID = longestTrustworthyRideSessionID
        self.longestRecordedRidingDayStreakDays = longestRecordedRidingDayStreakDays
        self.permitsCompletePeriodDistanceTotalWording = permitsCompletePeriodDistanceTotalWording
        self.permitsCompletePeriodLongestRideWording = permitsCompletePeriodLongestRideWording
        self.requiresKnownDistanceSubtotalDisclosure = requiresKnownDistanceSubtotalDisclosure
    }
}

public enum RideStatisticsPresenter {
    /// Converts completed-ride statistics into disclosure-safe product semantics.
    ///
    /// `RideStatisticsAggregator` constructs internally consistent summaries. This boundary revalidates
    /// the invariants so a future persistence/adapter layer cannot turn malformed aggregate state into
    /// confident product wording.
    public static func present(
        _ summary: RideStatisticsSummary
    ) throws -> RideStatisticsPresentation {
        guard summary.rideCount >= 0,
              summary.ridingDayCount >= 0,
              summary.trustworthyDistanceRideCount >= 0,
              summary.excludedDistanceRideCount >= 0,
              summary.longestRidingDayStreakDays >= 0,
              summary.rideCount
                == summary.trustworthyDistanceRideCount + summary.excludedDistanceRideCount,
              summary.ridingDayCount <= summary.rideCount,
              summary.longestRidingDayStreakDays <= summary.ridingDayCount else {
            throw RideStatisticsPresentationError.invalidSummary
        }

        if summary.rideCount == 0 {
            guard summary.ridingDayCount == 0,
                  summary.longestRidingDayStreakDays == 0 else {
                throw RideStatisticsPresentationError.invalidSummary
            }
        } else {
            guard summary.ridingDayCount > 0,
                  summary.longestRidingDayStreakDays > 0 else {
                throw RideStatisticsPresentationError.invalidSummary
            }
        }

        let hasTrustworthyDistance = summary.trustworthyDistanceRideCount > 0
        let hasTotal = summary.totalDistanceMeters != nil
        let hasLongestDistance = summary.longestRideDistanceMeters != nil
        let hasLongestSession = summary.longestRideSessionID != nil

        guard hasTrustworthyDistance == hasTotal,
              hasTrustworthyDistance == hasLongestDistance,
              hasTrustworthyDistance == hasLongestSession else {
            throw RideStatisticsPresentationError.invalidSummary
        }

        if let totalDistanceMeters = summary.totalDistanceMeters,
           let longestRideDistanceMeters = summary.longestRideDistanceMeters {
            guard totalDistanceMeters.isFinite,
                  totalDistanceMeters >= 0,
                  longestRideDistanceMeters.isFinite,
                  longestRideDistanceMeters >= 0,
                  longestRideDistanceMeters <= totalDistanceMeters else {
                throw RideStatisticsPresentationError.invalidSummary
            }
        }

        let state: RideStatisticsPresentationState
        switch summary.distanceAvailability {
        case .noRides:
            guard summary.rideCount == 0,
                  summary.trustworthyDistanceRideCount == 0,
                  summary.excludedDistanceRideCount == 0,
                  !hasTrustworthyDistance else {
                throw RideStatisticsPresentationError.invalidSummary
            }
            state = .noCompletedRides

        case .unavailable:
            guard summary.rideCount > 0,
                  summary.trustworthyDistanceRideCount == 0,
                  summary.excludedDistanceRideCount == summary.rideCount,
                  !hasTrustworthyDistance else {
                throw RideStatisticsPresentationError.invalidSummary
            }
            state = .distanceUnavailable

        case .partial:
            guard summary.rideCount > 0,
                  summary.trustworthyDistanceRideCount > 0,
                  summary.excludedDistanceRideCount > 0,
                  hasTrustworthyDistance else {
                throw RideStatisticsPresentationError.invalidSummary
            }
            state = .partialTrustworthyDistance

        case .complete:
            guard summary.rideCount > 0,
                  summary.trustworthyDistanceRideCount == summary.rideCount,
                  summary.excludedDistanceRideCount == 0,
                  hasTrustworthyDistance else {
                throw RideStatisticsPresentationError.invalidSummary
            }
            state = .completeTrustworthyDistance
        }

        let permitsCompleteDistanceWording = state == .completeTrustworthyDistance
        let requiresSubtotalDisclosure = state == .partialTrustworthyDistance

        return RideStatisticsPresentation(
            period: summary.period,
            state: state,
            rideCount: summary.rideCount,
            ridingDayCount: summary.ridingDayCount,
            ridesWithTrustworthyDistance: summary.trustworthyDistanceRideCount,
            ridesWithoutTrustworthyDistance: summary.excludedDistanceRideCount,
            knownDistanceSubtotalMeters: summary.totalDistanceMeters,
            longestTrustworthyRideDistanceMeters: summary.longestRideDistanceMeters,
            longestTrustworthyRideSessionID: summary.longestRideSessionID,
            longestRecordedRidingDayStreakDays: summary.longestRidingDayStreakDays,
            permitsCompletePeriodDistanceTotalWording: permitsCompleteDistanceWording,
            permitsCompletePeriodLongestRideWording: permitsCompleteDistanceWording,
            requiresKnownDistanceSubtotalDisclosure: requiresSubtotalDisclosure
        )
    }
}
