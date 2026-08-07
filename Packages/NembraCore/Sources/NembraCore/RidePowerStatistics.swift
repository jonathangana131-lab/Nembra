import Foundation

public enum RidePowerStatisticsError: Error, Equatable, Sendable {
    case invalidRide
    case invalidReferenceDate
    case sessionMismatch
    case continuityMismatch
    case sessionConflict(UUID)
    case sourceScopeConflict(UUID)
}

/// Completeness of accepted observed peak-power evidence represented by one period summary.
///
/// `.complete` means every supplied completed ride in the selected period carries accepted
/// peak-power evidence with no recorded selected-source evidence loss. It does not mean Nembra
/// observed a mathematically perfect continuous-time motor maximum.
public enum RidePowerStatisticsAvailability: String, Codable, Equatable, Sendable {
    case noRides
    case unavailable
    case partial
    case complete
}

/// One completed ride prepared for accepted observed peak-power statistics.
///
/// Construction is package-only so callers cannot pair a completed ride with unrelated peak-power
/// evidence. A nil peak means exactly that no accepted completed-ride peak evidence was supplied;
/// it is never converted into zero watts.
public struct RidePowerStatisticsRide: Equatable, Sendable {
    public let sessionID: UUID
    public let attributedDate: Date
    public let peakPowerEvidence: CompletedRidePeakPowerEvidence?

    package init(
        completedRide: CompletedRideEvidence,
        peakPowerEvidence: CompletedRidePeakPowerEvidence?,
        calendarAttribution: RideStatisticsCalendarAttribution
    ) throws {
        if let peakPowerEvidence {
            do {
                try peakPowerEvidence.validate(against: completedRide)
            } catch let error as CompletedRidePeakPowerEvidenceError {
                switch error {
                case .sessionMismatch:
                    throw RidePowerStatisticsError.sessionMismatch
                case .continuityMismatch:
                    throw RidePowerStatisticsError.continuityMismatch
                default:
                    throw RidePowerStatisticsError.invalidRide
                }
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
            throw RidePowerStatisticsError.invalidRide
        }

        self.sessionID = completedRide.sessionID
        self.attributedDate = attributedDate
        self.peakPowerEvidence = peakPowerEvidence
    }
}

/// Period statistics for accepted observed ride peak-power evidence.
///
/// `highestAcceptedObservedPowerWatts` is the largest accepted peak among the evidence Nembra
/// actually has for the selected rides. When `peakPowerAvailability == .partial`, missing or gapped
/// evidence means this value must not be presented as the complete period's physical maximum.
/// It is never a rated motor/controller maximum, throttle signal, learned full-power ceiling, or
/// interpolation-derived value.
public struct RidePowerStatisticsSummary: Equatable, Sendable {
    public let period: RideStatisticsPeriod
    public let rideCount: Int
    public let acceptedPeakPowerRideCount: Int
    public let gapFreePeakPowerRideCount: Int
    public let partialPeakPowerRideCount: Int
    public let unavailablePeakPowerRideCount: Int
    public let peakPowerAvailability: RidePowerStatisticsAvailability

    public let highestAcceptedObservedPowerWatts: Double?
    public let highestAcceptedObservedPowerSessionID: UUID?
    public let highestAcceptedObservedPowerContinuity: PeakPowerObservationContinuity?
    public let highestAcceptedObservedPowerConfirmedModeKey: String?

