import Foundation

public enum RideStatisticsError: Error, Equatable, Sendable {
    case invalidRide
    case invalidReferenceDate
    case aggregateOverflow
    case sessionConflict(UUID)
}

public enum RideStatisticsDistanceDisposition: String, Codable, Equatable, Sendable {
    case included
    case excludedInsufficientEvidence
    case excludedIncompleteCoverage
    case excludedConflict
}

/// Which recorded ride wall-clock date owns a completed ride for calendar
/// buckets such as Today or Month. Nembra does not silently choose this product
/// policy for callers because a ride may cross midnight.
public enum RideStatisticsCalendarAttribution: String, Codable, Equatable, Sendable {
    case rideBegan
    case rideEnded

    fileprivate func date(for ride: CompletedRideEvidence) -> Date {
        switch self {
        case .rideBegan:
            ride.beganAtDate
        case .rideEnded:
            ride.endedAtDate
        }
    }
}

/// One completed ride prepared for calendar statistics.
///
/// `attributedDate` is presentation/calendar evidence only. It must never be
/// reused as a monotonic ride-duration source. `distanceDisposition` keeps bad
/// or incomplete distance evidence visible to the statistics layer without
/// silently counting it into totals.
///
/// This is intentionally a derived runtime value rather than a persisted
/// payload. Durable history remains owned by `RideHistoryRecord` and its
/// validated evidence types.
public struct RideStatisticsRide: Equatable, Sendable {
    public let sessionID: UUID
    public let attributedDate: Date
    public let distanceMeters: Double?
    public let distanceDisposition: RideStatisticsDistanceDisposition

    /// Module-internal construction is reserved for core tests and trusted
    /// adapters. App code must not bypass reconciliation by self-declaring an
    /// arbitrary distance as included evidence.
    init(
        sessionID: UUID,
        attributedDate: Date,
        distanceMeters: Double?,
        distanceDisposition: RideStatisticsDistanceDisposition
    ) throws {
        guard attributedDate.timeIntervalSinceReferenceDate.isFinite else {
            throw RideStatisticsError.invalidRide
        }

        if let distanceMeters {
            guard distanceMeters.isFinite, distanceMeters >= 0 else {
                throw RideStatisticsError.invalidRide
            }
        }

        if distanceDisposition == .included, distanceMeters == nil {
            throw RideStatisticsError.invalidRide
        }

        self.sessionID = sessionID
        self.attributedDate = attributedDate
        self.distanceMeters = distanceMeters
        self.distanceDisposition = distanceDisposition
    }

    /// Bridges the existing completed-ride and reconciliation domains without
    /// treating incomplete/conflicting evidence as trustworthy mileage. The
    /// calendar attribution rule is explicit so this domain does not invent a
    /// start-vs-end-date product decision for rides that cross midnight.
    public init(
        completedRide: CompletedRideEvidence,
        reconciledDistance: ReconciledRideDistance,
        calendarAttribution: RideStatisticsCalendarAttribution
    ) throws {
        let disposition: RideStatisticsDistanceDisposition
        switch reconciledDistance.status {
        case .complete, .vehicleDistanceRecoveredAcrossCoverageGap:
            switch reconciledDistance.confidence {
            case .unavailable:
                disposition = .excludedInsufficientEvidence
            case .conflicting:
                disposition = .excludedConflict
            case .singleSource, .corroborated, .recoverySupported:
                disposition = reconciledDistance.finalDistanceMeters == nil
                    ? .excludedInsufficientEvidence
                    : .included
            }
        case .coverageIncomplete:
            disposition = .excludedIncompleteCoverage
        case .disagreementRequiresReview:
            disposition = .excludedConflict
        case .insufficientEvidence:
            disposition = .excludedInsufficientEvidence
        }

        try self.init(
            sessionID: completedRide.sessionID,
            attributedDate: calendarAttribution.date(for: completedRide),
            distanceMeters: reconciledDistance.finalDistanceMeters,
            distanceDisposition: disposition
        )
    }
}

public enum RideStatisticsPeriod: String, Codable, CaseIterable, Equatable, Sendable {
    case today
    case yesterday
    case week
    case month
    case year
    case allTime
}

/// Completeness of the numeric distance represented by one statistics summary.
/// This classifies only the supplied ride collection; it does not claim that an
/// upstream sync/history store itself has complete global coverage.
public enum RideStatisticsDistanceAvailability: String, Codable, Equatable, Sendable {
    /// The selected period contains no completed rides.
    case noRides
    /// Completed rides exist, but none has distance trustworthy enough to sum.
    case unavailable
    /// Some completed rides have trustworthy distance and others do not. The
    /// numeric value is a known subtotal and must not be labeled a full total.
    case partial
    /// Every completed ride in the supplied period contributes trustworthy
    /// distance to the numeric total.
    case complete
}

