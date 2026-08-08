import Foundation

public enum RideObservedMaxSpeedStatisticsError: Error, Equatable, Sendable {
    case invalidRide
    case invalidReferenceDate
    case sessionMismatch
    case continuityMismatch
    case evidenceMismatch
    case sessionConflict(UUID)
}

/// Whether one completed ride can contribute to a selected-period observed maximum.
///
/// A ride is included only when its durable completed-ride peak exactly matches the
/// same-ride `RideObservedPeakReadiness` audit and that audit is ready under its
/// caller-supplied telemetry-quality policy. A numeric peak that fails quality or
/// continuity checks remains real evidence for that ride but is intentionally not
/// promoted into the period statistic.
public enum RideObservedMaxSpeedRideEligibility: String, Codable, Equatable, Sendable {
    case includedQualifiedObservedPeak
    case excludedPeakUnavailable
    case excludedUnqualifiedObservedPeak
}

/// One completed ride prepared for selected-period observed-maximum statistics.
///
/// The qualified number is still the highest **accepted observed measurement**
/// retained for that ride, not an unknowable perfect continuous-time top speed.
/// Calendar attribution is presentation/statistics policy only and never becomes
/// speed or duration evidence.
public struct RideObservedMaxSpeedStatisticsRide: Equatable, Sendable {
    public let sessionID: UUID
    public let attributedDate: Date
    public let eligibility: RideObservedMaxSpeedRideEligibility
    public let qualifiedObservedPeakMetersPerSecond: Double?
    public let qualifiedObservedPeakSource: SpeedTelemetrySource?
    public let qualifiedObservedPeakSpeedAccuracyMetersPerSecond: Double?

    package let completedPeakEvidence: CompletedRidePeakSpeedEvidence?
    package let readiness: RideObservedPeakReadiness

