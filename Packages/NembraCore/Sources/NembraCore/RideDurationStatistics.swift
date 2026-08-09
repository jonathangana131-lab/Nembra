import Foundation

public enum RideDurationStatisticsError: Error, Equatable, Sendable {
    case invalidRide
    case invalidReferenceDate
    case aggregateOverflow
    case sessionMismatch
    case continuityMismatch
    case sessionConflict(UUID)
}

/// Completeness of the observed monotonic elapsed-time subtotal represented by
/// one period summary. A partial subtotal never implies the missing intervals
/// were zero and is never repaired from wall-clock ride dates.
public enum RideDurationStatisticsAvailability: String, Codable, Equatable, Sendable {
    case noRides
    case unavailable
    case partial
    case complete
}

/// One completed ride prepared for elapsed-time statistics.
///
/// `attributedDate` exists only for caller-selected calendar bucketing. Duration
/// always comes from `CompletedRideDurationEvidence`; Nembra never subtracts
/// `beganAtDate` from `endedAtDate` to manufacture elapsed time.
public struct RideDurationStatisticsRide: Equatable, Sendable {
    public let sessionID: UUID
    public let attributedDate: Date
    public let observedDurationNanoseconds: UInt64?
    public let coverage: RideSessionDurationCoverage

    /// Package-only because `CompletedRideDurationEvidence` currently proves
    /// session + continuity identity, not the full immutable completed record.
    /// Trusted package adapters must mechanically join both values from the same
    /// completed-ride record before constructing statistics input.
    package init(
        completedRide: CompletedRideEvidence,
        durationEvidence: CompletedRideDurationEvidence,
        calendarAttribution: RideStatisticsCalendarAttribution
    ) throws {
        do {
            try durationEvidence.validate(against: completedRide)
        } catch let error as CompletedRideDurationEvidenceError {
            switch error {
            case .sessionMismatch:
                throw RideDurationStatisticsError.sessionMismatch
            case .continuityMismatch:
                throw RideDurationStatisticsError.continuityMismatch
            case .completedRideMismatch, .invalidDurationEvidence:
                throw RideDurationStatisticsError.invalidRide
            }
        }

        let attributedDate: Date
        switch calendarAttribution {
        case .rideBegan:
            attributedDate = completedRide.beganAtDate
        case .rideEnded:
            attributedDate = completedRide.endedAtDate
        }

        guard attributedDate.timeIntervalSinceReferenceDate.isFinite else {
            throw RideDurationStatisticsError.invalidRide
        }

        switch (durationEvidence.observedDurationNanoseconds, durationEvidence.coverage) {
        case (nil, .unknown), (.some, .complete), (.some, .partial):
            break
        default:
            throw RideDurationStatisticsError.invalidRide
        }

        self.sessionID = completedRide.sessionID
        self.attributedDate = attributedDate
        self.observedDurationNanoseconds = durationEvidence.observedDurationNanoseconds
        self.coverage = durationEvidence.coverage
    }
}

/// Period statistics for monotonic elapsed-time evidence Nembra actually
/// observed. `totalObservedDurationNanoseconds` is a known subtotal whenever
/// availability is `.partial`; it is not total physical ride time or moving time.
public struct RideDurationStatisticsSummary: Equatable, Sendable {
    public let period: RideStatisticsPeriod
    public let rideCount: Int
    public let completeCoverageRideCount: Int
    public let partialCoverageRideCount: Int
    public let unavailableDurationRideCount: Int
    public let durationAvailability: RideDurationStatisticsAvailability
    public let totalObservedDurationNanoseconds: UInt64?

    public var observedDurationRideCount: Int {
        completeCoverageRideCount + partialCoverageRideCount
    }
}

