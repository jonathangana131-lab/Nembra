import Foundation

public enum RideAverageSpeedStatisticsError: Error, Equatable, Sendable {
    case invalidRide
    case invalidReferenceDate
    case aggregateOverflow
    case sessionMismatch
    case continuityMismatch
    case sessionConflict(UUID)
}

/// Why one completed ride can or cannot contribute to an elapsed-ride average-speed statistic.
///
/// `included` requires both a trustworthy reconciled whole-ride distance and complete monotonic
/// elapsed-duration coverage for the same immutable completed ride. Every exclusion remains explicit;
/// a missing or partial interval is never treated as zero time or zero distance.
public enum RideAverageSpeedRideEligibility: String, Codable, Equatable, Sendable {
    case included
    case excludedDistanceEvidence
    case excludedDurationEvidence
    case excludedZeroDuration
    case excludedMultipleEvidence
}

/// One completed ride prepared for elapsed-ride average-speed statistics.
///
/// The eventual numeric speed is distance divided by complete observed ride duration. It is not a
/// mean of speed telemetry samples and it is not "moving speed": legitimate stopped time inside the
/// completed ride remains part of the elapsed-duration denominator.
public struct RideAverageSpeedStatisticsRide: Equatable, Sendable {
    public let sessionID: UUID
    public let attributedDate: Date
    public let eligibility: RideAverageSpeedRideEligibility
    public let distanceDisposition: RideStatisticsDistanceDisposition
    public let durationCoverage: RideSessionDurationCoverage

    /// Present only when `eligibility == .included`.
    public let completeDistanceMeters: Double?
    /// Present only when `eligibility == .included`; guaranteed greater than zero.
    public let completeObservedDurationNanoseconds: UInt64?

    /// Package-only construction keeps the identity join at a trusted adapter boundary. The distance
    /// projection is already package-sealed, while duration evidence can independently validate its
    /// session + continuity against the immutable completed ride. This initializer requires both to
    /// agree with the same completed ride and with the same explicit calendar-attribution policy.
    package init(
        completedRide: CompletedRideEvidence,
        distanceRide: RideStatisticsRide,
        durationEvidence: CompletedRideDurationEvidence,
        calendarAttribution: RideStatisticsCalendarAttribution
    ) throws {
        guard distanceRide.sessionID == completedRide.sessionID else {
            throw RideAverageSpeedStatisticsError.sessionMismatch
        }

        do {
            try durationEvidence.validate(against: completedRide)
        } catch let error as CompletedRideDurationEvidenceError {
            switch error {
            case .sessionMismatch:
                throw RideAverageSpeedStatisticsError.sessionMismatch
            case .continuityMismatch:
                throw RideAverageSpeedStatisticsError.continuityMismatch
            case .completedRideMismatch, .invalidDurationEvidence:
                throw RideAverageSpeedStatisticsError.invalidRide
            }
        }

        let expectedAttributedDate: Date
        switch calendarAttribution {
        case .rideBegan:
            expectedAttributedDate = completedRide.beganAtDate
        case .rideEnded:
            expectedAttributedDate = completedRide.endedAtDate
        }

        guard distanceRide.attributedDate == expectedAttributedDate,
              expectedAttributedDate.timeIntervalSinceReferenceDate.isFinite else {
            throw RideAverageSpeedStatisticsError.invalidRide
        }

        let distanceIsUsable: Bool
        if distanceRide.distanceDisposition == .included {
            guard let distance = distanceRide.distanceMeters,
                  distance.isFinite,
                  distance >= 0 else {
                throw RideAverageSpeedStatisticsError.invalidRide
            }
            distanceIsUsable = true
        } else {
            distanceIsUsable = false
        }

        let durationState: DurationEligibility
        switch (durationEvidence.observedDurationNanoseconds, durationEvidence.coverage) {
        case (nil, .unknown):
            durationState = .unavailable
        case let (.some(duration), .complete):
            durationState = duration == 0 ? .zero : .usable(duration)
        case (.some, .partial):
            durationState = .unavailable
        default:
            throw RideAverageSpeedStatisticsError.invalidRide
        }

        let eligibility: RideAverageSpeedRideEligibility
        let completeDistanceMeters: Double?
        let completeObservedDurationNanoseconds: UInt64?

        switch (distanceIsUsable, durationState) {
        case (true, .usable(let duration)):
            eligibility = .included
            completeDistanceMeters = distanceRide.distanceMeters
            completeObservedDurationNanoseconds = duration

        case (false, .usable):
            eligibility = .excludedDistanceEvidence
            completeDistanceMeters = nil
            completeObservedDurationNanoseconds = nil

        case (true, .unavailable):
            eligibility = .excludedDurationEvidence
            completeDistanceMeters = nil
            completeObservedDurationNanoseconds = nil

        case (true, .zero):
            eligibility = .excludedZeroDuration
            completeDistanceMeters = nil
            completeObservedDurationNanoseconds = nil

        case (false, .unavailable), (false, .zero):
            eligibility = .excludedMultipleEvidence
            completeDistanceMeters = nil
            completeObservedDurationNanoseconds = nil
        }

        self.sessionID = completedRide.sessionID
        self.attributedDate = expectedAttributedDate
        self.eligibility = eligibility
        self.distanceDisposition = distanceRide.distanceDisposition
        self.durationCoverage = durationEvidence.coverage
        self.completeDistanceMeters = completeDistanceMeters
        self.completeObservedDurationNanoseconds = completeObservedDurationNanoseconds
    }

