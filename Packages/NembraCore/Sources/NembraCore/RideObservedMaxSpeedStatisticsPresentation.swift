import Foundation

public enum RideObservedMaxSpeedStatisticsPresentationError: Error, Equatable, Sendable {
    case invalidSummary
}

public enum RideObservedMaxSpeedStatisticsPresentationState: String, Codable, Equatable, Sendable {
    case noCompletedRides
    case observedMaximumUnavailable
    case partialQualifiedEvidence
    case completeQualifiedEvidence
}

/// UI/accessibility-safe projection of observed-maximum statistics.
/// The numeric value always remains an accepted observed measurement, never a
/// perfect continuous-time physical maximum or a claim about throttle/rated power.
public struct RideObservedMaxSpeedStatisticsPresentation: Equatable, Sendable {
    public let period: RideStatisticsPeriod
    public let state: RideObservedMaxSpeedStatisticsPresentationState
    public let rideCount: Int
    public let ridesSupportingObservedMaximum: Int
    public let ridesWithNoObservedPeak: Int
    public let ridesWithUnqualifiedObservedPeak: Int
    public let highestQualifiedObservedSpeedMetersPerSecond: Double?
    public let highestQualifiedObservedSpeedSessionID: UUID?
    public let highestQualifiedObservedSpeedSource: SpeedTelemetrySource?
    public let highestQualifiedObservedSpeedAccuracyMetersPerSecond: Double?
    public let permitsCompletePeriodObservedMaximumWording: Bool
    public let requiresIncompleteEvidenceDisclosure: Bool

    fileprivate init(
        period: RideStatisticsPeriod,
        state: RideObservedMaxSpeedStatisticsPresentationState,
        rideCount: Int,
        ridesSupportingObservedMaximum: Int,
        ridesWithNoObservedPeak: Int,
        ridesWithUnqualifiedObservedPeak: Int,
        highestQualifiedObservedSpeedMetersPerSecond: Double?,
        highestQualifiedObservedSpeedSessionID: UUID?,
        highestQualifiedObservedSpeedSource: SpeedTelemetrySource?,
        highestQualifiedObservedSpeedAccuracyMetersPerSecond: Double?,
        permitsCompletePeriodObservedMaximumWording: Bool,
        requiresIncompleteEvidenceDisclosure: Bool
    ) {
        self.period = period
        self.state = state
        self.rideCount = rideCount
        self.ridesSupportingObservedMaximum = ridesSupportingObservedMaximum
        self.ridesWithNoObservedPeak = ridesWithNoObservedPeak
        self.ridesWithUnqualifiedObservedPeak = ridesWithUnqualifiedObservedPeak
        self.highestQualifiedObservedSpeedMetersPerSecond = highestQualifiedObservedSpeedMetersPerSecond
        self.highestQualifiedObservedSpeedSessionID = highestQualifiedObservedSpeedSessionID
        self.highestQualifiedObservedSpeedSource = highestQualifiedObservedSpeedSource
        self.highestQualifiedObservedSpeedAccuracyMetersPerSecond = highestQualifiedObservedSpeedAccuracyMetersPerSecond
        self.permitsCompletePeriodObservedMaximumWording = permitsCompletePeriodObservedMaximumWording
        self.requiresIncompleteEvidenceDisclosure = requiresIncompleteEvidenceDisclosure
    }
}