public enum RideDurationStatisticsAggregator {
    public static func summarize(
        period: RideStatisticsPeriod,
        rides: [RideDurationStatisticsRide],
        referenceDate: Date,
        calendar: Calendar
    ) throws -> RideDurationStatisticsSummary {
        guard referenceDate.timeIntervalSinceReferenceDate.isFinite else {
            throw RideDurationStatisticsError.invalidReferenceDate
        }
        if period != .allTime,
           !isRepresentable(referenceDate, in: calendar) {
            throw RideDurationStatisticsError.invalidReferenceDate
        }

        let selectedWindow = try periodWindow(
            for: period,
            referenceDate: referenceDate,
            calendar: calendar
        )
        let periodRides = try selectedAndDeduplicated(
            rides,
            selectedWindow: selectedWindow
        )

        // Calendar representability is relevant only after period selection.
        // A finite but calendar-unrepresentable historical date outside the
        // requested bucket must not make an otherwise valid Today/Week/etc.
        // summary unavailable. If the malformed date belongs to the selected
        // input set (including All Time), fail closed as before.
        guard periodRides.allSatisfy({ isRepresentable($0.attributedDate, in: calendar) }) else {
            throw RideDurationStatisticsError.invalidRide
        }

        var completeCoverageRideCount = 0
        var partialCoverageRideCount = 0
        var unavailableDurationRideCount = 0
        var totalObservedDurationNanoseconds: UInt64?

        for ride in periodRides {
            switch (ride.observedDurationNanoseconds, ride.coverage) {
            case (nil, .unknown):
                unavailableDurationRideCount += 1

            case let (.some(duration), .complete):
                completeCoverageRideCount += 1
                totalObservedDurationNanoseconds = try adding(
                    duration,
                    to: totalObservedDurationNanoseconds
                )

            case let (.some(duration), .partial):
                partialCoverageRideCount += 1
                totalObservedDurationNanoseconds = try adding(
                    duration,
                    to: totalObservedDurationNanoseconds
                )

            default:
                throw RideDurationStatisticsError.invalidRide
            }
        }

        let durationAvailability: RideDurationStatisticsAvailability
        if periodRides.isEmpty {
            durationAvailability = .noRides
        } else if completeCoverageRideCount == 0,
                  partialCoverageRideCount == 0 {
            durationAvailability = .unavailable
        } else if completeCoverageRideCount == periodRides.count {
            durationAvailability = .complete
        } else {
            durationAvailability = .partial
        }

        return RideDurationStatisticsSummary(
            period: period,
            rideCount: periodRides.count,
            completeCoverageRideCount: completeCoverageRideCount,
            partialCoverageRideCount: partialCoverageRideCount,
            unavailableDurationRideCount: unavailableDurationRideCount,
            durationAvailability: durationAvailability,
            totalObservedDurationNanoseconds: totalObservedDurationNanoseconds
        )
    }

    private struct PeriodWindow {
        let interval: DateInterval?

        func contains(_ date: Date) -> Bool {
            guard let interval else { return true }
            return date >= interval.start && date < interval.end
        }
    }

    /// Select period membership before allowing unrelated historical conflicts
    /// to invalidate the requested summary. Once any copy of a session is a
    /// period candidate, however, every supplied copy of that session remains
    /// relevant to identity reconciliation: disagreement can make membership or
    /// duration ambiguous and therefore still fails closed.
    private static func selectedAndDeduplicated(
        _ rides: [RideDurationStatisticsRide],
        selectedWindow: PeriodWindow
    ) throws -> [RideDurationStatisticsRide] {
        // All Time intentionally preserves the original global reconciliation
        // path and avoids allocating a selected-session set for the full history.
        guard selectedWindow.interval != nil else {
            return try deduplicated(rides)
        }

        let selectedSessionIDs = Set(
            rides.lazy
                .filter { selectedWindow.contains($0.attributedDate) }
                .map(\.sessionID)
        )

        guard !selectedSessionIDs.isEmpty else { return [] }

        let relevantRides = rides.filter { selectedSessionIDs.contains($0.sessionID) }
        return try deduplicated(relevantRides).filter {
            selectedWindow.contains($0.attributedDate)
        }
    }

    private static func adding(
        _ duration: UInt64,
        to current: UInt64?
    ) throws -> UInt64 {
        let (sum, overflow) = (current ?? 0).addingReportingOverflow(duration)
        guard !overflow else {
            throw RideDurationStatisticsError.aggregateOverflow
        }
        return sum
    }

    private static func deduplicated(
        _ rides: [RideDurationStatisticsRide]
    ) throws -> [RideDurationStatisticsRide] {
        var recordsBySessionID: [UUID: RideDurationStatisticsRide] = [:]
        var uniqueRides: [RideDurationStatisticsRide] = []
        uniqueRides.reserveCapacity(rides.count)

        for ride in rides {
            if let existing = recordsBySessionID[ride.sessionID] {
                guard existing == ride else {
                    throw RideDurationStatisticsError.sessionConflict(ride.sessionID)
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
                throw RideDurationStatisticsError.invalidReferenceDate
            }
            return PeriodWindow(interval: interval)
        case .yesterday:
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: referenceDate),
                  let interval = calendar.dateInterval(of: .day, for: yesterday) else {
                throw RideDurationStatisticsError.invalidReferenceDate
            }
            return PeriodWindow(interval: interval)
        case .week:
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: referenceDate) else {
                throw RideDurationStatisticsError.invalidReferenceDate
            }
            return PeriodWindow(interval: interval)
        case .month:
            guard let interval = calendar.dateInterval(of: .month, for: referenceDate) else {
                throw RideDurationStatisticsError.invalidReferenceDate
            }
            return PeriodWindow(interval: interval)
        case .year:
            guard let interval = calendar.dateInterval(of: .year, for: referenceDate) else {
                throw RideDurationStatisticsError.invalidReferenceDate
            }
            return PeriodWindow(interval: interval)
        }
    }
}