    package init(
        completedRide: CompletedRideEvidence,
        completedPeak: CompletedRidePeakSpeedEvidence?,
        readiness: RideObservedPeakReadiness,
        calendarAttribution: RideStatisticsCalendarAttribution
    ) throws {
        guard readiness.sessionID == completedRide.sessionID else {
            throw RideObservedMaxSpeedStatisticsError.sessionMismatch
        }

        let attributedDate: Date
        switch calendarAttribution {
        case .rideBegan: attributedDate = completedRide.beganAtDate
        case .rideEnded: attributedDate = completedRide.endedAtDate
        }
        guard attributedDate.timeIntervalSinceReferenceDate.isFinite else {
            throw RideObservedMaxSpeedStatisticsError.invalidRide
        }

        switch (readiness.peakEvidence, completedPeak) {
        case (nil, nil):
            break
        case let (.some(livePeak), .some(durablePeak)):
            do {
                try durablePeak.validate(against: completedRide)
            } catch let error as CompletedRidePeakSpeedEvidenceError {
                switch error {
                case .sessionMismatch:
                    throw RideObservedMaxSpeedStatisticsError.sessionMismatch
                case .continuityMismatch:
                    throw RideObservedMaxSpeedStatisticsError.continuityMismatch
                case .invalidEvidence:
                    throw RideObservedMaxSpeedStatisticsError.invalidRide
                }
            }

            guard durablePeak.sessionID == livePeak.sessionID,
                  durablePeak.beganAfterKnownObservationGap == livePeak.beganAfterKnownObservationGap,
                  durablePeak.source == livePeak.policy.source,
                  durablePeak.metersPerSecond == livePeak.peakEvidence.peak.metersPerSecond,
                  durablePeak.speedAccuracyMetersPerSecond == livePeak.peakEvidence.peak.speedAccuracyMetersPerSecond,
                  durablePeak.maximumAllowedSpeedAccuracyMetersPerSecond == livePeak.policy.maximumSpeedAccuracyMetersPerSecond,
                  durablePeak.acceptedSampleCount == livePeak.peakEvidence.acceptedSampleCount,
                  durablePeak.qualityRejectedSampleCount == livePeak.peakEvidence.qualityRejectedSampleCount,
                  durablePeak.knownInterruptionCount == livePeak.peakEvidence.knownInterruptionCount,
                  durablePeak.observationContinuity == livePeak.peakEvidence.continuity else {
                throw RideObservedMaxSpeedStatisticsError.evidenceMismatch
            }
        case (.some, nil), (nil, .some):
            throw RideObservedMaxSpeedStatisticsError.evidenceMismatch
        }

        let eligibility: RideObservedMaxSpeedRideEligibility
        let qualifiedPeak: Double?
        let qualifiedSource: SpeedTelemetrySource?
        let qualifiedAccuracy: Double?

        if readiness.isReady {
            guard readiness.failures.isEmpty,
                  readiness.telemetryQuality.isQualified,
                  readiness.foreignSourceCallbackCount == 0,
                  readiness.knownSelectedSourceInterruptionCount == 0,
                  let completedPeak,
                  completedPeak.observationContinuity == .noRecordedSelectedSourceEvidenceLoss,
                  completedPeak.source != .motionAssist,
                  completedPeak.metersPerSecond.isFinite,
                  completedPeak.metersPerSecond >= 0 else {
                throw RideObservedMaxSpeedStatisticsError.evidenceMismatch
            }
            eligibility = .includedQualifiedObservedPeak
            qualifiedPeak = completedPeak.metersPerSecond
            qualifiedSource = completedPeak.source
            qualifiedAccuracy = completedPeak.speedAccuracyMetersPerSecond
        } else {
            eligibility = readiness.peakEvidence == nil
                ? .excludedPeakUnavailable
                : .excludedUnqualifiedObservedPeak
            qualifiedPeak = nil
            qualifiedSource = nil
            qualifiedAccuracy = nil
        }

        self.sessionID = completedRide.sessionID
        self.attributedDate = attributedDate
        self.eligibility = eligibility
        self.qualifiedObservedPeakMetersPerSecond = qualifiedPeak
        self.qualifiedObservedPeakSource = qualifiedSource
        self.qualifiedObservedPeakSpeedAccuracyMetersPerSecond = qualifiedAccuracy
        self.completedPeakEvidence = completedPeak
        self.readiness = readiness
    }
}

public enum RideObservedMaxSpeedStatisticsAvailability: String, Codable, Equatable, Sendable {
    case noRides
    case unavailable
    case partial
    case complete
}

/// Selected-period maximum of quality-qualified completed-ride observed peaks.
/// This summarizes only the supplied completed rides. Even complete output is the
/// highest accepted observed measurement, not a perfect continuous-time maximum.
public struct RideObservedMaxSpeedStatisticsSummary: Equatable, Sendable {
    public let period: RideStatisticsPeriod
    public let rideCount: Int
    public let qualifyingRideCount: Int
    public let peakUnavailableRideCount: Int
    public let unqualifiedObservedPeakRideCount: Int
    public let availability: RideObservedMaxSpeedStatisticsAvailability
    public let highestQualifiedObservedSpeedMetersPerSecond: Double?
    public let highestQualifiedObservedSpeedSessionID: UUID?
    public let highestQualifiedObservedSpeedSource: SpeedTelemetrySource?
    public let highestQualifiedObservedSpeedAccuracyMetersPerSecond: Double?

    public var excludedRideCount: Int {
        peakUnavailableRideCount + unqualifiedObservedPeakRideCount
    }

    public var permitsCompletePeriodObservedMaximumWording: Bool {
        availability == .complete
    }

    public var requiresIncompleteEvidenceDisclosure: Bool {
        availability == .partial
    }
}