/// Aggregated completed-ride statistics. The memberwise initializer remains
/// module-internal so external callers cannot manufacture internally
/// inconsistent summary counts.
public struct RideStatisticsSummary: Equatable, Sendable {
    public let period: RideStatisticsPeriod
    public let rideCount: Int
    public let ridingDayCount: Int
    public let trustworthyDistanceRideCount: Int
    public let excludedDistanceRideCount: Int
    public let distanceAvailability: RideStatisticsDistanceAvailability
    /// Nil means the period has no trustworthy distance evidence. When
    /// `distanceAvailability == .partial`, this is only the sum of trustworthy
    /// rides and must be presented as a known subtotal rather than the period's
    /// complete mileage. A real zero remains representable when at least one
    /// included ride legitimately has a zero reconciled distance.
    public let totalDistanceMeters: Double?
    public let longestRideDistanceMeters: Double?
    /// Equal-distance ties use only the durable session UUID as a deterministic
    /// identity tie-break. Calendar date does not become an extra product
    /// preference merely because two rides have the same longest distance.
    public let longestRideSessionID: UUID?
    public let longestRidingDayStreakDays: Int
}

public enum RideStatisticsAggregator {
    public static func summarize(
        period: RideStatisticsPeriod,
        rides: [RideStatisticsRide],
        referenceDate: Date,
        calendar: Calendar
    ) throws -> RideStatisticsSummary {
        guard referenceDate.timeIntervalSinceReferenceDate.isFinite,
              isRepresentable(referenceDate, in: calendar) else {
            throw RideStatisticsError.invalidReferenceDate
        }

        let uniqueRides = try deduplicated(rides)
        guard uniqueRides.allSatisfy({ isRepresentable($0.attributedDate, in: calendar) }) else {
            throw RideStatisticsError.invalidRide
        }

        // Period boundaries depend only on the caller-supplied reference date
        // and Calendar. Resolve them once rather than asking Foundation to
        // rebuild the same day/week/month/year interval for every stored ride.
        let selectedInterval = try periodInterval(
            for: period,
            referenceDate: referenceDate,
            calendar: calendar
        )
        let periodRides = uniqueRides.filter { ride in
            selectedInterval?.contains(ride.attributedDate) ?? true
        }

        var excludedDistanceRideCount = 0
        var trustworthyRides: [(ride: RideStatisticsRide, distance: Double)] = []
        trustworthyRides.reserveCapacity(periodRides.count)

        for ride in periodRides {
            guard ride.distanceDisposition == .included,
                  let distance = ride.distanceMeters else {
                excludedDistanceRideCount += 1
                continue
            }
            trustworthyRides.append((ride: ride, distance: distance))
        }

        // Only trustworthy rides inside the requested period need a stable
        // arithmetic order. Do not sort years of unrelated history merely to
        // summarize Today/Week/Month. The date+UUID order is semantic-neutral:
        // it exists only so persistence fetch order cannot perturb floating-
        // point aggregation.
        trustworthyRides.sort { lhs, rhs in
            if lhs.ride.attributedDate != rhs.ride.attributedDate {
                return lhs.ride.attributedDate < rhs.ride.attributedDate
            }
            return lhs.ride.sessionID.uuidString < rhs.ride.sessionID.uuidString
        }

        let trustworthyDistanceRideCount = trustworthyRides.count
        var distanceSum = 0.0
        var distanceCompensation = 0.0
        var longestRideDistanceMeters: Double?
        var longestRideSessionID: UUID?

        for trustworthyRide in trustworthyRides {
            let ride = trustworthyRide.ride
            let distance = trustworthyRide.distance

            // Neumaier compensated summation keeps small legitimate ride
            // distances from disappearing merely because a much larger total
            // was accumulated first. Stable ride ordering still guarantees the
            // same immutable ride set follows the same arithmetic path.
            let nextSum = distanceSum + distance
            guard nextSum.isFinite else {
                throw RideStatisticsError.aggregateOverflow
            }

            let correction: Double
            if distanceSum.magnitude >= distance.magnitude {
                correction = (distanceSum - nextSum) + distance
            } else {
                correction = (distance - nextSum) + distanceSum
            }
            let nextCompensation = distanceCompensation + correction
            guard nextCompensation.isFinite else {
                throw RideStatisticsError.aggregateOverflow
            }

            distanceSum = nextSum
            distanceCompensation = nextCompensation

            if shouldReplaceLongestRide(
                candidateDistance: distance,
                candidateSessionID: ride.sessionID,
                currentDistance: longestRideDistanceMeters,
                currentSessionID: longestRideSessionID
            ) {
                longestRideDistanceMeters = distance
                longestRideSessionID = ride.sessionID
            }
        }

        let totalDistanceMeters: Double?
        if trustworthyDistanceRideCount == 0 {
            totalDistanceMeters = nil
        } else {
            let compensatedTotal = distanceSum + distanceCompensation
            guard compensatedTotal.isFinite, compensatedTotal >= 0 else {
                throw RideStatisticsError.aggregateOverflow
            }
            totalDistanceMeters = compensatedTotal
        }

        let distanceAvailability: RideStatisticsDistanceAvailability
        if periodRides.isEmpty {
            distanceAvailability = .noRides
        } else if trustworthyDistanceRideCount == 0 {
            distanceAvailability = .unavailable
        } else if excludedDistanceRideCount == 0 {
            distanceAvailability = .complete
        } else {
            distanceAvailability = .partial
        }

        let ridingDays = Set(periodRides.map { calendar.startOfDay(for: $0.attributedDate) })
        let longestStreak = longestConsecutiveDayStreak(
            days: ridingDays,
            calendar: calendar
        )

        return RideStatisticsSummary(
            period: period,
            rideCount: periodRides.count,
            ridingDayCount: ridingDays.count,
            trustworthyDistanceRideCount: trustworthyDistanceRideCount,
            excludedDistanceRideCount: excludedDistanceRideCount,
            distanceAvailability: distanceAvailability,
            totalDistanceMeters: totalDistanceMeters,
            longestRideDistanceMeters: longestRideDistanceMeters,
            longestRideSessionID: longestRideSessionID,
            longestRidingDayStreakDays: longestStreak
        )
    }