    private enum DurationEligibility: Equatable {
        case usable(UInt64)
        case unavailable
        case zero
    }
}

/// Completeness of one selected-period elapsed-ride average-speed result.
///
/// A `.partial` numeric result is a weighted average over only the rides with complete paired
/// evidence. It must never be labeled as the average for the entire selected period.
public enum RideAverageSpeedStatisticsAvailability: String, Codable, Equatable, Sendable {
    case noRides
    case unavailable
    case partial
    case complete
}

/// Period summary for elapsed-ride average speed backed by paired distance + monotonic-duration truth.
///
/// The average is weighted correctly as `sum(distance) / sum(duration)`, never as an unweighted mean
/// of per-ride averages. Supporting totals include only rides whose paired evidence is fully eligible.
public struct RideAverageSpeedStatisticsSummary: Equatable, Sendable {
    public let period: RideStatisticsPeriod
    public let rideCount: Int
    public let includedRideCount: Int
    public let excludedDistanceRideCount: Int
    public let excludedDurationRideCount: Int
    public let excludedZeroDurationRideCount: Int
    public let excludedMultipleEvidenceRideCount: Int
    public let availability: RideAverageSpeedStatisticsAvailability

    /// Weighted average over eligible rides only. In `.partial`, this is a known-evidence subtotal
    /// average and requires incomplete-evidence disclosure.
    public let averageElapsedRideSpeedMetersPerSecond: Double?
    /// Sum of complete reconciled distance for exactly the rides supporting the numeric average.
    public let supportingDistanceMeters: Double?
    /// Sum of complete monotonic elapsed duration for exactly the rides supporting the numeric average.
    public let supportingObservedDurationNanoseconds: UInt64?

    public var excludedRideCount: Int {
        excludedDistanceRideCount
            + excludedDurationRideCount
            + excludedZeroDurationRideCount
            + excludedMultipleEvidenceRideCount
    }

    /// Only a complete selected-period result may use wording that implies the number covers every ride
    /// in that selected period. Even then it remains elapsed-ride average speed, not moving speed.
    public var permitsCompletePeriodAverageWording: Bool {
        availability == .complete
    }

    public var requiresIncompleteEvidenceDisclosure: Bool {
        availability == .partial
    }
}