public enum RideObservedMaxSpeedStatisticsAggregator {
    public static func summarize(
        period: RideStatisticsPeriod,
        rides: [RideObservedMaxSpeedStatisticsRide],
        referenceDate: Date,
        calendar: Calendar
    ) throws -> RideObservedMaxSpeedStatisticsSummary {
        guard referenceDate.timeIntervalSinceReferenceDate.isFinite else {
            throw RideObservedMaxSpeedStatisticsError.invalidReferenceDate
        }
        if period != .allTime, !isRepresentable(referenceDate, in: calendar) {
            throw RideObservedMaxSpeedStatisticsError.invalidReferenceDate
        }

        let selectedWindow = try periodWindow(for: period, referenceDate: referenceDate, calendar: calendar)
        let periodRides = try selectedAndDeduplicated(rides, selectedWindow: selectedWindow)
        guard periodRides.allSatisfy({ isRepresentable($0.attributedDate, in: calendar) }) else {
            throw RideObservedMaxSpeedStatisticsError.invalidRide
        }

        var qualifyingRideCount = 0
        var peakUnavailableRideCount = 0
        var unqualifiedObservedPeakRideCount = 0
        var highestSpeed: Double?
        var highestSessionID: UUID?
        var highestSessionKey: String?
        var highestSource: SpeedTelemetrySource?
        var highestAccuracy: Double?

        for ride in periodRides {
            switch ride.eligibility {
            case .includedQualifiedObservedPeak:
                guard let speed = ride.qualifiedObservedPeakMetersPerSecond,
                      let source = ride.qualifiedObservedPeakSource,
                      source != .motionAssist,
                      speed.isFinite,
                      speed >= 0 else {
                    throw RideObservedMaxSpeedStatisticsError.invalidRide
                }
                if let accuracy = ride.qualifiedObservedPeakSpeedAccuracyMetersPerSecond {
                    guard accuracy.isFinite, accuracy >= 0 else {
                        throw RideObservedMaxSpeedStatisticsError.invalidRide
                    }
                }
                qualifyingRideCount += 1
                let sessionKey = ride.sessionID.uuidString
                if shouldReplaceMaximum(
                    candidateSpeed: speed,
                    candidateSessionKey: sessionKey,
                    currentSpeed: highestSpeed,
                    currentSessionKey: highestSessionKey
                ) {
                    highestSpeed = speed
                    highestSessionID = ride.sessionID
                    highestSessionKey = sessionKey
                    highestSource = source
                    highestAccuracy = ride.qualifiedObservedPeakSpeedAccuracyMetersPerSecond
                }
            case .excludedPeakUnavailable:
                guard ride.qualifiedObservedPeakMetersPerSecond == nil,
                      ride.qualifiedObservedPeakSource == nil,
                      ride.qualifiedObservedPeakSpeedAccuracyMetersPerSecond == nil else {
                    throw RideObservedMaxSpeedStatisticsError.invalidRide
                }
                peakUnavailableRideCount += 1
            case .excludedUnqualifiedObservedPeak:
                guard ride.qualifiedObservedPeakMetersPerSecond == nil,
                      ride.qualifiedObservedPeakSource == nil,
                      ride.qualifiedObservedPeakSpeedAccuracyMetersPerSecond == nil else {
                    throw RideObservedMaxSpeedStatisticsError.invalidRide
                }
                unqualifiedObservedPeakRideCount += 1
            }
        }

        let availability: RideObservedMaxSpeedStatisticsAvailability
        if periodRides.isEmpty {
            availability = .noRides
        } else if qualifyingRideCount == 0 {
            availability = .unavailable
        } else if qualifyingRideCount == periodRides.count {
            availability = .complete
        } else {
            availability = .partial
        }

        if qualifyingRideCount == 0 {
            guard highestSpeed == nil, highestSessionID == nil, highestSource == nil, highestAccuracy == nil else {
                throw RideObservedMaxSpeedStatisticsError.invalidRide
            }
        } else {
            guard highestSpeed != nil, highestSessionID != nil, highestSource != nil else {
                throw RideObservedMaxSpeedStatisticsError.invalidRide
            }
        }

        return RideObservedMaxSpeedStatisticsSummary(
            period: period,
            rideCount: periodRides.count,
            qualifyingRideCount: qualifyingRideCount,
            peakUnavailableRideCount: peakUnavailableRideCount,
            unqualifiedObservedPeakRideCount: unqualifiedObservedPeakRideCount,
            availability: availability,
            highestQualifiedObservedSpeedMetersPerSecond: highestSpeed,
            highestQualifiedObservedSpeedSessionID: highestSessionID,
            highestQualifiedObservedSpeedSource: highestSource,
            highestQualifiedObservedSpeedAccuracyMetersPerSecond: highestAccuracy
        )
    }