    private static func shouldReplaceLongestRide(
        candidateDistance: Double,
        candidateSessionID: UUID,
        currentDistance: Double?,
        currentSessionID: UUID?
    ) -> Bool {
        guard let currentDistance else {
            return true
        }

        if candidateDistance != currentDistance {
            return candidateDistance > currentDistance
        }

        guard let currentSessionID else {
            return true
        }
        return candidateSessionID.uuidString < currentSessionID.uuidString
    }

    private static func deduplicated(
        _ rides: [RideStatisticsRide]
    ) throws -> [RideStatisticsRide] {
        var recordsBySessionID: [UUID: RideStatisticsRide] = [:]
        var uniqueRides: [RideStatisticsRide] = []
        uniqueRides.reserveCapacity(rides.count)

        for ride in rides {
            if let existing = recordsBySessionID[ride.sessionID] {
                guard existing == ride else {
                    throw RideStatisticsError.sessionConflict(ride.sessionID)
                }
                continue
            }

            recordsBySessionID[ride.sessionID] = ride
            uniqueRides.append(ride)
        }
        return uniqueRides
    }

    private static func isRepresentable(
        _ date: Date,
        in calendar: Calendar
    ) -> Bool {
        guard let dayInterval = calendar.dateInterval(of: .day, for: date) else {
            return false
        }
        return dayInterval.contains(date)
    }

    private static func periodInterval(
        for period: RideStatisticsPeriod,
        referenceDate: Date,
        calendar: Calendar
    ) throws -> DateInterval? {
        switch period {
        case .allTime:
            return nil
        case .today:
            guard let interval = calendar.dateInterval(of: .day, for: referenceDate) else {
                throw RideStatisticsError.invalidReferenceDate
            }
            return interval
        case .yesterday:
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: referenceDate),
                  let interval = calendar.dateInterval(of: .day, for: yesterday) else {
                throw RideStatisticsError.invalidReferenceDate
            }
            return interval
        case .week:
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: referenceDate) else {
                throw RideStatisticsError.invalidReferenceDate
            }
            return interval
        case .month:
            guard let interval = calendar.dateInterval(of: .month, for: referenceDate) else {
                throw RideStatisticsError.invalidReferenceDate
            }
            return interval
        case .year:
            guard let interval = calendar.dateInterval(of: .year, for: referenceDate) else {
                throw RideStatisticsError.invalidReferenceDate
            }
            return interval
        }
    }

    private static func longestConsecutiveDayStreak(
        days: Set<Date>,
        calendar: Calendar
    ) -> Int {
        let sortedDays = days.sorted()
        guard !sortedDays.isEmpty else { return 0 }

        var longest = 1
        var current = 1

        for pair in zip(sortedDays, sortedDays.dropFirst()) {
            let dayDelta = calendar.dateComponents([.day], from: pair.0, to: pair.1).day
            if dayDelta == 1 {
                current += 1
                longest = max(longest, current)
            } else {
                current = 1
            }
        }
        return longest
    }
}