public enum RideAverageSpeedStatisticsAggregator {
    public static func summarize(
        period: RideStatisticsPeriod,
        rides: [RideAverageSpeedStatisticsRide],
        referenceDate: Date,
        calendar: Calendar
    ) throws -> RideAverageSpeedStatisticsSummary {
        guard referenceDate.timeIntervalSinceReferenceDate.isFinite else {
            throw RideAverageSpeedStatisticsError.invalidReferenceDate
        }
        if period != .allTime,
           !isRepresentable(referenceDate, in: calendar) {
            throw RideAverageSpeedStatisticsError.invalidReferenceDate
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

        guard periodRides.allSatisfy({ isRepresentable($0.attributedDate, in: calendar) }) else {
            throw RideAverageSpeedStatisticsError.invalidRide
        }

        var includedRideCount = 0
        var excludedDistanceRideCount = 0
        var excludedDurationRideCount = 0
        var excludedZeroDurationRideCount = 0
        var excludedMultipleEvidenceRideCount = 0

        var distanceSum = 0.0
        var distanceCompensation = 0.0
        var durationSum: UInt64?

        for ride in periodRides {
            switch ride.eligibility {
            case .included:
                guard let distance = ride.completeDistanceMeters,
                      let duration = ride.completeObservedDurationNanoseconds,
                      distance.isFinite,
                      distance >= 0,
                      duration > 0 else {
                    throw RideAverageSpeedStatisticsError.invalidRide
                }

                includedRideCount += 1

                let nextDistanceSum = distanceSum + distance
                guard nextDistanceSum.isFinite else {
                    throw RideAverageSpeedStatisticsError.aggregateOverflow
                }
                let correction: Double
                if distanceSum.magnitude >= distance.magnitude {
                    correction = (distanceSum - nextDistanceSum) + distance
                } else {
                    correction = (distance - nextDistanceSum) + distanceSum
                }
                let nextCompensation = distanceCompensation + correction
                guard nextCompensation.isFinite else {
                    throw RideAverageSpeedStatisticsError.aggregateOverflow
                }
                distanceSum = nextDistanceSum
                distanceCompensation = nextCompensation

                let (nextDuration, durationOverflow) = (durationSum ?? 0)
                    .addingReportingOverflow(duration)
                guard !durationOverflow else {
                    throw RideAverageSpeedStatisticsError.aggregateOverflow
                }
                durationSum = nextDuration

            case .excludedDistanceEvidence:
                excludedDistanceRideCount += 1
            case .excludedDurationEvidence:
                excludedDurationRideCount += 1
            case .excludedZeroDuration:
                excludedZeroDurationRideCount += 1
            case .excludedMultipleEvidence:
                excludedMultipleEvidenceRideCount += 1
            }
        }

        let availability: RideAverageSpeedStatisticsAvailability
        if periodRides.isEmpty {
            availability = .noRides
        } else if includedRideCount == 0 {
            availability = .unavailable
        } else if includedRideCount == periodRides.count {
            availability = .complete
        } else {
            availability = .partial
        }

        let supportingDistanceMeters: Double?
        let averageElapsedRideSpeedMetersPerSecond: Double?
        if includedRideCount == 0 {
            supportingDistanceMeters = nil
            averageElapsedRideSpeedMetersPerSecond = nil
        } else {
            let compensatedDistance = distanceSum + distanceCompensation
            guard compensatedDistance.isFinite,
                  compensatedDistance >= 0,
                  let durationSum,
                  durationSum > 0 else {
                throw RideAverageSpeedStatisticsError.aggregateOverflow
            }

            let seconds = Double(durationSum) / 1_000_000_000
            let average = compensatedDistance / seconds
            guard seconds.isFinite,
                  seconds > 0,
                  average.isFinite,
                  average >= 0 else {
                throw RideAverageSpeedStatisticsError.aggregateOverflow
            }

            supportingDistanceMeters = compensatedDistance
            averageElapsedRideSpeedMetersPerSecond = average
        }

        return RideAverageSpeedStatisticsSummary(
            period: period,
            rideCount: periodRides.count,
            includedRideCount: includedRideCount,
            excludedDistanceRideCount: excludedDistanceRideCount,
            excludedDurationRideCount: excludedDurationRideCount,
            excludedZeroDurationRideCount: excludedZeroDurationRideCount,
            excludedMultipleEvidenceRideCount: excludedMultipleEvidenceRideCount,
            availability: availability,
            averageElapsedRideSpeedMetersPerSecond: averageElapsedRideSpeedMetersPerSecond,
            supportingDistanceMeters: supportingDistanceMeters,
            supportingObservedDurationNanoseconds: includedRideCount == 0 ? nil : durationSum
        )
    }

    private struct PeriodWindow {
        let interval: DateInterval?

        func contains(_ date: Date) -> Bool {
            guard let interval else { return true }
            return date >= interval.start && date < interval.end
        }
    }

    private static func selectedAndDeduplicated(
        _ rides: [RideAverageSpeedStatisticsRide],
        selectedWindow: PeriodWindow
    ) throws -> [RideAverageSpeedStatisticsRide] {
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

    private static func deduplicated(
        _ rides: [RideAverageSpeedStatisticsRide]
    ) throws -> [RideAverageSpeedStatisticsRide] {
        var recordsBySessionID: [UUID: RideAverageSpeedStatisticsRide] = [:]
        var uniqueRides: [RideAverageSpeedStatisticsRide] = []
        uniqueRides.reserveCapacity(rides.count)

        for ride in rides {
            if let existing = recordsBySessionID[ride.sessionID] {
                guard existing == ride else {
                    throw RideAverageSpeedStatisticsError.sessionConflict(ride.sessionID)
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
                throw RideAverageSpeedStatisticsError.invalidReferenceDate
            }
            return PeriodWindow(interval: interval)
        case .yesterday:
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: referenceDate),
                  let interval = calendar.dateInterval(of: .day, for: yesterday) else {
                throw RideAverageSpeedStatisticsError.invalidReferenceDate
            }
            return PeriodWindow(interval: interval)
        case .week:
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: referenceDate) else {
                throw RideAverageSpeedStatisticsError.invalidReferenceDate
            }
            return PeriodWindow(interval: interval)
        case .month:
            guard let interval = calendar.dateInterval(of: .month, for: referenceDate) else {
                throw RideAverageSpeedStatisticsError.invalidReferenceDate
            }
            return PeriodWindow(interval: interval)
        case .year:
            guard let interval = calendar.dateInterval(of: .year, for: referenceDate) else {
                throw RideAverageSpeedStatisticsError.invalidReferenceDate
            }
            return PeriodWindow(interval: interval)
        }
    }
}