public enum RideObservedMaxSpeedStatisticsPresenter {
    public static func present(
        _ summary: RideObservedMaxSpeedStatisticsSummary
    ) throws -> RideObservedMaxSpeedStatisticsPresentation {
        guard summary.rideCount >= 0,
              summary.qualifyingRideCount >= 0,
              summary.peakUnavailableRideCount >= 0,
              summary.unqualifiedObservedPeakRideCount >= 0 else {
            throw RideObservedMaxSpeedStatisticsPresentationError.invalidSummary
        }

        let excluded = summary.peakUnavailableRideCount.addingReportingOverflow(
            summary.unqualifiedObservedPeakRideCount
        )
        let reconciled = summary.qualifyingRideCount.addingReportingOverflow(excluded.partialValue)
        guard !excluded.overflow,
              !reconciled.overflow,
              reconciled.partialValue == summary.rideCount else {
            throw RideObservedMaxSpeedStatisticsPresentationError.invalidSummary
        }

        let hasSpeed = summary.highestQualifiedObservedSpeedMetersPerSecond != nil
        let hasSession = summary.highestQualifiedObservedSpeedSessionID != nil
        let hasSource = summary.highestQualifiedObservedSpeedSource != nil
        guard hasSpeed == hasSession,
              hasSpeed == hasSource,
              hasSpeed == (summary.qualifyingRideCount > 0) else {
            throw RideObservedMaxSpeedStatisticsPresentationError.invalidSummary
        }

        if let speed = summary.highestQualifiedObservedSpeedMetersPerSecond {
            guard speed.isFinite, speed >= 0 else {
                throw RideObservedMaxSpeedStatisticsPresentationError.invalidSummary
            }
        }
        if let source = summary.highestQualifiedObservedSpeedSource, source == .motionAssist {
            throw RideObservedMaxSpeedStatisticsPresentationError.invalidSummary
        }
        if let accuracy = summary.highestQualifiedObservedSpeedAccuracyMetersPerSecond {
            guard hasSpeed, accuracy.isFinite, accuracy >= 0 else {
                throw RideObservedMaxSpeedStatisticsPresentationError.invalidSummary
            }
        }

        let state: RideObservedMaxSpeedStatisticsPresentationState
        switch summary.availability {
        case .noRides:
            guard summary.rideCount == 0,
                  summary.qualifyingRideCount == 0,
                  excluded.partialValue == 0,
                  !hasSpeed,
                  summary.highestQualifiedObservedSpeedAccuracyMetersPerSecond == nil else {
                throw RideObservedMaxSpeedStatisticsPresentationError.invalidSummary
            }
            state = .noCompletedRides
        case .unavailable:
            guard summary.rideCount > 0,
                  summary.qualifyingRideCount == 0,
                  excluded.partialValue == summary.rideCount,
                  !hasSpeed,
                  summary.highestQualifiedObservedSpeedAccuracyMetersPerSecond == nil else {
                throw RideObservedMaxSpeedStatisticsPresentationError.invalidSummary
            }
            state = .observedMaximumUnavailable
        case .partial:
            guard summary.rideCount > 0,
                  summary.qualifyingRideCount > 0,
                  summary.qualifyingRideCount < summary.rideCount,
                  excluded.partialValue > 0,
                  hasSpeed else {
                throw RideObservedMaxSpeedStatisticsPresentationError.invalidSummary
            }
            state = .partialQualifiedEvidence
        case .complete:
            guard summary.rideCount > 0,
                  summary.qualifyingRideCount == summary.rideCount,
                  excluded.partialValue == 0,
                  hasSpeed else {
                throw RideObservedMaxSpeedStatisticsPresentationError.invalidSummary
            }
            state = .completeQualifiedEvidence
        }

        let permitsCompleteWording = state == .completeQualifiedEvidence
        let requiresIncompleteDisclosure = state == .partialQualifiedEvidence
        guard summary.permitsCompletePeriodObservedMaximumWording == permitsCompleteWording,
              summary.requiresIncompleteEvidenceDisclosure == requiresIncompleteDisclosure else {
            throw RideObservedMaxSpeedStatisticsPresentationError.invalidSummary
        }

        return RideObservedMaxSpeedStatisticsPresentation(
            period: summary.period,
            state: state,
            rideCount: summary.rideCount,
            ridesSupportingObservedMaximum: summary.qualifyingRideCount,
            ridesWithNoObservedPeak: summary.peakUnavailableRideCount,
            ridesWithUnqualifiedObservedPeak: summary.unqualifiedObservedPeakRideCount,
            highestQualifiedObservedSpeedMetersPerSecond: summary.highestQualifiedObservedSpeedMetersPerSecond,
            highestQualifiedObservedSpeedSessionID: summary.highestQualifiedObservedSpeedSessionID,
            highestQualifiedObservedSpeedSource: summary.highestQualifiedObservedSpeedSource,
            highestQualifiedObservedSpeedAccuracyMetersPerSecond: summary.highestQualifiedObservedSpeedAccuracyMetersPerSecond,
            permitsCompletePeriodObservedMaximumWording: permitsCompleteWording,
            requiresIncompleteEvidenceDisclosure: requiresIncompleteDisclosure
        )
    }
}