    private struct PeriodWindow {
        let interval: DateInterval?
        func contains(_ date: Date) -> Bool {
            guard let interval else { return true }
            return date >= interval.start && date < interval.end
        }
    }

    private static func shouldReplaceMaximum(
        candidateSpeed: Double,
        candidateSessionKey: String,
        currentSpeed: Double?,
        currentSessionKey: String?
    ) -> Bool {
        guard let currentSpeed else { return true }
        if candidateSpeed != currentSpeed { return candidateSpeed > currentSpeed }
        guard let currentSessionKey else { return true }
        return candidateSessionKey < currentSessionKey
    }

    private static func selectedAndDeduplicated(
        _ rides: [RideObservedMaxSpeedStatisticsRide],
        selectedWindow: PeriodWindow
    ) throws -> [RideObservedMaxSpeedStatisticsRide] {
        guard selectedWindow.interval != nil else { return try deduplicated(rides) }
        let selectedSessionIDs = Set(
            rides.lazy.filter { selectedWindow.contains($0.attributedDate) }.map(\.sessionID)
        )
        guard !selectedSessionIDs.isEmpty else { return [] }
        let relevantRides = rides.filter { selectedSessionIDs.contains($0.sessionID) }
        return try deduplicated(relevantRides).filter { selectedWindow.contains($0.attributedDate) }
    }

    private static func deduplicated(
        _ rides: [RideObservedMaxSpeedStatisticsRide]
    ) throws -> [RideObservedMaxSpeedStatisticsRide] {
        var recordsBySessionID: [UUID: RideObservedMaxSpeedStatisticsRide] = [:]
        var uniqueRides: [RideObservedMaxSpeedStatisticsRide] = []
        uniqueRides.reserveCapacity(rides.count)
        for ride in rides {
            if let existing = recordsBySessionID[ride.sessionID] {
                guard existing == ride else {
                    throw RideObservedMaxSpeedStatisticsError.sessionConflict(ride.sessionID)
                }
                continue
            }
            recordsBySessionID[ride.sessionID] = ride
            uniqueRides.append(ride)
        }
        return uniqueRides
    }

    private static func isRepresentable(_ date: Date, in calendar: Calendar) -> Bool {
        guard let dayInterval = calendar.dateInterval(of: .day, for: date) else { return false }
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
                throw RideObservedMaxSpeedStatisticsError.invalidReferenceDate
            }
            return PeriodWindow(interval: interval)
        case .yesterday:
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: referenceDate),
                  let interval = calendar.dateInterval(of: .day, for: yesterday) else {
                throw RideObservedMaxSpeedStatisticsError.invalidReferenceDate
            }
            return PeriodWindow(interval: interval)
        case .week:
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: referenceDate) else {
                throw RideObservedMaxSpeedStatisticsError.invalidReferenceDate
            }
            return PeriodWindow(interval: interval)
        case .month:
            guard let interval = calendar.dateInterval(of: .month, for: referenceDate) else {
                throw RideObservedMaxSpeedStatisticsError.invalidReferenceDate
            }
            return PeriodWindow(interval: interval)
        case .year:
            guard let interval = calendar.dateInterval(of: .year, for: referenceDate) else {
                throw RideObservedMaxSpeedStatisticsError.invalidReferenceDate
            }
            return PeriodWindow(interval: interval)
        }
    }
}
