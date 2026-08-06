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

    public init(
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
    /// treating incomplete/conflicting evidence as trustworthy mileage.
    /// Calendar attribution uses the recorded ride-begin date; no duration is
    /// derived from wall-clock begin/end ordering.
    public init(
        completedRide: CompletedRideEvidence,
        reconciledDistance: ReconciledRideDistance
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
            attributedDate: completedRide.beganAtDate,
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

/// Aggregated completed-ride statistics. The memberwise initializer remains
/// module-internal so external callers cannot manufacture internally
/// inconsistent summary counts.
public struct RideStatisticsSummary: Equatable, Sendable {
    public let period: RideStatisticsPeriod
    public let rideCount: Int
    public let ridingDayCount: Int
    public let trustworthyDistanceRideCount: Int
    public let excludedDistanceRideCount: Int
    /// Nil means the period has no trustworthy distance evidence. A real zero
    /// remains representable when at least one included ride legitimately has a
    /// zero reconciled distance.
    public let totalDistanceMeters: Double?
    public let longestRideDistanceMeters: Double?
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
        guard referenceDate.timeIntervalSinceReferenceDate.isFinite else {
            throw RideStatisticsError.invalidReferenceDate
        }

        let uniqueRides = try deduplicated(rides)
        let periodRides = try uniqueRides.filter { ride in
            try contains(
                ride.attributedDate,
                period: period,
                referenceDate: referenceDate,
                calendar: calendar
            )
        }

        var trustworthyDistanceRideCount = 0
        var excludedDistanceRideCount = 0
        var totalDistanceMeters: Double?
        var longestRideDistanceMeters: Double?
        var longestRideSessionID: UUID?

        for ride in periodRides {
            guard ride.distanceDisposition == .included,
                  let distance = ride.distanceMeters else {
                excludedDistanceRideCount += 1
                continue
            }

            let nextTotal = (totalDistanceMeters ?? 0) + distance
            guard nextTotal.isFinite else {
                throw RideStatisticsError.aggregateOverflow
            }

            trustworthyDistanceRideCount += 1
            totalDistanceMeters = nextTotal

            if longestRideDistanceMeters.map({ distance > $0 }) ?? true {
                longestRideDistanceMeters = distance
                longestRideSessionID = ride.sessionID
            }
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
            totalDistanceMeters: totalDistanceMeters,
            longestRideDistanceMeters: longestRideDistanceMeters,
            longestRideSessionID: longestRideSessionID,
            longestRidingDayStreakDays: longestStreak
        )
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

    private static func contains(
        _ date: Date,
        period: RideStatisticsPeriod,
        referenceDate: Date,
        calendar: Calendar
    ) throws -> Bool {
        switch period {
        case .allTime:
            return true
        case .today:
            return calendar.isDate(date, inSameDayAs: referenceDate)
        case .yesterday:
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: referenceDate) else {
                throw RideStatisticsError.invalidReferenceDate
            }
            return calendar.isDate(date, inSameDayAs: yesterday)
        case .week:
            return try contains(
                date,
                component: .weekOfYear,
                referenceDate: referenceDate,
                calendar: calendar
            )
        case .month:
            return try contains(
                date,
                component: .month,
                referenceDate: referenceDate,
                calendar: calendar
            )
        case .year:
            return try contains(
                date,
                component: .year,
                referenceDate: referenceDate,
                calendar: calendar
            )
        }
    }

    private static func contains(
        _ date: Date,
        component: Calendar.Component,
        referenceDate: Date,
        calendar: Calendar
    ) throws -> Bool {
        guard let interval = calendar.dateInterval(of: component, for: referenceDate) else {
            throw RideStatisticsError.invalidReferenceDate
        }
        return interval.contains(date)
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
