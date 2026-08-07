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

    /// Package-only construction is reserved for NembraCore tests and trusted
    /// package adapters. Ordinary clients cannot manufacture included mileage,
    /// and direct-app source composition fails closed instead of silently gaining
    /// same-module access to this constructor.
    package init(
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

    /// Package-only bridge between completed-ride and reconciliation domains.
    /// `ReconciledRideDistance` does not yet carry durable ride identity, so this
    /// two-value composition must not be exposed as public production API until
    /// a future adapter mechanically binds both values to the same ride.
    /// Calendar attribution stays explicit so the domain does not invent a
    /// start-vs-end-date product decision for rides that cross midnight.
    package init(
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

        // Period boundaries depend only on the caller-supplied reference date
        // and Calendar. Resolve them once rather than asking Foundation to
        // rebuild the same day/week/month/year interval for every stored ride.
        // Every finite calendar bucket is start-inclusive/end-exclusive so the
        // first instant of the next bucket can never be counted twice.
        let selectedWindow = try periodWindow(
            for: period,
            referenceDate: referenceDate,
            calendar: calendar
        )
        let periodRides = try selectedAndDeduplicated(
            rides,
            selectedWindow: selectedWindow
        )

        // Historical records outside a finite requested period are irrelevant to
        // that period's arithmetic. Once any copy of a session falls inside the
        // requested period, however, every supplied copy of that session remains
        // relevant because conflicting identity/date/distance evidence could make
        // membership ambiguous. All-time intentionally retains whole-history
        // validation and conflict detection.
        guard periodRides.allSatisfy({ isRepresentable($0.attributedDate, in: calendar) }) else {
            throw RideStatisticsError.invalidRide
        }

        var excludedDistanceRideCount = 0
        var trustworthyRides: [(
            ride: RideStatisticsRide,
            distance: Double,
            sessionKey: String
        )] = []
        trustworthyRides.reserveCapacity(periodRides.count)

        for ride in periodRides {
            guard ride.distanceDisposition == .included,
                  let distance = ride.distanceMeters else {
                excludedDistanceRideCount += 1
                continue
            }
            trustworthyRides.append((
                ride: ride,
                distance: distance,
                sessionKey: ride.sessionID.uuidString
            ))
        }

        // Only trustworthy rides inside the requested period need a stable
        // arithmetic order. Do not sort years of unrelated history merely to
        // summarize Today/Week/Month. UUID string keys are materialized once
        // per selected ride so comparison-heavy sorts do not repeatedly allocate
        // the same deterministic identity representation.
        trustworthyRides.sort { lhs, rhs in
            if lhs.ride.attributedDate != rhs.ride.attributedDate {
                return lhs.ride.attributedDate < rhs.ride.attributedDate
            }
            return lhs.sessionKey < rhs.sessionKey
        }

        let trustworthyDistanceRideCount = trustworthyRides.count
        var distanceSum = 0.0
        var distanceCompensation = 0.0
        var longestRideDistanceMeters: Double?
        var longestRideSessionID: UUID?
        var longestRideSessionKey: String?

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
                candidateSessionKey: trustworthyRide.sessionKey,
                currentDistance: longestRideDistanceMeters,
                currentSessionKey: longestRideSessionKey
            ) {
                longestRideDistanceMeters = distance
                longestRideSessionID = ride.sessionID
                longestRideSessionKey = trustworthyRide.sessionKey
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

    private struct PeriodWindow {
        let interval: DateInterval?

        func contains(_ date: Date) -> Bool {
            guard let interval else {
                return true
            }
            return date >= interval.start && date < interval.end
        }
    }

    private static func shouldReplaceLongestRide(
        candidateDistance: Double,
        candidateSessionKey: String,
        currentDistance: Double?,
        currentSessionKey: String?
    ) -> Bool {
        guard let currentDistance else {
            return true
        }

        if candidateDistance != currentDistance {
            return candidateDistance > currentDistance
        }

        guard let currentSessionKey else {
            return true
        }
        return candidateSessionKey < currentSessionKey
    }

    /// Select period membership before allowing unrelated historical conflicts to
    /// invalidate a finite requested summary. If any copy of a session is a period
    /// candidate, all supplied copies of that session are reconciled together so a
    /// conflicting duplicate cannot move the session across the period boundary or
    /// silently replace its distance evidence.
    private static func selectedAndDeduplicated(
        _ rides: [RideStatisticsRide],
        selectedWindow: PeriodWindow
    ) throws -> [RideStatisticsRide] {
        guard selectedWindow.interval != nil else {
            return try deduplicated(rides)
        }

        let selectedSessionIDs = Set(
            rides.lazy
                .filter { selectedWindow.contains($0.attributedDate) }
                .map(\.sessionID)
        )

        guard !selectedSessionIDs.isEmpty else {
            return []
        }

        let relevantRides = rides.filter {
            selectedSessionIDs.contains($0.sessionID)
        }
        return try deduplicated(relevantRides).filter {
            selectedWindow.contains($0.attributedDate)
        }
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
                throw RideStatisticsError.invalidReferenceDate
            }
            return PeriodWindow(interval: interval)
        case .yesterday:
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: referenceDate),
                  let interval = calendar.dateInterval(of: .day, for: yesterday) else {
                throw RideStatisticsError.invalidReferenceDate
            }
            return PeriodWindow(interval: interval)
        case .week:
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: referenceDate) else {
                throw RideStatisticsError.invalidReferenceDate
            }
            return PeriodWindow(interval: interval)
        case .month:
            guard let interval = calendar.dateInterval(of: .month, for: referenceDate) else {
                throw RideStatisticsError.invalidReferenceDate
            }
            return PeriodWindow(interval: interval)
        case .year:
            guard let interval = calendar.dateInterval(of: .year, for: referenceDate) else {
                throw RideStatisticsError.invalidReferenceDate
            }
            return PeriodWindow(interval: interval)
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