    /// Exact source provenance shared by every accepted peak included in this summary.
    /// These remain nil when no accepted peak-power evidence exists in the selected period.
    public let vehicleIdentityKey: String?
    public let identityAuthority: ObservedPowerEnvelopeScopeAuthority?
    public let evidenceAuthority: ObservedPowerEnvelopeEvidenceAuthority?
}

public enum RidePowerStatisticsAggregator {
    public static func summarize(
        period: RideStatisticsPeriod,
        rides: [RidePowerStatisticsRide],
        referenceDate: Date,
        calendar: Calendar
    ) throws -> RidePowerStatisticsSummary {
        guard referenceDate.timeIntervalSinceReferenceDate.isFinite else {
            throw RidePowerStatisticsError.invalidReferenceDate
        }
        if period != .allTime,
           !isRepresentable(referenceDate, in: calendar) {
            throw RidePowerStatisticsError.invalidReferenceDate
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
            throw RidePowerStatisticsError.invalidRide
        }

        struct AcceptedSourceScope: Equatable {
            let vehicleIdentityKey: String
            let identityAuthority: ObservedPowerEnvelopeScopeAuthority
            let evidenceAuthority: ObservedPowerEnvelopeEvidenceAuthority
        }

        var selectedSourceScope: AcceptedSourceScope?
        var gapFreePeakPowerRideCount = 0
        var partialPeakPowerRideCount = 0
        var unavailablePeakPowerRideCount = 0

        var highestEvidence: CompletedRidePeakPowerEvidence?
        var highestSessionKey: String?

        for ride in periodRides {
            guard let evidence = ride.peakPowerEvidence else {
                unavailablePeakPowerRideCount += 1
                continue
            }

            let evidenceScope = AcceptedSourceScope(
                vehicleIdentityKey: evidence.vehicleIdentityKey,
                identityAuthority: evidence.identityAuthority,
                evidenceAuthority: evidence.evidenceAuthority
            )
            if let selectedSourceScope {
                guard selectedSourceScope == evidenceScope else {
                    throw RidePowerStatisticsError.sourceScopeConflict(ride.sessionID)
                }
            } else {
                selectedSourceScope = evidenceScope
            }

            switch evidence.observationContinuity {
            case .noRecordedSelectedSourceEvidenceLoss:
                gapFreePeakPowerRideCount += 1
            case .partialSelectedSourceEvidence:
                partialPeakPowerRideCount += 1
            }

            let sessionKey = ride.sessionID.uuidString
            if shouldReplaceHighest(
                candidate: evidence,
                candidateSessionKey: sessionKey,
                current: highestEvidence,
                currentSessionKey: highestSessionKey
            ) {
                highestEvidence = evidence
                highestSessionKey = sessionKey
            }
        }

        let acceptedPeakPowerRideCount = gapFreePeakPowerRideCount + partialPeakPowerRideCount
        let peakPowerAvailability: RidePowerStatisticsAvailability
        if periodRides.isEmpty {
            peakPowerAvailability = .noRides
        } else if acceptedPeakPowerRideCount == 0 {
            peakPowerAvailability = .unavailable
        } else if gapFreePeakPowerRideCount == periodRides.count {
            peakPowerAvailability = .complete
        } else {
            peakPowerAvailability = .partial
        }

        return RidePowerStatisticsSummary(
            period: period,
            rideCount: periodRides.count,
            acceptedPeakPowerRideCount: acceptedPeakPowerRideCount,
            gapFreePeakPowerRideCount: gapFreePeakPowerRideCount,
            partialPeakPowerRideCount: partialPeakPowerRideCount,
            unavailablePeakPowerRideCount: unavailablePeakPowerRideCount,
            peakPowerAvailability: peakPowerAvailability,
            highestAcceptedObservedPowerWatts: highestEvidence?.powerWatts,
            highestAcceptedObservedPowerSessionID: highestEvidence?.sessionID,
            highestAcceptedObservedPowerContinuity: highestEvidence?.observationContinuity,
            highestAcceptedObservedPowerConfirmedModeKey: highestEvidence?.confirmedModeKey,
            vehicleIdentityKey: selectedSourceScope?.vehicleIdentityKey,
            identityAuthority: selectedSourceScope?.identityAuthority,
            evidenceAuthority: selectedSourceScope?.evidenceAuthority
        )
    }

    private struct PeriodWindow {
        let interval: DateInterval?

        func contains(_ date: Date) -> Bool {
            guard let interval else { return true }
            return date >= interval.start && date < interval.end
        }
    }

    private static func shouldReplaceHighest(
        candidate: CompletedRidePeakPowerEvidence,
        candidateSessionKey: String,
        current: CompletedRidePeakPowerEvidence?,
        currentSessionKey: String?
    ) -> Bool {
        guard let current else { return true }

        if candidate.powerWatts != current.powerWatts {
            return candidate.powerWatts > current.powerWatts
        }

        guard let currentSessionKey else { return true }
        return candidateSessionKey < currentSessionKey
    }

    /// Select period membership before allowing unrelated historical conflicts to invalidate the
    /// requested summary. Once any copy of a session is a period candidate, every supplied copy of
    /// that session remains relevant to identity reconciliation because disagreement could make
    /// membership or peak evidence ambiguous.
    private static func selectedAndDeduplicated(
        _ rides: [RidePowerStatisticsRide],
        selectedWindow: PeriodWindow
    ) throws -> [RidePowerStatisticsRide] {
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
        _ rides: [RidePowerStatisticsRide]
    ) throws -> [RidePowerStatisticsRide] {
        var recordsBySessionID: [UUID: RidePowerStatisticsRide] = [:]
        var uniqueRides: [RidePowerStatisticsRide] = []
        uniqueRides.reserveCapacity(rides.count)

        for ride in rides {
            if let existing = recordsBySessionID[ride.sessionID] {
                guard existing == ride else {
                    throw RidePowerStatisticsError.sessionConflict(ride.sessionID)
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
                throw RidePowerStatisticsError.invalidReferenceDate
            }
            return PeriodWindow(interval: interval)
        case .yesterday:
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: referenceDate),
                  let interval = calendar.dateInterval(of: .day, for: yesterday) else {
                throw RidePowerStatisticsError.invalidReferenceDate
            }
            return PeriodWindow(interval: interval)
        case .week:
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: referenceDate) else {
                throw RidePowerStatisticsError.invalidReferenceDate
            }
            return PeriodWindow(interval: interval)
        case .month:
            guard let interval = calendar.dateInterval(of: .month, for: referenceDate) else {
                throw RidePowerStatisticsError.invalidReferenceDate
            }
            return PeriodWindow(interval: interval)
        case .year:
            guard let interval = calendar.dateInterval(of: .year, for: referenceDate) else {
                throw RidePowerStatisticsError.invalidReferenceDate
            }
            return PeriodWindow(interval: interval)
        }
    }
}
